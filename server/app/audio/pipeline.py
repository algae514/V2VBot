import asyncio
import os
from typing import Optional, Callable
import time
import logging

import numpy as np
from aiortc import MediaStreamTrack

from .vad_silero import SileroVAD
from ..stt.whisper_faster import WhisperFaster
from ..llm.gemini import GeminiLLM
from ..tts.melo_tts import MeloTTS

logger = logging.getLogger(__name__)


class AudioPipeline:
	def __init__(self, dc_send: Callable[[str], None]):
		# Re-enable VAD with fallback to energy-based detection if model not available
		model_path = os.getenv("SILERO_VAD_ONNX", "models/silero_vad.onnx")
		# Using original working VAD settings
		self.vad = SileroVAD(model_path=model_path, threshold=0.3, window_ms=20, end_ms=1500)
		
		# Use Faster Whisper for better accuracy with accents
		whisper_model = os.getenv("WHISPER_MODEL", "small.en")
		self.whisper = WhisperFaster(model_size=whisper_model, device="cpu", compute_type="int8")
		
		# Initialize Gemini LLM
		try:
			self.llm = GeminiLLM()
			print(f"LLM enabled: Gemini")
		except Exception as e:
			print(f"LLM disabled: {e}")
			self.llm = None
		
		# Initialize TTS (HTTP-based service)
		try:
			self.tts = MeloTTS(device="cpu", language="EN")
			# Don't set to None if not ready yet - initialization is async and will complete later
			if self.tts.is_ready():
				print(f"TTS enabled: HTTP-based TTS service")
			else:
				print(f"TTS initialized but not ready yet (async initialization in progress, TTS_URL: {os.getenv('TTS_URL', 'not set')})")
				# Keep self.tts - it will become ready after async initialization completes
		except Exception as e:
			print(f"TTS disabled: {e}")
			self.tts = None
		
		self.buffer_audio: list[np.ndarray] = []  # Buffer 16kHz audio for Whisper
		self.dc_send = dc_send
		self.frame_count = 0
		self.last_utterance_text = ""  # Keep last transcription for turn_complete
		self.tts_interrupted = False  # Flag to interrupt ongoing TTS
		
		print(f"AudioPipeline initialized: Sequential mode with LLM and TTS integration")

	async def _interrupt_tts(self) -> None:
		"""
		Interrupt any ongoing TTS synthesis when user starts speaking.
		"""
		if self.tts_interrupted:
			return  # Already interrupted
			
		self.tts_interrupted = True
		print("[TTS] Interrupted by user speech")
		
		# Send interruption event to frontend
		self.dc_send('{"event":"tts_interrupted"}')

	async def handle_audio_frame(self, audio_16k: np.ndarray) -> None:
		"""
		Process 16kHz audio frame.
		
		Args:
			audio_16k: float32 mono samples at 16kHz
		"""
		frame_start = time.time()
		self.frame_count += 1
		
		# Process with VAD (expects 16kHz)
		# Returns: started=bool, ended="utterance_end"|"turn_end"|None
		vad_start = time.time()
		started, event = self.vad.process(audio_16k)
		vad_latency = (time.time() - vad_start) * 1000
		
		if started:
			interrupt_start = time.time()
			self.dc_send('{"event":"turn_started"}')
			# Clear last utterance when starting new speech
			self.last_utterance_text = ""
			
			# Interrupt any ongoing TTS synthesis
			await self._interrupt_tts()
			interrupt_latency = (time.time() - interrupt_start) * 1000
			logger.info(f"[LATENCY] Turn started: VAD={vad_latency:.2f}ms, interrupt={interrupt_latency:.2f}ms")
		
		# Buffer 16kHz audio when VAD is active (during speech)
		buffer_start = time.time()
		if self.vad.active:
			self.buffer_audio.append(audio_16k.copy())
		buffer_latency = (time.time() - buffer_start) * 1000
		
		# Handle different pause events
		if event == "utterance_end":
			# Short pause (1.5s) - natural break, transcribe and continue listening
			await self._on_utterance_end(is_turn_complete=False)
		elif event == "turn_end":
			# Long pause (2s) - user is done talking, ready for LLM
			# Just send turn_complete with last transcription (no need to re-transcribe)
			await self._on_turn_complete()
		
		total_frame_latency = (time.time() - frame_start) * 1000
		# Only log if frame processing is unusually slow (>50ms) - normal frames are <1ms
		# This prevents log flooding since frames come every ~20ms
		if total_frame_latency > 50.0:
			logger.info(f"[LATENCY] Frame handle (slow): VAD={vad_latency:.2f}ms, buffer={buffer_latency:.2f}ms, TOTAL={total_frame_latency:.2f}ms")

	async def _on_utterance_end(self, is_turn_complete: bool) -> None:
		"""
		Transcribe utterance on short pause (1.5s).
		
		Args:
			is_turn_complete: Always False for this method
		"""
		utterance_start = time.time()
		try:
			if not self.buffer_audio:
				# No audio buffered, send empty result
				self.dc_send('{"event":"turn_final","text":""}')
				return
			
			# Check if Whisper is ready
			if not self.whisper.is_ready():
				self.dc_send('{"error":"Whisper not ready"}')
				return
			
			# Transcribe entire buffer
			concat_start = time.time()
			utt_audio = np.concatenate(self.buffer_audio)
			duration_s = len(utt_audio) / 16000
			concat_latency = (time.time() - concat_start) * 1000
			
			print(f"[UTTERANCE] Transcribing {duration_s:.2f}s of audio...")
			logger.info(f"[LATENCY] Utterance end: audio_concat={concat_latency:.2f}ms, duration={duration_s:.2f}s")
			
			stt_start = time.time()
			loop = asyncio.get_running_loop()
			text = await loop.run_in_executor(None, self.whisper.transcribe, utt_audio)
			stt_latency = (time.time() - stt_start) * 1000
			
			elapsed = time.time() - utterance_start
			print(f"[UTTERANCE] Transcription took {elapsed:.2f}s")
			logger.info(f"[LATENCY] STT transcription: {stt_latency:.2f}ms (audio_duration={duration_s:.2f}s, ratio={stt_latency/(duration_s*1000):.2f}x)")
			if text:
				print(f"[UTTERANCE] Result: '{text}'")
			
			# Save transcription for potential turn_complete
			self.last_utterance_text = text if text else ""
			
			# Clear buffer (but keep VAD active to detect turn_end)
			self.buffer_audio.clear()
			
			# Send turn_final event
			send_start = time.time()
			escaped_text = self.last_utterance_text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
			self.dc_send('{"event":"turn_final","text":"' + escaped_text + '"}')
			send_latency = (time.time() - send_start) * 1000
			
			total_latency = (time.time() - utterance_start) * 1000
			logger.info(f"[LATENCY] Utterance end total: concat={concat_latency:.2f}ms, STT={stt_latency:.2f}ms, send={send_latency:.2f}ms, TOTAL={total_latency:.2f}ms")
				
		except Exception as e:
			total_latency = (time.time() - utterance_start) * 1000
			print(f"[UTTERANCE] Error: {e}")
			logger.error(f"[LATENCY] Utterance end error after {total_latency:.2f}ms: {e}")
			import traceback
			traceback.print_exc()
	
	async def _on_turn_complete(self) -> None:
		"""
		Send turn_complete event on long pause (2s) and generate LLM response.
		Uses previously transcribed text, no re-transcription needed.
		"""
		turn_start = time.time()
		try:
			print(f"[TURN-COMPLETE] Long pause detected, ready for LLM")
			print(f"[TURN-COMPLETE] User: '{self.last_utterance_text}'")
			
			# Reset VAD for next turn
			vad_reset_start = time.time()
			self.vad.reset()
			vad_reset_latency = (time.time() - vad_reset_start) * 1000
			
			# Send turn_complete with previously transcribed text
			send_start = time.time()
			escaped_text = self.last_utterance_text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
			self.dc_send('{"event":"turn_complete","text":"' + escaped_text + '"}')
			send_latency = (time.time() - send_start) * 1000
			
			# Generate LLM response if available
			if self.llm and self.last_utterance_text.strip():
				await self._generate_llm_response(self.last_utterance_text)
			
			# Clear state
			self.last_utterance_text = ""
			
			total_latency = (time.time() - turn_start) * 1000
			logger.info(f"[LATENCY] Turn complete: vad_reset={vad_reset_latency:.2f}ms, send={send_latency:.2f}ms, TOTAL={total_latency:.2f}ms")
			
		except Exception as e:
			total_latency = (time.time() - turn_start) * 1000
			print(f"[TURN-COMPLETE] Error: {e}")
			logger.error(f"[LATENCY] Turn complete error after {total_latency:.2f}ms: {e}")
			import traceback
			traceback.print_exc()
	
	async def _generate_llm_response(self, user_text: str) -> None:
		"""
		Generate and stream LLM response, then synthesize to speech.
		
		Args:
			user_text: User's transcribed text
		"""
		llm_start = time.time()
		try:
			# Send llm_started event
			send_start = time.time()
			self.dc_send('{"event":"llm_started"}')
			send_latency = (time.time() - send_start) * 1000
			print(f"[LLM] Generating response...")
			logger.info(f"[LATENCY] LLM started: send_event={send_latency:.2f}ms")
			
			# Stream response chunks
			llm_gen_start = time.time()
			full_response = ""
			chunk_count = 0
			first_chunk_time = None
			last_chunk_time = None
			async for chunk in self.llm.generate_streaming(user_text):
				if first_chunk_time is None:
					first_chunk_time = time.time()
					ttfb = (first_chunk_time - llm_gen_start) * 1000
					logger.info(f"[LATENCY] LLM first chunk (TTFB): {ttfb:.2f}ms")
				
				chunk_start = time.time()
				full_response += chunk
				chunk_count += 1
				# Send each chunk as llm_chunk event
				print(f"[LLM] Sending chunk {chunk_count}: '{chunk}'")
				escaped_chunk = chunk.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
				self.dc_send('{"event":"llm_chunk","text":"' + escaped_chunk + '"}')
				chunk_latency = (time.time() - chunk_start) * 1000
				last_chunk_time = time.time()
				if chunk_latency > 1.0:  # Only log if chunk processing > 1ms
					logger.info(f"[LATENCY] LLM chunk {chunk_count}: send={chunk_latency:.2f}ms")
			
			llm_gen_latency = (time.time() - llm_gen_start) * 1000
			total_chunks = chunk_count
			avg_chunk_time = (llm_gen_latency / total_chunks) if total_chunks > 0 else 0
			logger.info(f"[LATENCY] LLM generation: total={llm_gen_latency:.2f}ms, chunks={total_chunks}, avg_chunk={avg_chunk_time:.2f}ms")
			
			# Send llm_complete with full response
			complete_start = time.time()
			print(f"[LLM] Response: '{full_response}'")
			escaped_response = full_response.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
			self.dc_send('{"event":"llm_complete","text":"' + escaped_response + '"}')
			complete_latency = (time.time() - complete_start) * 1000
			
			# Generate TTS if available
			print(f"[TTS] Checking TTS availability: self.tts={self.tts is not None}, is_ready()={self.tts.is_ready() if self.tts else False}, full_response.strip()={bool(full_response.strip())}")
			if self.tts and self.tts.is_ready() and full_response.strip():
				print(f"[TTS] ✅ All conditions met, calling _synthesize_response")
				await self._synthesize_response(full_response)
			else:
				print(f"[TTS] ❌ TTS not called - self.tts={self.tts is not None}, is_ready={self.tts.is_ready() if self.tts else False}, has_text={bool(full_response.strip())}")
			
			total_llm_latency = (time.time() - llm_start) * 1000
			logger.info(f"[LATENCY] LLM total: generation={llm_gen_latency:.2f}ms, complete_send={complete_latency:.2f}ms, TOTAL={total_llm_latency:.2f}ms")
			
		except Exception as e:
			total_llm_latency = (time.time() - llm_start) * 1000
			print(f"[LLM] Error: {e}")
			logger.error(f"[LATENCY] LLM error after {total_llm_latency:.2f}ms: {e}")
			self.dc_send('{"event":"llm_error","error":"' + str(e).replace('"', '\\"') + '"}')
			import traceback
			traceback.print_exc()
	
	async def _synthesize_response(self, text: str) -> None:
		"""
		Synthesize LLM response to speech and stream audio.
		
		Args:
			text: Text to synthesize
		"""
		tts_start = time.time()
		try:
			# Reset interruption flag for new synthesis
			self.tts_interrupted = False
			
			# Send tts_started event
			send_start = time.time()
			self.dc_send('{"event":"tts_started"}')
			send_latency = (time.time() - send_start) * 1000
			print(f"[TTS] Synthesizing response...")
			logger.info(f"[LATENCY] TTS started: send_event={send_latency:.2f}ms")
			
			# Stream TTS audio sentences
			sentence_count = 0
			total_synthesis_time = 0
			async for sentence_audio in self.tts.synthesize_sentences(text):
				# Check for interruption before processing each sentence
				if self.tts_interrupted:
					print(f"[TTS] Synthesis interrupted after {sentence_count} sentences")
					break
					
				sentence_count += 1
				duration = len(sentence_audio) / self.tts.get_sample_rate()
				print(f"[TTS] Generated sentence {sentence_count}, duration: {duration:.2f}s, samples: {len(sentence_audio)}")
				
				# Convert sentence audio to base64 for transmission
				encode_start = time.time()
				import base64
				# Ensure audio is in range [-1, 1] and convert to int16
				sentence_audio = np.clip(sentence_audio, -1.0, 1.0)
				audio_bytes = (sentence_audio * 32767).astype(np.int16).tobytes()
				audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
				encode_latency = (time.time() - encode_start) * 1000
				
				# Send sentence audio via DataChannel
				send_chunk_start = time.time()
				self.dc_send(f'{{"event":"tts_chunk","audio":"{audio_b64}","sample_rate":{self.tts.get_sample_rate()}}}')
				send_chunk_latency = (time.time() - send_chunk_start) * 1000
				
				if encode_latency > 5.0 or send_chunk_latency > 5.0:  # Only log if significant
					logger.info(f"[LATENCY] TTS sentence {sentence_count}: encode={encode_latency:.2f}ms, send={send_chunk_latency:.2f}ms")
			
			# Send appropriate completion event
			complete_start = time.time()
			if self.tts_interrupted:
				print(f"[TTS] Synthesis interrupted, {sentence_count} sentences generated")
				self.dc_send('{"event":"tts_interrupted"}')
			else:
				print(f"[TTS] Synthesis complete, {sentence_count} sentences generated")
				self.dc_send('{"event":"tts_complete"}')
			complete_latency = (time.time() - complete_start) * 1000
			
			total_tts_latency = (time.time() - tts_start) * 1000
			logger.info(f"[LATENCY] TTS total: send_event={send_latency:.2f}ms, complete_send={complete_latency:.2f}ms, sentences={sentence_count}, TOTAL={total_tts_latency:.2f}ms")
			
		except Exception as e:
			total_tts_latency = (time.time() - tts_start) * 1000
			print(f"[TTS] Error: {e}")
			logger.error(f"[LATENCY] TTS error after {total_tts_latency:.2f}ms: {e}")
			# Clean error message for JSON transmission
			error_msg = str(e).replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
			# Remove control characters that break JSON
			import re
			error_msg = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', error_msg)
			self.dc_send('{"event":"tts_error","error":"' + error_msg + '"}')
			import traceback
			traceback.print_exc()
