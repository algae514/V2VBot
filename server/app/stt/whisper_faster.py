import numpy as np
from typing import Optional
from faster_whisper import WhisperModel
from scipy.signal import butter, sosfilt


class WhisperFaster:
	def __init__(self, model_size: str = "small.en", device: str = "cpu", compute_type: str = "int8"):
		"""
		Initialize Faster Whisper model.
		
		Args:
			model_size: Model size (tiny.en, base.en, small.en, medium.en, large-v3)
			device: "cpu" or "cuda"
			compute_type: "int8", "int8_float16", "float16", "float32"
		"""
		self.model_size = model_size
		self.device = device
		self.compute_type = compute_type
		self.model = None
		self._load_model()
	
	def _load_model(self) -> None:
		"""Load the Faster Whisper model."""
		try:
			print(f"Loading Whisper model: {self.model_size}")
			self.model = WhisperModel(
				self.model_size,
				device=self.device,
				compute_type=self.compute_type
			)
			print(f"✓ Whisper model ready")
		except Exception as e:
			print(f"Failed to load Whisper model: {e}")
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
		audio = audio_16k.astype(np.float32)
		
		# Remove DC offset (center around 0)
		audio = audio - np.mean(audio)
		
		# High-pass filter at 80Hz to remove rumble/noise (16kHz sample rate)
		sos = butter(4, 80, btype='highpass', fs=16000, output='sos')
		audio = sosfilt(sos, audio).astype(np.float32)
		
		# Calculate RMS for normalization
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
		
		try:
			audio_16k = audio_16k.astype(np.float32)
			
			# Preprocess audio to improve quality (already at 16kHz)
			audio_clean = self._preprocess_audio(audio_16k)
			
			# Transcribe
			segments, info = self.model.transcribe(
				audio_clean,
				language=language,
				beam_size=5,
				vad_filter=False,  # We already did VAD
				without_timestamps=True
			)
			
			# Collect all segments
			transcription = " ".join([segment.text for segment in segments]).strip()
			return transcription if transcription else ""
		
		except Exception as e:
			print(f"Whisper transcription error: {e}")
			return ""

