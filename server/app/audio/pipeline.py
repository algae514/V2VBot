import asyncio
import os
from typing import Optional, Callable
import time

import numpy as np
from aiortc import MediaStreamTrack

from .vad_silero import SileroVAD
from ..stt.whisper_faster import WhisperFaster
from ..llm.gemini import GeminiLLM


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
		
		self.buffer_audio: list[np.ndarray] = []  # Buffer 16kHz audio for Whisper
		self.dc_send = dc_send
		self.frame_count = 0
		self.last_utterance_text = ""  # Keep last transcription for turn_complete
		
		print(f"AudioPipeline initialized: Sequential mode with LLM integration")

	async def handle_audio_frame(self, audio_16k: np.ndarray) -> None:
		"""
		Process 16kHz audio frame.
		
		Args:
			audio_16k: float32 mono samples at 16kHz
		"""
		self.frame_count += 1
		
		# Process with VAD (expects 16kHz)
		# Returns: started=bool, ended="utterance_end"|"turn_end"|None
		started, event = self.vad.process(audio_16k)
		
		if started:
			self.dc_send('{"event":"turn_started"}')
			# Clear last utterance when starting new speech
			self.last_utterance_text = ""
		
		# Buffer 16kHz audio when VAD is active (during speech)
		if self.vad.active:
			self.buffer_audio.append(audio_16k.copy())
		
		# Handle different pause events
		if event == "utterance_end":
			# Short pause (1.5s) - natural break, transcribe and continue listening
			await self._on_utterance_end(is_turn_complete=False)
		elif event == "turn_end":
			# Long pause (2s) - user is done talking, ready for LLM
			# Just send turn_complete with last transcription (no need to re-transcribe)
			await self._on_turn_complete()

	async def _on_utterance_end(self, is_turn_complete: bool) -> None:
		"""
		Transcribe utterance on short pause (1.5s).
		
		Args:
			is_turn_complete: Always False for this method
		"""
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
			utt_audio = np.concatenate(self.buffer_audio)
			duration_s = len(utt_audio) / 16000
			
			print(f"[UTTERANCE] Transcribing {duration_s:.2f}s of audio...")
			start_time = time.time()
			
			loop = asyncio.get_running_loop()
			text = await loop.run_in_executor(None, self.whisper.transcribe, utt_audio)
			
			elapsed = time.time() - start_time
			print(f"[UTTERANCE] Transcription took {elapsed:.2f}s")
			if text:
				print(f"[UTTERANCE] Result: '{text}'")
			
			# Save transcription for potential turn_complete
			self.last_utterance_text = text if text else ""
			
			# Clear buffer (but keep VAD active to detect turn_end)
			self.buffer_audio.clear()
			
			# Send turn_final event
			self.dc_send('{"event":"turn_final","text":"' + self.last_utterance_text.replace('"', '\\"') + '"}')
				
		except Exception as e:
			print(f"[UTTERANCE] Error: {e}")
			import traceback
			traceback.print_exc()
	
	async def _on_turn_complete(self) -> None:
		"""
		Send turn_complete event on long pause (2s) and generate LLM response.
		Uses previously transcribed text, no re-transcription needed.
		"""
		try:
			print(f"[TURN-COMPLETE] Long pause detected, ready for LLM")
			print(f"[TURN-COMPLETE] User: '{self.last_utterance_text}'")
			
			# Reset VAD for next turn
			self.vad.reset()
			
			# Send turn_complete with previously transcribed text
			self.dc_send('{"event":"turn_complete","text":"' + self.last_utterance_text.replace('"', '\\"') + '"}')
			
			# Generate LLM response if available
			if self.llm and self.last_utterance_text.strip():
				await self._generate_llm_response(self.last_utterance_text)
			
			# Clear state
			self.last_utterance_text = ""
			
		except Exception as e:
			print(f"[TURN-COMPLETE] Error: {e}")
			import traceback
			traceback.print_exc()
	
	async def _generate_llm_response(self, user_text: str) -> None:
		"""
		Generate and stream LLM response.
		
		Args:
			user_text: User's transcribed text
		"""
		try:
			# Send llm_started event
			self.dc_send('{"event":"llm_started"}')
			print(f"[LLM] Generating response...")
			
			# Stream response chunks
			full_response = ""
			async for chunk in self.llm.generate_streaming(user_text):
				full_response += chunk
				# Send each chunk as llm_chunk event
				self.dc_send('{"event":"llm_chunk","text":"' + chunk.replace('"', '\\"') + '"}')
			
			# Send llm_complete with full response
			print(f"[LLM] Response: '{full_response}'")
			self.dc_send('{"event":"llm_complete","text":"' + full_response.replace('"', '\\"') + '"}')
			
		except Exception as e:
			print(f"[LLM] Error: {e}")
			self.dc_send('{"event":"llm_error","error":"' + str(e).replace('"', '\\"') + '"}')
			import traceback
			traceback.print_exc()
