import numpy as np


def to_mono(audio: np.ndarray) -> np.ndarray:
	if audio.ndim == 1:
		return audio
	return np.mean(audio, axis=1).astype(audio.dtype)


def resample_48k_to_16k(audio_48k: np.ndarray) -> np.ndarray:
	# Simple decimation by factor 3; assumes input is 48000 Hz
	return audio_48k[::3]
