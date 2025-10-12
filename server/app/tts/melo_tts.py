import os
import asyncio
import numpy as np
from typing import Optional, AsyncGenerator, List
import time
import logging
import torch

logger = logging.getLogger(__name__)


class MeloTTS:
    """
    MeloTTS-English v3 text-to-speech synthesis with streaming support and GPU acceleration.
    """
    
    def __init__(self, device: str = None, language: str = "EN"):
        """
        Initialize MeloTTS model with automatic GPU detection.
        
        Args:
            device: Device to run on ('cpu' or 'cuda', auto-detects if None)
            language: Language code ('EN' for English)
        """
        # Auto-detect GPU availability
        if device is None:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
            print(f"[TTS] Auto-detected device: {self.device}")
        else:
            self.device = device
        
        self.language = language
        self.model = None
        self.speaker_id = None
        self.sample_rate = 44100  # MeloTTS actual sample rate
        self.is_ready_flag = False
        
        # Initialize model asynchronously
        asyncio.create_task(self._initialize_model())
    
    async def _initialize_model(self):
        """Initialize the MeloTTS model asynchronously with GPU support."""
        try:
            # Import MeloTTS here to avoid blocking startup
            from melo.api import TTS
            
            print(f"[TTS] Loading MeloTTS-English model on {self.device}...")
            start_time = time.time()
            
            # Show GPU info if available
            if self.device == "cuda" and torch.cuda.is_available():
                gpu_name = torch.cuda.get_device_name(0)
                gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
                print(f"[TTS] GPU detected: {gpu_name} ({gpu_memory:.2f} GB)")
            
            # Run model loading in thread pool to avoid blocking
            loop = asyncio.get_running_loop()
            self.model = await loop.run_in_executor(
                None, 
                lambda: TTS(language=self.language, device=self.device)
            )
            
            # Get speaker IDs and use first available English speaker
            speaker_ids = self.model.hps.data.spk2id
            if speaker_ids:
                # Use first available speaker (typically 'EN-US' or similar)
                self.speaker_id = list(speaker_ids.values())[0]
                print(f"[TTS] Using speaker ID: {self.speaker_id}")
            else:
                raise ValueError("No speakers available in MeloTTS model")
            
            elapsed = time.time() - start_time
            print(f"[TTS] MeloTTS model loaded on {self.device} in {elapsed:.2f}s")
            self.is_ready_flag = True
            
        except Exception as e:
            print(f"[TTS] Failed to load MeloTTS model on {self.device}: {e}")
            logger.exception("MeloTTS initialization failed")
            
            # Fallback to CPU if GPU fails
            if self.device == "cuda":
                print("[TTS] Falling back to CPU...")
                self.device = "cpu"
                try:
                    from melo.api import TTS
                    loop = asyncio.get_running_loop()
                    self.model = await loop.run_in_executor(
                        None, 
                        lambda: TTS(language=self.language, device=self.device)
                    )
                    speaker_ids = self.model.hps.data.spk2id
                    if speaker_ids:
                        self.speaker_id = list(speaker_ids.values())[0]
                    print(f"[TTS] MeloTTS model loaded on CPU (fallback)")
                    self.is_ready_flag = True
                except Exception as e2:
                    print(f"[TTS] CPU fallback also failed: {e2}")
                    self.is_ready_flag = False
            else:
                self.is_ready_flag = False
    
    def is_ready(self) -> bool:
        """Check if TTS model is ready."""
        return self.is_ready_flag and self.model is not None
    
    async def synthesize_sentences(self, text: str, speed: float = 1.0) -> AsyncGenerator[np.ndarray, None]:
        """
        Synthesize text sentence by sentence for better streaming experience.
        
        Args:
            text: Text to synthesize
            speed: Speech speed (1.0 = normal)
            
        Yields:
            Complete sentence audio as numpy arrays
        """
        if not self.is_ready():
            raise RuntimeError("TTS model not ready")
        
        if not text.strip():
            return
        
        try:
            print(f"[TTS] Synthesizing sentences: '{text[:50]}{'...' if len(text) > 50 else ''}'")
            
            # Split text into sentences
            sentences = self._split_into_sentences(text)
            print(f"[TTS] Split into {len(sentences)} sentences")
            
            for i, sentence in enumerate(sentences):
                if not sentence.strip():
                    continue
                    
                print(f"[TTS] Synthesizing sentence {i+1}/{len(sentences)}: '{sentence[:30]}{'...' if len(sentence) > 30 else ''}'")
                start_time = time.time()
                
                # Run synthesis in thread pool to avoid blocking
                loop = asyncio.get_running_loop()
                audio_data = await loop.run_in_executor(
                    None,
                    self._synthesize_text,
                    sentence.strip(),
                    speed
                )
                
                elapsed = time.time() - start_time
                print(f"[TTS] Sentence {i+1} synthesis took {elapsed:.2f}s")
                
                # Yield complete sentence audio
                yield audio_data
                    
        except Exception as e:
            print(f"[TTS] Synthesis error: {e}")
            logger.exception("TTS synthesis failed")
            raise
    
    def _split_into_sentences(self, text: str) -> list[str]:
        """
        Split text into sentences for better streaming.
        
        Args:
            text: Input text
            
        Returns:
            List of sentences
        """
        import re
        
        # Simple sentence splitting by punctuation
        sentences = re.split(r'[.!?]+', text)
        
        # Clean up and filter empty sentences
        sentences = [s.strip() for s in sentences if s.strip()]
        
        # If no sentences found, return the original text
        if not sentences:
            return [text.strip()]
        
        return sentences
    
    def _synthesize_text(self, text: str, speed: float) -> np.ndarray:
        """
        Synthesize text to audio (blocking operation).
        
        Args:
            text: Text to synthesize
            speed: Speech speed
            
        Returns:
            Audio data as numpy array
        """
        try:
            # Use MeloTTS to generate audio - save to temporary file first
            import tempfile
            import os
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
                temp_path = tmp_file.name
            
            # Generate audio file
            self.model.tts_to_file(
                text=text,
                speaker_id=self.speaker_id,
                output_path=temp_path,
                speed=speed
            )
            
            # Read the generated audio file
            import soundfile as sf
            audio_data, sample_rate = sf.read(temp_path)
            
            # Clean up temporary file
            os.unlink(temp_path)
            
            # Ensure it's float32 and mono
            if len(audio_data.shape) > 1:
                audio_data = audio_data[:, 0]  # Take first channel if stereo
            
            audio_data = audio_data.astype(np.float32)
            
            # Update sample rate if different
            if sample_rate != self.sample_rate:
                print(f"[TTS] Sample rate mismatch: {sample_rate} vs {self.sample_rate}")
                self.sample_rate = sample_rate
            
            return audio_data
            
        except Exception as e:
            print(f"[TTS] Synthesis error: {e}")
            raise
    
    async def synthesize(self, text: str, speed: float = 1.0) -> np.ndarray:
        """
        Synthesize complete text to audio (non-streaming).
        
        Args:
            text: Text to synthesize
            speed: Speech speed
            
        Returns:
            Complete audio data as numpy array
        """
        if not self.is_ready():
            raise RuntimeError("TTS model not ready")
        
        if not text.strip():
            return np.array([], dtype=np.float32)
        
        try:
            print(f"[TTS] Synthesizing complete: '{text[:50]}{'...' if len(text) > 50 else ''}'")
            start_time = time.time()
            
            # Run synthesis in thread pool
            loop = asyncio.get_running_loop()
            audio_data = await loop.run_in_executor(
                None,
                self._synthesize_text,
                text,
                speed
            )
            
            elapsed = time.time() - start_time
            print(f"[TTS] Complete synthesis took {elapsed:.2f}s")
            
            return audio_data
            
        except Exception as e:
            print(f"[TTS] Synthesis error: {e}")
            logger.exception("TTS synthesis failed")
            raise
    
    def get_sample_rate(self) -> int:
        """Get the sample rate of synthesized audio."""
        return self.sample_rate
    
    def get_device(self) -> str:
        """Get the device being used."""
        return self.device
