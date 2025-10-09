import os
import numpy as np
import onnxruntime as ort
from typing import Optional, Tuple


class SileroVAD:
	def __init__(self, model_path: str, threshold: float = 0.5, window_ms: int = 20, end_ms: int = 2000):
		thr = float(os.getenv("VAD_THRESHOLD", threshold))
		wnd = int(os.getenv("VAD_WINDOW_MS", window_ms))
		endw = int(os.getenv("VAD_END_MS", end_ms))
		try:
			self.session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"]) if os.path.exists(model_path) else None
		except Exception as e:
			print(f"Failed to load Silero VAD model: {e}")
			self.session = None
		self.threshold = thr
		self.window_samples = int(16000 * wnd / 1000)
		self.end_samples = int(16000 * endw / 1000)
		self._voiced_run = 0
		self._unvoiced_run = 0
		self.active = False

	def is_ready(self) -> bool:
		return self.session is not None

	def reset(self) -> None:
		self._voiced_run = 0
		self._unvoiced_run = 0
		self.active = False

	def process(self, audio_16k: np.ndarray) -> Tuple[bool, Optional[str]]:
		# audio_16k: 1D float32 in [-1,1], length = window_samples
		if self.session is None:
			# Fallback: simple energy gate
			energy = float(np.mean(np.abs(audio_16k)))
			voiced = energy > float(os.getenv("VAD_ENERGY_FALLBACK", 0.003))
		else:
			inp = audio_16k.astype(np.float32).reshape(1, -1)
			probs = self.session.run(None, {self.session.get_inputs()[0].name: inp})[0]
			voiced = float(probs[0, 0]) > self.threshold

		if voiced:
			self._voiced_run += self.window_samples
			self._unvoiced_run = 0
		else:
			self._unvoiced_run += self.window_samples
			self._voiced_run = 0

		started = False
		ended = None
		if not self.active and self._voiced_run >= 2 * self.window_samples:
			self.active = True
			started = True
		if self.active and self._unvoiced_run >= self.end_samples:
			self.active = False
			ended = "end"

		return started, ended
