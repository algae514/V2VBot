import asyncio
import os
from typing import Optional, Callable
import time

import numpy as np
from aiortc import MediaStreamTrack

from .vad_silero import SileroVAD
from ..stt.whisper_faster import WhisperFaster


class AudioPipeline:
	def __init__(self, dc_send: Callable[[str], None]):
		# Re-enable VAD with fallback to energy-based detection if model not available
		model_path = os.getenv("SILERO_VAD_ONNX", "models/silero_vad.onnx")
		# Using original working VAD settings
		self.vad = SileroVAD(model_path=model_path, threshold=0.3, window_ms=20, end_ms=1500)
		
		# Use Faster Whisper for better accuracy with accents
		whisper_model = os.getenv("WHISPER_MODEL", "small.en")
		self.whisper = WhisperFaster(model_size=whisper_model, device="cpu", compute_type="int8")
		self.buffer_audio: list[np.ndarray] = []  # Buffer 16kHz audio for Whisper
		self.dc_send = dc_send
		self.frame_count = 0
		
		print(f"AudioPipeline initialized: Sequential mode, VAD threshold=0.3, VAD end=1500ms")

	async def handle_audio_frame(self, audio_16k: np.ndarray) -> None:
		"""
		Process 16kHz audio frame.
		
		Args:
			audio_16k: float32 mono samples at 16kHz
		"""
		self.frame_count += 1
		
		# Process with VAD (expects 16kHz)
		started, ended = self.vad.process(audio_16k)
		
		if started:
			self.dc_send('{"event":"turn_started"}')
		
		# Buffer 16kHz audio when VAD is active (during speech)
		if self.vad.active:
			self.buffer_audio.append(audio_16k.copy())
		
		# Process when speech ends
		if ended:
			await self._on_utterance_end()

	async def _on_utterance_end(self) -> None:
		"""
		Process complete utterance when speech ends.
		Simple sequential processing - no streaming.
		"""
		try:
			# Get buffered audio
			if not self.buffer_audio:
				return
			
			utt_audio_16k = np.concatenate(self.buffer_audio)
			self.buffer_audio.clear()
			self.vad.reset()
			
			# Check if Whisper is ready
			if not self.whisper.is_ready():
				self.dc_send('{"error":"Whisper not ready"}')
				return
			
			# Transcribe (offload to thread to avoid blocking event loop)
			loop = asyncio.get_running_loop()
			text = await loop.run_in_executor(None, self.whisper.transcribe, utt_audio_16k)
			
			# Send result
			if text:
				self.dc_send('{"event":"turn_final","text":"' + text.replace('"', '\\"') + '"}')
			else:
				self.dc_send('{"event":"turn_final","text":""}')
		except Exception as e:
			print(f"Error in _on_utterance_end: {e}")
			import traceback
			traceback.print_exc()
