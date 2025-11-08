import numpy as np
import os
from typing import Optional
import time
import logging
from faster_whisper import WhisperModel
from scipy.signal import butter, sosfilt
import torch

logger = logging.getLogger(__name__)


class WhisperFaster:
	def __init__(self, model_size: str = "small.en", device: str = None, compute_type: str = None):
		"""
		Initialize Faster Whisper model with automatic GPU detection.
		
		Args:
			model_size: Model size (tiny.en, base.en, small.en, medium.en, large-v3)
			device: "cpu" or "cuda" (auto-detects if None)
			compute_type: "int8", "int8_float16", "float16", "float32" (auto-selects if None)
		"""
		self.model_size = model_size
		
		# Auto-detect GPU availability
		if device is None:
			self.device = "cuda" if torch.cuda.is_available() else "cpu"
			print(f"Auto-detected device: {self.device}")
		else:
			self.device = device
		
		# Auto-select compute type based on device
		if compute_type is None:
			if self.device == "cuda":
				# Use float16 for GPU for best performance
				self.compute_type = "float16"
			else:
				# Use int8 for CPU for efficiency
				self.compute_type = "int8"
			print(f"Auto-selected compute type: {self.compute_type}")
		else:
			self.compute_type = compute_type
		
		self.model = None
		self._load_model()
	
	def _load_model(self) -> None:
		"""Load the Faster Whisper model with GPU support."""
		try:
			print(f"Loading Whisper model: {self.model_size} on {self.device} with {self.compute_type}")
			
			# Show GPU info if available
			if self.device == "cuda" and torch.cuda.is_available():
				gpu_name = torch.cuda.get_device_name(0)
				gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
				print(f"GPU detected: {gpu_name} ({gpu_memory:.2f} GB)")
			
			self.model = WhisperModel(
				self.model_size,
				device=self.device,
				compute_type=self.compute_type,
				# Enable GPU optimizations
				num_workers=1 if self.device == "cuda" else 4
			)
			print(f"✓ Whisper model ready on {self.device}")
		except Exception as e:
			print(f"Failed to load Whisper model: {e}")
			# Fallback to CPU if GPU fails
			if self.device == "cuda":
				print("Falling back to CPU...")
				self.device = "cpu"
				self.compute_type = "int8"
				try:
					self.model = WhisperModel(
						self.model_size,
						device=self.device,
						compute_type=self.compute_type
					)
					print(f"✓ Whisper model ready on CPU (fallback)")
				except Exception as e2:
					print(f"CPU fallback also failed: {e2}")
					self.model = None
			else:
				self.model = None
	
	def is_ready(self) -> bool:
		"""Check if the model is ready to use."""
		return self.model is not None
	
	def _preprocess_audio(self, audio_16k: np.ndarray) -> np.ndarray:
		"""
		Preprocess 16kHz audio to improve transcription quality.
		- Remove DC offset
		- Apply high-pass filter to remove low-frequency noise
		- Normalize volume
		- Apply soft limiting to prevent clipping
		
		Args:
			audio_16k: Audio samples at 16kHz
		
		Returns:
			Preprocessed audio at 16kHz
		"""
		preprocess_start = time.time()
		audio = audio_16k.astype(np.float32)
		
		# Remove DC offset (center around 0)
		dc_start = time.time()
		audio = audio - np.mean(audio)
		dc_latency = (time.time() - dc_start) * 1000
		
		# High-pass filter at 80Hz to remove rumble/noise (16kHz sample rate)
		filter_start = time.time()
		sos = butter(4, 80, btype='highpass', fs=16000, output='sos')
		audio = sosfilt(sos, audio).astype(np.float32)
		filter_latency = (time.time() - filter_start) * 1000
		
		# Calculate RMS for normalization
		normalize_start = time.time()
		rms = np.sqrt(np.mean(audio ** 2))
		
		if rms > 1e-6:  # Only normalize if there's actual signal
			# Target RMS of 0.05 (good level for speech)
			target_rms = 0.05
			gain = target_rms / rms
			
			# Limit gain to prevent amplifying noise too much
			gain = min(gain, 10.0)
			audio = audio * gain
			
			# Soft clip/limit to prevent distortion
			# Use tanh for smooth limiting (prevents harsh clipping)
			audio = np.tanh(audio * 0.9)
			
			# Scale to use 80% of dynamic range (leaves headroom)
			audio = audio * 0.8
		normalize_latency = (time.time() - normalize_start) * 1000
		
		total_preprocess_latency = (time.time() - preprocess_start) * 1000
		if total_preprocess_latency > 10.0:  # Only log if > 10ms
			logger.info(f"[LATENCY] STT preprocessing: DC={dc_latency:.2f}ms, filter={filter_latency:.2f}ms, normalize={normalize_latency:.2f}ms, TOTAL={total_preprocess_latency:.2f}ms")
		
		return audio
	
	def transcribe(self, audio_16k: np.ndarray, language: str = "en") -> Optional[str]:
		"""
		Transcribe 16kHz audio using Faster Whisper.
		
		Args:
			audio_16k: Audio samples as float32 numpy array at 16kHz
			language: Language code (e.g., "en")
		
		Returns:
			Transcribed text or None if failed
		"""
		if not self.is_ready():
			return None
		
		transcribe_start = time.time()
		try:
			cast_start = time.time()
			audio_16k = audio_16k.astype(np.float32)
			cast_latency = (time.time() - cast_start) * 1000
			
			# Preprocess audio to improve quality (already at 16kHz)
			preprocess_start = time.time()
			audio_clean = self._preprocess_audio(audio_16k)
			preprocess_latency = (time.time() - preprocess_start) * 1000
			
			# Transcribe
			model_start = time.time()
			segments, info = self.model.transcribe(
				audio_clean,
				language=language,
				beam_size=5,
				vad_filter=False,  # We already did VAD
				without_timestamps=True
			)
			model_latency = (time.time() - model_start) * 1000
			
			# Collect all segments
			collect_start = time.time()
			transcription = " ".join([segment.text for segment in segments]).strip()
			collect_latency = (time.time() - collect_start) * 1000
			
			total_latency = (time.time() - transcribe_start) * 1000
			audio_duration = len(audio_16k) / 16000
			logger.info(f"[LATENCY] STT transcribe: cast={cast_latency:.2f}ms, preprocess={preprocess_latency:.2f}ms, model={model_latency:.2f}ms, collect={collect_latency:.2f}ms, TOTAL={total_latency:.2f}ms (audio={audio_duration:.2f}s, ratio={total_latency/(audio_duration*1000):.2f}x)")
			
			return transcription if transcription else ""
		
		except Exception as e:
			total_latency = (time.time() - transcribe_start) * 1000
			print(f"Whisper transcription error: {e}")
			logger.error(f"[LATENCY] STT transcribe error after {total_latency:.2f}ms: {e}")
			return ""

