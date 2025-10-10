import numpy as np
import scipy.signal


def to_mono(audio: np.ndarray) -> np.ndarray:
	if audio.ndim == 1:
		return audio
	return np.mean(audio, axis=1).astype(audio.dtype)


def resample_48k_to_16k(audio_48k: np.ndarray) -> np.ndarray:
	# Simple decimation by factor 3; assumes input is 48000 Hz
	return audio_48k[::3]


def resample_to_16k(audio: np.ndarray, sample_rate: int) -> np.ndarray:
	"""
	Resample audio to 16kHz from any sample rate.
	
	Args:
		audio: Audio samples as float32 numpy array
		sample_rate: Current sample rate of the audio
	
	Returns:
		Audio resampled to 16kHz
	"""
	if sample_rate == 16000:
		return audio
	elif sample_rate == 48000:
		# Use optimized decimation for 48kHz
		return resample_48k_to_16k(audio)
	else:
		# General resampling for other rates
		num_samples_16k = int(len(audio) * 16000 / sample_rate)
		return scipy.signal.resample(audio, num_samples_16k).astype(np.float32)
