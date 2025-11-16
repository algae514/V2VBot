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
		# VAD settings - reduced end_ms for faster turn detection (lower latency)
		vad_end_ms = int(os.getenv("VAD_END_MS", "1000"))  # Default 1000ms for real-time conversation
		self.vad = SileroVAD(model_path=model_path, threshold=0.3, window_ms=20, end_ms=vad_end_ms)
		
		# Use Faster Whisper for better accuracy with accents
		# Auto-detect GPU if available, otherwise use CPU
		whisper_model = os.getenv("WHISPER_MODEL", "small.en")
		use_gpu = os.getenv("USE_GPU", "false").lower() in ("true", "1", "yes")
		whisper_device = None if use_gpu else "cpu"  # None = auto-detect, "cpu" = force CPU
		self.whisper = WhisperFaster(model_size=whisper_model, device=whisper_device, compute_type=None)
		
		# Initialize Gemini LLM
		try:
			self.llm = GeminiLLM()
			print(f"LLM enabled: Gemini")
		except Exception as e:
			print(f"LLM disabled: {e}")
			self.llm = None
		
		# Initialize TTS (Local MeloTTS with GPU support)
		try:
			# Device will be auto-detected based on USE_GPU env var
			self.tts = MeloTTS(device=None, language="EN")
			# Don't set to None if not ready yet - initialization is async and will complete later
			if self.tts.is_ready():
				device = self.tts.get_device()
				print(f"TTS enabled: Local MeloTTS on {device}")
			else:
				print(f"TTS initialized but not ready yet (async initialization in progress, device: {os.getenv('USE_GPU', 'auto-detect')})")
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
		Generate and stream LLM response, with streaming TTS (Phase 3).
		Start TTS synthesis as soon as complete sentences are available.
		
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
			
			# Initialize streaming TTS
			# Reset interruption flag for new synthesis
			self.tts_interrupted = False
			tts_started = False
			sentence_buffer = ""  # Accumulate chunks until we have complete sentences
			completed_sentences = set()  # Set of sentences already queued (for duplicate detection)
			tts_tasks = []  # Track TTS synthesis tasks
			sentence_index = 0  # Track sentence order
			ordered_results = {}  # Store results by index: {index: (sentence, audio_data, latency)}
			failed_sentences = set()  # Track failed sentence indices to skip them
			next_sentence_to_send = [0]  # Track which sentence to send next (list for shared reference)
			send_lock = asyncio.Lock()  # Lock for thread-safe ordered sending
			total_sentences = [0]  # Track total number of sentences (will be updated as we detect them)
			
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
				sentence_buffer += chunk
				chunk_count += 1
				
				# Send each chunk as llm_chunk event
				print(f"[LLM] Sending chunk {chunk_count}: '{chunk}'")
				escaped_chunk = chunk.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
				self.dc_send('{"event":"llm_chunk","text":"' + escaped_chunk + '"}')
				chunk_latency = (time.time() - chunk_start) * 1000
				last_chunk_time = time.time()
				if chunk_latency > 1.0:  # Only log if chunk processing > 1ms
					logger.info(f"[LATENCY] LLM chunk {chunk_count}: send={chunk_latency:.2f}ms")
				
				# Phase 3: Detect complete sentences and start TTS immediately
				if self.tts and self.tts.is_ready():
					# Check for sentence boundaries (period, exclamation, question mark)
					import re
					# Find complete sentences (ending with . ! ?)
					sentence_pattern = r'([^.!?]*[.!?]+)'
					matches = list(re.finditer(sentence_pattern, sentence_buffer))
					
					if matches:
						print(f"[TTS] 🔍 Detected {len(matches)} complete sentence(s) in buffer")
						logger.debug(f"[TTS] Sentence detection: found {len(matches)} matches in buffer (length={len(sentence_buffer)})")
						
						# Extract complete sentences and queue them in order
						# Process all matches to ensure we don't skip any sentences
						sentences_to_queue = []
						processed_end = 0  # Track how much of the buffer we've processed
						
						for match in matches:
							complete_sentence = match.group(1).strip()
							
							# Filter out very short sentences (likely fragments like "Hi." or "OK.")
							# Minimum sentence length to avoid fragments
							min_sentence_length = 3
							
							if not complete_sentence:
								print(f"[TTS] ⏭️  Skipping empty sentence at position {match.start()}-{match.end()}")
								logger.debug(f"[TTS] Empty sentence skipped at position {match.start()}-{match.end()}")
							elif len(complete_sentence) < min_sentence_length:
								print(f"[TTS] ⏭️  Skipping very short sentence ({len(complete_sentence)} chars): '{complete_sentence}' (likely fragment)")
								logger.debug(f"[TTS] Very short sentence skipped: {len(complete_sentence)} chars at {match.start()}-{match.end()}")
							elif complete_sentence in completed_sentences:
								# This sentence text was already queued - skip it
								# This handles legitimate duplicates in LLM response
								print(f"[TTS] ⏭️  Skipping duplicate sentence text: '{complete_sentence[:30]}...' (already queued)")
								logger.debug(f"[TTS] Duplicate sentence text skipped: {len(complete_sentence)} chars at {match.start()}-{match.end()}")
							else:
								# New sentence - add to queue
								completed_sentences.add(complete_sentence)
								sentences_to_queue.append((match.start(), match.end(), complete_sentence))
								print(f"[TTS] 📝 New sentence detected: '{complete_sentence}' ({len(complete_sentence)} chars at position {match.start()}-{match.end()})")
								logger.info(f"[TTS] New sentence detected: '{complete_sentence}' ({len(complete_sentence)} chars at position {match.start()}-{match.end()})")
						
						# Queue all new sentences with sequential indices
						for match_start, match_end, complete_sentence in sentences_to_queue:
							# Start TTS for this sentence immediately
							if not tts_started:
								tts_started = True
								# Send tts_started event
								self.dc_send('{"event":"tts_started"}')
								logger.info(f"[LATENCY] TTS started (streaming): first sentence ready")
							
							# Start TTS synthesis for this sentence (non-blocking)
							current_index = sentence_index
							sentence_index += 1
							total_sentences[0] = sentence_index  # Update total count
							print(f"[TTS] 🚀 Creating task for sentence {current_index}: '{complete_sentence[:50]}{'...' if len(complete_sentence) > 50 else ''}'")
							tts_task = asyncio.create_task(self._synthesize_single_sentence(complete_sentence, current_index, ordered_results, next_sentence_to_send, send_lock, failed_sentences, total_sentences))
							tts_tasks.append(tts_task)
							print(f"[TTS] ✅ Task created (total tasks: {len(tts_tasks)})")
							logger.info(f"[TTS] Streaming TTS: sentence {current_index} queued for synthesis (task {len(tts_tasks)})")
							
							# Track the furthest processed position
							processed_end = max(processed_end, match_end)
						
						# Remove all processed sentences from buffer (both queued and skipped)
						# This prevents reprocessing the same sentences as the buffer grows
						if matches:
							max_processed_end = max(match.end() for match in matches)
							if max_processed_end > 0:
								queued_count = len(sentences_to_queue)
								skipped_count = len(matches) - queued_count
								sentence_buffer = sentence_buffer[max_processed_end:].strip()
								print(f"[TTS] 📦 Buffer updated: removed {len(matches)} sentences (queued: {queued_count}, skipped: {skipped_count}) up to position {max_processed_end}, remaining='{sentence_buffer[:50]}{'...' if len(sentence_buffer) > 50 else ''}'")
								logger.debug(f"[TTS] Buffer trimmed: removed {max_processed_end} chars ({len(matches)} sentences: {queued_count} queued, {skipped_count} skipped), remaining {len(sentence_buffer)} chars")
			
			llm_gen_latency = (time.time() - llm_gen_start) * 1000
			total_chunks = chunk_count
			avg_chunk_time = (llm_gen_latency / total_chunks) if total_chunks > 0 else 0
			logger.info(f"[LATENCY] LLM generation: total={llm_gen_latency:.2f}ms, chunks={total_chunks}, avg_chunk={avg_chunk_time:.2f}ms")
			
			# Send llm_complete with full response
			complete_start = time.time()
			print(f"[LLM] Response: '{full_response}'")
			print(f"[LLM] Response length: {len(full_response)} chars, sentence_buffer remaining: '{sentence_buffer}' ({len(sentence_buffer)} chars)")
			print(f"[LLM] Total sentences queued: {sentence_index}, completed_sentences count: {len(completed_sentences)}")
			logger.info(f"[LLM] Full response: {len(full_response)} chars, sentence_buffer remaining: {len(sentence_buffer)} chars, sentences queued: {sentence_index}")
			escaped_response = full_response.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
			self.dc_send('{"event":"llm_complete","text":"' + escaped_response + '"}')
			complete_latency = (time.time() - complete_start) * 1000
			
			# Handle any remaining text in buffer (incomplete last sentence)
			if self.tts and self.tts.is_ready() and sentence_buffer.strip():
				remaining_text = sentence_buffer.strip()
				# Only process if it's substantial (not just a fragment)
				if len(remaining_text) >= 3:  # Minimum length to avoid fragments
					# Process remaining text as final sentence
					if not tts_started:
						tts_started = True
						self.dc_send('{"event":"tts_started"}')
					current_index = sentence_index
					sentence_index += 1
					total_sentences[0] = sentence_index  # Update total count
					tts_task = asyncio.create_task(self._synthesize_single_sentence(remaining_text, current_index, ordered_results, next_sentence_to_send, send_lock, failed_sentences, total_sentences))
					tts_tasks.append(tts_task)
					print(f"[TTS] 🚀 STREAMING: Started TTS for final sentence {current_index}: '{remaining_text[:50]}{'...' if len(remaining_text) > 50 else ''}' ({len(remaining_text)} chars)")
					logger.info(f"[TTS] Final sentence queued: {len(remaining_text)} chars")
				else:
					print(f"[TTS] ⏭️  Skipping final fragment: '{remaining_text}' ({len(remaining_text)} chars, too short)")
					logger.debug(f"[TTS] Final fragment skipped: {len(remaining_text)} chars (too short)")
			
			# If no streaming TTS was started, synthesize the full response (fallback)
			if not tts_started and self.tts and self.tts.is_ready() and full_response.strip():
				print(f"[TTS] No sentences detected during streaming, synthesizing full response")
				await self._synthesize_response(full_response)
			else:
				# Wait for all streaming TTS tasks to complete
				if tts_tasks:
					print(f"[TTS] Waiting for {len(tts_tasks)} streaming TTS tasks to complete...")
					logger.info(f"[TTS] Waiting for {len(tts_tasks)} streaming TTS tasks")
					wait_start = time.time()
					results = await asyncio.gather(*tts_tasks, return_exceptions=True)
					wait_time = (time.time() - wait_start) * 1000
					logger.info(f"[TTS] Gather completed in {wait_time:.2f}ms")
					
					# Check for exceptions
					exception_count = 0
					for i, result in enumerate(results):
						if isinstance(result, Exception):
							exception_count += 1
							print(f"[TTS] ❌ Task {i+1}/{len(tts_tasks)} failed: {type(result).__name__}: {result}")
							logger.error(f"[TTS] Streaming task {i+1}/{len(tts_tasks)} failed: {type(result).__name__}: {result}", exc_info=result)
						else:
							logger.debug(f"[TTS] Task {i+1}/{len(tts_tasks)} completed successfully")
					
					if exception_count > 0:
						print(f"[TTS] ⚠️  {exception_count}/{len(tts_tasks)} tasks failed")
						logger.warning(f"[TTS] {exception_count}/{len(tts_tasks)} streaming TTS tasks failed")
					
					# Final check: Send any remaining sentences that weren't sent yet
					async with send_lock:
						import base64
						remaining_sent = 0
						print(f"[TTS] 🔍 Final check: next_sentence_to_send={next_sentence_to_send[0]}, total_sentences={total_sentences[0]}, ordered_results keys={list(ordered_results.keys())}")
						logger.info(f"[TTS] Final check: next={next_sentence_to_send[0]}, total={total_sentences[0]}, remaining_keys={list(ordered_results.keys())}")
						while next_sentence_to_send[0] < total_sentences[0]:
							idx = next_sentence_to_send[0]
							if idx in ordered_results:
								sent, audio, synth_time, audio_dur = ordered_results[idx]
								sentence_audio = np.clip(audio, -1.0, 1.0)
								audio_bytes = (sentence_audio * 32767).astype(np.int16).tobytes()
								audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
								self.dc_send(f'{{"event":"tts_chunk","sequence":0,"audio":"{audio_b64}","sample_rate":{self.tts.get_sample_rate()}}}')
								del ordered_results[idx]
								next_sentence_to_send[0] += 1
								remaining_sent += 1
								await asyncio.sleep(0.01)  # Delay between sentences
								print(f"[TTS] ✅ Sent remaining sentence {idx} (total remaining: {remaining_sent})")
								logger.info(f"[TTS] Sent remaining sentence {idx}")
							elif idx in failed_sentences:
								print(f"[TTS] ⏭️  Skipping failed sentence {idx} in final check")
								next_sentence_to_send[0] += 1
							else:
								# Missing sentence - skip it
								print(f"[TTS] ⚠️  Sentence {idx} missing in final check, skipping")
								logger.warning(f"[TTS] Sentence {idx} was never synthesized, skipping in final check")
								next_sentence_to_send[0] += 1
						
						if remaining_sent > 0:
							print(f"[TTS] ✅ Sent {remaining_sent} remaining sentences in final check")
							logger.info(f"[TTS] Sent {remaining_sent} remaining sentences after task completion")
						else:
							print(f"[TTS] ℹ️  No remaining sentences to send (all were sent during synthesis)")
							logger.debug(f"[TTS] No remaining sentences to send")
					
					# Send tts_complete event
					self.dc_send('{"event":"tts_complete"}')
					print(f"[TTS] All streaming TTS tasks completed (wait_time: {wait_time:.1f}ms)")
					logger.info(f"[TTS] All {len(tts_tasks)} streaming TTS tasks completed (wait_time: {wait_time:.2f}ms, exceptions: {exception_count})")
			
			total_llm_latency = (time.time() - llm_start) * 1000
			logger.info(f"[LATENCY] LLM total: generation={llm_gen_latency:.2f}ms, complete_send={complete_latency:.2f}ms, TOTAL={total_llm_latency:.2f}ms")
			
		except Exception as e:
			total_llm_latency = (time.time() - llm_start) * 1000
			print(f"[LLM] Error: {e}")
			logger.error(f"[LATENCY] LLM error after {total_llm_latency:.2f}ms: {e}")
			self.dc_send('{"event":"llm_error","error":"' + str(e).replace('"', '\\"') + '"}')
			import traceback
			traceback.print_exc()
	
	async def _synthesize_single_sentence(self, sentence: str, sentence_index: int, ordered_results: dict, next_sentence_to_send: list, send_lock: asyncio.Lock, failed_sentences: set, total_sentences: list) -> None:
		"""
		Synthesize a single sentence for streaming TTS (Phase 3).
		This is called as soon as a complete sentence is detected from LLM streaming.
		Results are stored and sent in order to maintain LLM response order.
		
		Args:
			sentence: Single sentence to synthesize
			sentence_index: Index of this sentence in the response (0-based)
			ordered_results: Dictionary to store results: {index: (sentence, audio_data, latency)}
			next_sentence_to_send: List with single element [index] - the next sentence index to send (will be updated)
			send_lock: Async lock for thread-safe ordered sending
			failed_sentences: Set of failed sentence indices to skip
			total_sentences: List with total sentence count
		"""
		print(f"[TTS] 🎬 _synthesize_single_sentence called with: '{sentence[:50]}{'...' if len(sentence) > 50 else ''}'")
		logger.info(f"[TTS] _synthesize_single_sentence called: sentence_length={len(sentence)}")
		
		if not self.tts:
			msg = "[TTS] ❌ TTS not available"
			print(msg)
			logger.error(msg)
			return
		
		tts_ready = self.tts.is_ready()
		if not tts_ready:
			msg = f"[TTS] ❌ TTS not ready (is_ready()={tts_ready})"
			print(msg)
			logger.error(msg)
			return
		
		sentence_stripped = sentence.strip()
		if not sentence_stripped:
			msg = "[TTS] ❌ Empty sentence"
			print(msg)
			logger.warning(msg)
			return
		
		logger.info(f"[TTS] All checks passed, proceeding with synthesis")
		
		try:
			# Check for interruption
			interrupted = self.tts_interrupted
			logger.info(f"[TTS] Interruption check: interrupted={interrupted}")
			if interrupted:
				msg = "[TTS] ⏸️  Synthesis interrupted"
				print(msg)
				logger.warning(msg)
				return
			
			# Synthesize the single sentence
			sentence_to_synth = sentence_stripped
			msg = f"[TTS] 🔄 Starting synthesis for: '{sentence_to_synth[:50]}{'...' if len(sentence_to_synth) > 50 else ''}'"
			print(msg)
			logger.info(f"[TTS] Starting synthesis for sentence: {len(sentence_to_synth)} chars")
			sentence_start = time.time()
			try:
				audio_data = await self.tts._synthesize_text(sentence_to_synth, speed=1.0)
				logger.info(f"[TTS] _synthesize_text completed successfully")
			except Exception as synth_error:
				logger.error(f"[TTS] _synthesize_text failed: {synth_error}", exc_info=True)
				raise
			synthesis_time = (time.time() - sentence_start) * 1000
			
			if self.tts_interrupted:
				print(f"[TTS] ⏸️  Synthesis interrupted after completion")
				return
			
			duration = len(audio_data) / self.tts.get_sample_rate()
			print(f"[TTS] 🎵 STREAMING: Synthesized sentence {sentence_index} in {synthesis_time:.1f}ms (duration: {duration:.2f}s): '{sentence[:50]}{'...' if len(sentence) > 50 else ''}'")
			logger.info(f"[LATENCY] TTS streaming sentence {sentence_index}: {synthesis_time:.2f}ms (audio_duration={duration:.2f}s)")
			
			# Store result in ordered dictionary
			ordered_results[sentence_index] = (sentence, audio_data, synthesis_time, duration)
			
			# Send sentences in order (send all consecutive sentences starting from next_sentence_to_send)
			# Use lock to ensure thread-safe ordered sending and prevent parallel playback
			async with send_lock:
				import base64
				# Send all consecutive ready sentences in order
				while True:
					idx = next_sentence_to_send[0]
					
					# Check if this sentence is ready
					if idx in ordered_results:
						sent, audio, synth_time, audio_dur = ordered_results[idx]
						
						# Convert sentence audio to base64 for transmission
						sentence_audio = np.clip(audio, -1.0, 1.0)
						audio_bytes = (sentence_audio * 32767).astype(np.int16).tobytes()
						audio_b64 = base64.b64encode(audio_bytes).decode('utf-8')
						
						# Send sentence audio via DataChannel with sequence number for client ordering
						send_start = time.time()
						self.dc_send(f'{{"event":"tts_chunk","sequence":{idx},"audio":"{audio_b64}","sample_rate":{self.tts.get_sample_rate()}}}')
						send_time = (time.time() - send_start) * 1000
						print(f"[TTS] ✅ Sent sentence {idx} audio chunk (sequence={idx}, {len(audio_b64)} bytes) in {send_time:.1f}ms")
						logger.info(f"[LATENCY] TTS chunk send (sentence {idx}, sequence={idx}): {send_time:.2f}ms")
						
						# Remove from results and increment next index
						del ordered_results[idx]
						next_sentence_to_send[0] += 1
						
						# Small delay to prevent overwhelming the client
						# Use a fixed small delay instead of duration-based to avoid blocking too long
						await asyncio.sleep(0.01)  # 10ms delay
						print(f"[TTS] ⏱️  Delayed 10ms after sentence {idx}")
					elif idx in failed_sentences:
						# Skip failed sentences
						print(f"[TTS] ⏭️  Skipping failed sentence {idx}")
						next_sentence_to_send[0] += 1
					elif idx >= total_sentences[0]:
						# Reached end of all sentences
						break
					else:
						# This sentence not ready yet, stop sending (will be sent when it's ready)
						break
			
		except Exception as e:
			print(f"[TTS] ❌ Error synthesizing sentence {sentence_index}: {e}")
			logger.error(f"[TTS] Error in streaming sentence synthesis (sentence {sentence_index}): {e}", exc_info=True)
			# Mark as failed so subsequent sentences can still be sent
			failed_sentences.add(sentence_index)
			# Try to continue sending other sentences
			async with send_lock:
				# Skip this failed sentence and continue
				if next_sentence_to_send[0] == sentence_index:
					next_sentence_to_send[0] += 1
					print(f"[TTS] ⏭️  Skipped failed sentence {sentence_index}, continuing with next")
			# Don't re-raise - allow other sentences to continue
	
	async def _synthesize_response(self, text: str) -> None:
		"""
		Synthesize LLM response to speech and stream audio.
		Used as fallback when streaming TTS doesn't detect sentences.
		
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
				self.dc_send(f'{{"event":"tts_chunk","sequence":0,"audio":"{audio_b64}","sample_rate":{self.tts.get_sample_rate()}}}')
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
