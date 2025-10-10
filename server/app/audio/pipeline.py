import asyncio
import os
from typing import Optional, Callable
import time

import numpy as np
from aiortc import MediaStreamTrack

from .resample import to_mono, resample_48k_to_16k
from .vad_silero import SileroVAD
from ..stt.whisper_faster import WhisperFaster


class AudioPipeline:
	def __init__(self, dc_send: Callable[[str], None]):
		# Re-enable VAD with fallback to energy-based detection if model not available
		model_path = os.getenv("SILERO_VAD_ONNX", "models/silero_vad.onnx")
		self.vad = SileroVAD(model_path=model_path, threshold=0.3, window_ms=20, end_ms=1500)
		
		# Use Faster Whisper for better accuracy with accents
		whisper_model = os.getenv("WHISPER_MODEL", "small.en")
		self.whisper = WhisperFaster(model_size=whisper_model, device="cpu", compute_type="int8")
		self.buffer_audio: list[np.ndarray] = []  # Buffer original audio for Whisper
		self.buffer_sample_rate: int = 48000  # Track the sample rate of buffered audio
		self.dc_send = dc_send
		self._lock = asyncio.Lock()
		self.frame_count = 0

	async def handle_audio_frame(self, audio: np.ndarray, sample_rate: int = 48000) -> None:
		# audio: float32 mono samples at given sample_rate
		self.frame_count += 1
		
		# Downsample to 16kHz for VAD processing
		if sample_rate == 48000:
			pcm16 = resample_48k_to_16k(audio)
		elif sample_rate == 16000:
			pcm16 = audio
		else:
			# General resampling for other rates
			import scipy.signal
			num_samples_16k = int(len(audio) * 16000 / sample_rate)
			pcm16 = scipy.signal.resample(audio, num_samples_16k).astype(np.float32)
		
		started, ended = self.vad.process(pcm16)
		
		if started:
			self.buffer_sample_rate = sample_rate
			self.dc_send('{"event":"turn_started"}')
		
		# Buffer original audio when VAD is active (during speech)
		if self.vad.active:
			async with self._lock:
				self.buffer_audio.append(audio.copy())
		
		# Process OUTSIDE the lock to avoid deadlock
		if ended:
			await self._on_utterance_end()

	async def _on_utterance_end(self) -> None:
		try:
			async with self._lock:
				if not self.buffer_audio:
					return
				utt_audio = np.concatenate(self.buffer_audio)
				sample_rate = self.buffer_sample_rate
				self.buffer_audio.clear()
				self.vad.reset()
			
			self.dc_send('{"event":"turn_final"}')
			
			# Check if Whisper is ready
			if not self.whisper.is_ready():
				self.dc_send('{"error":"Whisper not ready"}')
				return
			
			# Offload STT to a thread to avoid blocking loop
			loop = asyncio.get_running_loop()
			text = await loop.run_in_executor(None, self.whisper.transcribe, utt_audio, sample_rate)
			
			if text:
				self.dc_send('{"final":"' + text.replace('"', '\\"') + '"}')
			else:
				self.dc_send('{"final":""}')
		except Exception as e:
			print(f"Error in _on_utterance_end: {e}")
			import traceback
			traceback.print_exc()
