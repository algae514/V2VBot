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
				"-t", "1"  # single thread for faster response
			]
			try:
				out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, universal_newlines=True)
				# Parse transcription lines - they start with timestamps [HH:MM:SS.mmm --> HH:MM:SS.mmm]
				transcription_lines = []
				for line in out.splitlines():
					line = line.strip()
					# Look for lines with timestamp format
					if line.startswith('[') and '-->' in line and ']' in line:
						# Extract text after the closing bracket
						text_part = line.split(']', 1)[1].strip()
						if text_part and text_part not in ['[BLANK_AUDIO]', '(BLANK_AUDIO)', '']:
							transcription_lines.append(text_part)
				
				result = ' '.join(transcription_lines).strip()
				return result
			except subprocess.CalledProcessError as e:
				print(f"Whisper error: {e}")
				return ""
