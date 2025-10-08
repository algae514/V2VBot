import os
import subprocess
import tempfile
from typing import Optional
import soundfile as sf
import numpy as np


class WhisperCpp:
	def __init__(self, binary_path: str, model_path: str):
		self.binary_path = binary_path
		self.model_path = model_path

	def is_ready(self) -> bool:
		return os.path.exists(self.binary_path) and os.path.exists(self.model_path)

	def transcribe_16k(self, audio_16k: np.ndarray, language: str = "en") -> Optional[str]:
		if not self.is_ready():
			return None
		with tempfile.TemporaryDirectory() as d:
			wav_path = os.path.join(d, "utt.wav")
			sf.write(wav_path, audio_16k, 16000, subtype='PCM_16')
			cmd = [
				self.binary_path,
				"-m", self.model_path,
				"-f", wav_path,
				"-l", language,
				"-ml", "0",
				"-nt"  # no timestamps to reduce output parsing
			]
			try:
				out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, universal_newlines=True)
				# Heuristic: take the last non-empty line as text
				lines = [l.strip() for l in out.splitlines() if l.strip()]
				return lines[-1] if lines else ""
			except subprocess.CalledProcessError as e:
				return None
