import asyncio
import os
from typing import Optional, Callable

import numpy as np
from aiortc import MediaStreamTrack

from .resample import to_mono, resample_48k_to_16k
from .vad_silero import SileroVAD
from ..stt.whisper_cpp import WhisperCpp


class AudioPipeline:
	def __init__(self, dc_send: Callable[[str], None]):
		model_path = os.getenv("SILERO_VAD_ONNX", "silero_vad.onnx")
		self.vad = SileroVAD(model_path=model_path, threshold=0.5, window_ms=20, end_ms=500)
		self.whisper = WhisperCpp(
			binary_path=os.getenv("WHISPER_CPP_BIN", "./main"),
			model_path=os.getenv("WHISPER_CPP_MODEL", "./models/ggml-tiny.en.bin"),
		)
		self.buffer_16k: list[np.ndarray] = []
		self.dc_send = dc_send
		self.frame_samples_48k = 960  # 20 ms at 48k
		self.frame_samples_16k = 320  # 20 ms at 16k
		self._lock = asyncio.Lock()

	async def handle_audio_frame(self, pcm48: np.ndarray) -> None:
		# pcm48: float32 mono samples, length 960
		pcm16 = resample_48k_to_16k(pcm48)
		started, ended = self.vad.process(pcm16)
		if started:
			self.dc_send('{"event":"turn_started"}')
		# accumulate for utterance
		async with self._lock:
			self.buffer_16k.append(pcm16.copy())
		if ended:
			await self._on_utterance_end()

	async def _on_utterance_end(self) -> None:
		async with self._lock:
			if not self.buffer_16k:
				return
			utt = np.concatenate(self.buffer_16k)
			self.buffer_16k.clear()
			self.vad.reset()
		self.dc_send('{"event":"turn_final"}')
		# Offload STT to a thread to avoid blocking loop
		loop = asyncio.get_running_loop()
		text = await loop.run_in_executor(None, self.whisper.transcribe_16k, utt)
		if text:
			self.dc_send('{"final":"' + text.replace('"', '\\"') + '"}')
		else:
			self.dc_send('{"final":""}')
