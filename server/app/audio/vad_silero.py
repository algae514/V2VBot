import os
import numpy as np
import onnxruntime as ort
from typing import Optional, Tuple
import logging

logger = logging.getLogger(__name__)


class SileroVAD:
	def __init__(self, model_path: str, threshold: float = 0.5, window_ms: int = 20, end_ms: int = 1500, turn_end_ms: int = 2000, use_gpu: bool = None):
		thr = float(os.getenv("VAD_THRESHOLD", threshold))
		wnd = int(os.getenv("VAD_WINDOW_MS", window_ms))
		endw = int(os.getenv("VAD_END_MS", end_ms))
		turn_endw = int(os.getenv("VAD_TURN_END_MS", turn_end_ms))
		
		# Auto-detect GPU availability if not specified
		if use_gpu is None:
			use_gpu = os.getenv("USE_GPU", "true").lower() in ("true", "1", "yes")
		
		# Setup ONNX Runtime providers with GPU support
		providers = []
		if use_gpu:
			# Try CUDA provider first
			available_providers = ort.get_available_providers()
			if "CUDAExecutionProvider" in available_providers:
				providers.append("CUDAExecutionProvider")
				logger.info("Using CUDA for Silero VAD")
			else:
				logger.info("CUDA not available for ONNX, using CPU for VAD")
		
		# Always add CPU as fallback
		providers.append("CPUExecutionProvider")
		
		try:
			if os.path.exists(model_path):
				self.session = ort.InferenceSession(model_path, providers=providers)
				actual_provider = self.session.get_providers()[0]
				logger.info(f"Silero VAD loaded with provider: {actual_provider}, model_path: {model_path}")
			else:
				logger.error(f"Silero VAD model not found at: {model_path}")
				self.session = None
		except Exception as e:
			logger.error(f"Failed to load Silero VAD model: {e}", exc_info=True)
			self.session = None
		self.threshold = thr
		self.window_samples = int(16000 * wnd / 1000)
		self.end_samples = int(16000 * endw / 1000)
		self.turn_end_samples = int(16000 * turn_endw / 1000)
		self._voiced_run = 0
		self._unvoiced_run = 0
		self.active = False
		self._utterance_end_sent = False  # Track if we've sent utterance_end for this silence
		
		# Initialize LSTM state for Silero VAD: [2, batch_size, 128]
		self._state = np.zeros((2, 1, 128), dtype=np.float32)
		self._sample_rate = np.array(16000, dtype=np.int64)
		
		logger.info(f"VAD initialized: threshold={self.threshold}, window={wnd}ms ({self.window_samples} samples), utterance_end={endw}ms ({self.end_samples} samples), turn_end={turn_endw}ms ({self.turn_end_samples} samples), ready={self.is_ready()}")

	def is_ready(self) -> bool:
		return self.session is not None

	def reset(self) -> None:
		self._voiced_run = 0
		self._unvoiced_run = 0
		self.active = False
		self._utterance_end_sent = False
		# Reset LSTM state
		self._state = np.zeros((2, 1, 128), dtype=np.float32)

	def process(self, audio_16k: np.ndarray) -> Tuple[bool, Optional[str]]:
		# audio_16k: 1D float32 in [-1,1], length = window_samples
		# Log frame size mismatch for debugging
		if len(audio_16k) != self.window_samples:
			logger.debug(f"VAD frame size mismatch: expected {self.window_samples}, got {len(audio_16k)} samples")
		
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
				logger.warning(f"Silero VAD error: {e}, falling back to energy detection", exc_info=True)
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
		
		# Detect speech start (or resume after utterance_end)
		if not self.active and self._voiced_run >= self.window_samples:
			self.active = True
			started = True
		elif self.active and self._utterance_end_sent and self._voiced_run >= self.window_samples:
			# User resumed speaking after utterance_end - signal new start
			self._utterance_end_sent = False
			started = True
		
		# Two-level pause detection
		if self.active and self._unvoiced_run >= self.turn_end_samples:
			# Long pause (2s) - user is done talking, end of turn
			self.active = False
			self._utterance_end_sent = False  # Reset for next utterance
			ended = "turn_end"
		elif self.active and self._unvoiced_run >= self.end_samples and not self._utterance_end_sent:
			# Short pause (1.5s) - natural break, end of utterance
			# Send only once, keep active=True to continue tracking for turn_end
			self._utterance_end_sent = True
			ended = "utterance_end"

		return started, ended
