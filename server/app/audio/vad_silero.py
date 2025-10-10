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
		
		# Initialize LSTM state for Silero VAD: [2, batch_size, 128]
		self._state = np.zeros((2, 1, 128), dtype=np.float32)
		self._sample_rate = np.array(16000, dtype=np.int64)

	def is_ready(self) -> bool:
		return self.session is not None

	def reset(self) -> None:
		self._voiced_run = 0
		self._unvoiced_run = 0
		self.active = False
		# Reset LSTM state
		self._state = np.zeros((2, 1, 128), dtype=np.float32)

	def process(self, audio_16k: np.ndarray) -> Tuple[bool, Optional[str]]:
		# audio_16k: 1D float32 in [-1,1], length = window_samples
		if self.session is None:
			# Fallback: simple energy gate
			energy = float(np.mean(np.abs(audio_16k)))
			voiced = energy > float(os.getenv("VAD_ENERGY_FALLBACK", 0.05))
		else:
			# Prepare inputs for Silero VAD
			inp = audio_16k.astype(np.float32).reshape(1, -1)  # [batch, samples]
			
			try:
				# Call model with all required inputs
				inputs = {
					'input': inp,
					'state': self._state,
					'sr': self._sample_rate
				}
				outputs = self.session.run(None, inputs)
				
				# Extract speech probability and update state
				probs = outputs[0]  # [batch, 1]
				self._state = outputs[1]  # [2, batch, 128] - update for next call
				
				speech_prob = float(probs[0, 0])
				voiced = speech_prob > self.threshold
			except Exception as e:
				print(f"Silero VAD error: {e}, falling back to energy detection")
				# Fallback to energy detection if Silero fails
				energy = float(np.mean(np.abs(audio_16k)))
				voiced = energy > float(os.getenv("VAD_ENERGY_FALLBACK", 0.05))

		if voiced:
			self._voiced_run += self.window_samples
			self._unvoiced_run = 0
		else:
			self._unvoiced_run += self.window_samples
			self._voiced_run = 0

		started = False
		ended = None
		if not self.active and self._voiced_run >= self.window_samples:
			self.active = True
			started = True
		if self.active and self._unvoiced_run >= self.end_samples:
			self.active = False
			ended = "end"

		return started, ended
