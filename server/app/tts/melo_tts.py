import os
import asyncio
import numpy as np
from typing import Optional, AsyncGenerator
import time
import logging
import torch
import soundfile as sf
import tempfile

logger = logging.getLogger(__name__)


class MeloTTS:
    """
    Local MeloTTS-English v3 text-to-speech synthesis with streaming support and GPU acceleration.
    """
    
    def __init__(self, device: str = None, language: str = "EN", tts_url: str = None):
        """
        Initialize MeloTTS model with automatic GPU detection.
        
        Args:
            device: Device to run on ('cpu' or 'cuda', auto-detects if None)
            language: Language code ('EN' for English)
            tts_url: Ignored (kept for compatibility with old HTTP-based code)
        """
        # Auto-detect GPU availability
        if device is None:
            use_gpu = os.getenv("USE_GPU", "false").lower() in ("true", "1", "yes")
            self.device = "cuda" if (use_gpu and torch.cuda.is_available()) else "cpu"
            logger.info(f"[TTS] Auto-detected device: {self.device}")
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
        """Initialize the MeloTTS model with GPU support (async)."""
        init_start = time.time()
        try:
            # Import MeloTTS here to avoid blocking startup
            from melo.api import TTS
            
            logger.info(f"[TTS] Loading MeloTTS-English model on {self.device}...")
            
            # Show GPU info if available
            if self.device == "cuda" and torch.cuda.is_available():
                gpu_name = torch.cuda.get_device_name(0)
                gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
                print(f"[TTS] 🎮 GPU detected: {gpu_name} ({gpu_memory:.2f} GB)")
                logger.info(f"[TTS] GPU detected: {gpu_name} ({gpu_memory:.2f} GB)")
            
            # Download required NLTK data if needed
            try:
                import nltk
                nltk.download('averaged_perceptron_tagger_eng', quiet=True)
            except Exception as e:
                logger.warning(f"Failed to download NLTK data: {e}")
            
            # Initialize model in executor to avoid blocking
            loop = asyncio.get_running_loop()
            self.model = await loop.run_in_executor(
                None,
                lambda: TTS(language=self.language, device=self.device)
            )
            
            # Get speaker IDs and use first available English speaker
            speaker_ids = self.model.hps.data.spk2id
            if speaker_ids:
                self.speaker_id = list(speaker_ids.values())[0]
                logger.info(f"[TTS] Using speaker ID: {self.speaker_id}")
            else:
                raise ValueError("No speakers available in MeloTTS model")
            
            elapsed = time.time() - init_start
            print(f"[TTS] ✅ INIT: MeloTTS model loaded on {self.device} in {elapsed:.2f}s")
            logger.info(f"[TTS] MeloTTS model loaded on {self.device} in {elapsed:.2f}s")
            self.is_ready_flag = True
            
        except Exception as e:
            elapsed = time.time() - init_start
            logger.error(f"[TTS] Failed to load MeloTTS model on {self.device}: {e}")
            print(f"[TTS] ❌ INIT ERROR after {elapsed:.2f}s: {e}")
            
            # Fallback to CPU if GPU fails
            if self.device == "cuda":
                logger.warning("[TTS] Falling back to CPU...")
                print("[TTS] ⚠️  Falling back to CPU...")
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
                    elapsed = time.time() - init_start
                    print(f"[TTS] ✅ INIT: MeloTTS model loaded on CPU (fallback) in {elapsed:.2f}s")
                    logger.info(f"[TTS] MeloTTS model loaded on CPU (fallback) in {elapsed:.2f}s")
                    self.is_ready_flag = True
                except Exception as e2:
                    elapsed = time.time() - init_start
                    logger.error(f"[TTS] CPU fallback also failed: {e2}")
                    print(f"[TTS] ❌ INIT ERROR after {elapsed:.2f}s: CPU fallback failed: {e2}")
                    self.is_ready_flag = False
            else:
                self.is_ready_flag = False
    
    async def __aenter__(self):
        """Async context manager entry."""
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit - cleanup."""
        # MeloTTS doesn't require explicit cleanup
        pass
    
    def is_ready(self) -> bool:
        """Check if TTS model is ready."""
        return self.is_ready_flag and self.model is not None
    
    async def synthesize_sentences(self, text: str, speed: float = 1.0) -> AsyncGenerator[np.ndarray, None]:
        """
        Synthesize text sentence by sentence.
        Results are returned in the correct order.
        
        Args:
            text: Text to synthesize
            speed: Speech speed (1.0 = normal)
            
        Yields:
            Complete sentence audio as numpy arrays (in order)
        """
        if not self.is_ready():
            raise RuntimeError("TTS service not ready")
        
        if not text.strip():
            return
        
        total_start = time.time()
        try:
            print(f"[TTS] ⏱️  START: Synthesizing sentences: '{text[:50]}{'...' if len(text) > 50 else ''}'")
            logger.info(f"[TTS] Starting synthesis of {len(text)} characters")
            
            # Split text into sentences
            split_start = time.time()
            sentences = self._split_into_sentences(text)
            split_latency = (time.time() - split_start) * 1000
            print(f"[TTS] ⏱️  LATENCY: Sentence splitting took {split_latency:.2f}ms → {len(sentences)} sentences")
            logger.info(f"[LATENCY] TTS sentence splitting: {split_latency:.2f}ms, sentences={len(sentences)}")
            
            # Filter out empty sentences
            sentence_tasks = []
            for i, sentence in enumerate(sentences):
                if not sentence.strip():
                    continue
                sentence_tasks.append((i, sentence.strip()))
            
            if not sentence_tasks:
                return
            
            # Synthesize sentences in parallel
            parallel_start = time.time()
            print(f"[TTS] 🚀 PARALLEL: Synthesizing {len(sentence_tasks)} sentences simultaneously")
            logger.info(f"[TTS] Phase 2: Synthesizing {len(sentence_tasks)} parallel TTS sentences")
            
            # Create async tasks for all sentences
            async def synthesize_with_index(index: int, sentence: str) -> tuple[int, np.ndarray, float]:
                """Synthesize a sentence and return its index, audio, and latency."""
                sentence_start = time.time()
                audio_data = await self._synthesize_text(sentence, speed)
                sentence_latency = (time.time() - sentence_start) * 1000
                return (index, audio_data, sentence_latency)
            
            # Execute all requests in parallel
            tasks = [synthesize_with_index(i, sentence) for i, sentence in sentence_tasks]
            results = await asyncio.gather(*tasks)
            
            parallel_latency = (time.time() - parallel_start) * 1000
            print(f"[TTS] ⏱️  PARALLEL: All {len(sentence_tasks)} sentences completed in {parallel_latency:.2f}ms")
            logger.info(f"[LATENCY] TTS parallel requests: {parallel_latency:.2f}ms for {len(sentence_tasks)} sentences")
            
            # Sort results by original index to maintain order
            results.sort(key=lambda x: x[0])
            
            # Yield results in order
            for original_index, audio_data, sentence_latency in results:
                duration = len(audio_data) / self.sample_rate
                sentence_num = original_index + 1
                print(f"[TTS] ⏱️  YIELD: Sentence {sentence_num}/{len(sentence_tasks)}: {sentence_latency:.2f}ms (audio duration: {duration:.2f}s, {len(audio_data)} samples)")
                logger.info(f"[LATENCY] TTS sentence {sentence_num}/{len(sentence_tasks)}: {sentence_latency:.2f}ms (audio_duration={duration:.2f}s)")
                
                # Yield complete sentence audio in order
                yield audio_data
            
            total_latency = (time.time() - total_start) * 1000
            print(f"[TTS] ⏱️  TOTAL: All {len(sentence_tasks)} sentences synthesized in {total_latency:.2f}ms (parallel: {parallel_latency:.2f}ms)")
            logger.info(f"[LATENCY] TTS total synthesis: {total_latency:.2f}ms, sentences={len(sentence_tasks)}, parallel_time={parallel_latency:.2f}ms")
                    
        except Exception as e:
            total_latency = (time.time() - total_start) * 1000
            print(f"[TTS] ❌ ERROR after {total_latency:.2f}ms: {e}")
            logger.exception(f"TTS synthesis failed after {total_latency:.2f}ms")
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
    
    async def _synthesize_text(self, text: str, speed: float) -> np.ndarray:
        """
        Synthesize text to audio using local MeloTTS (async operation).
        
        Args:
            text: Text to synthesize
            speed: Speech speed
            
        Returns:
            Audio data as numpy array
        """
        if not self.model:
            raise RuntimeError("TTS model not initialized")
        
        total_start = time.time()
        try:
            # Create temporary file for synthesis
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
                tmp_path = tmp_file.name
            
            # Synthesize in executor to avoid blocking
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(
                None,
                lambda: self.model.tts_to_file(
                    text=text,
                    speaker_id=self.speaker_id,
                    output_path=tmp_path,
                    speed=speed
                )
            )
            
            # Read audio file
            read_start = time.time()
            audio_data, sample_rate = sf.read(tmp_path)
            read_latency = (time.time() - read_start) * 1000
            
            # Clean up temp file
            try:
                os.unlink(tmp_path)
            except:
                pass
            
            # Ensure it's float32 and mono
            convert_start = time.time()
            if len(audio_data.shape) > 1:
                audio_data = audio_data[:, 0]  # Take first channel if stereo
            
            audio_data = audio_data.astype(np.float32)
            convert_latency = (time.time() - convert_start) * 1000
            
            # Update sample rate if different
            if sample_rate != self.sample_rate:
                print(f"[TTS] 📊 Sample rate update: {self.sample_rate}Hz → {sample_rate}Hz")
                self.sample_rate = sample_rate
            
            total_latency = (time.time() - total_start) * 1000
            process_latency = (time.time() - read_start) * 1000
            print(f"[TTS] ⏱️  BREAKDOWN: Synthesis={process_latency:.2f}ms, TOTAL={total_latency:.2f}ms")
            logger.info(f"[TTS] Synthesis breakdown: Processing={process_latency:.2f}ms, Total={total_latency:.2f}ms")
            
            return audio_data
            
        except Exception as e:
            total_latency = (time.time() - total_start) * 1000
            print(f"[TTS] ❌ ERROR after {total_latency:.2f}ms: {e}")
            logger.exception(f"TTS synthesis error after {total_latency:.2f}ms")
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
            raise RuntimeError("TTS service not ready")
        
        if not text.strip():
            return np.array([], dtype=np.float32)
        
        total_start = time.time()
        try:
            print(f"[TTS] ⏱️  START: Synthesizing complete text: '{text[:50]}{'...' if len(text) > 50 else ''}'")
            logger.info(f"[TTS] Starting complete synthesis of {len(text)} characters")
            
            # Call synthesis
            audio_data = await self._synthesize_text(text, speed)
            
            total_latency = (time.time() - total_start) * 1000
            duration = len(audio_data) / self.sample_rate
            print(f"[TTS] ⏱️  COMPLETE: Synthesis finished in {total_latency:.2f}ms (audio duration: {duration:.2f}s)")
            logger.info(f"[TTS] Complete synthesis finished in {total_latency:.2f}ms (audio: {duration:.2f}s)")
            
            return audio_data
            
        except Exception as e:
            total_latency = (time.time() - total_start) * 1000
            print(f"[TTS] ❌ ERROR after {total_latency:.2f}ms: {e}")
            logger.exception(f"TTS synthesis failed after {total_latency:.2f}ms")
            raise
    
    def get_sample_rate(self) -> int:
        """Get the sample rate of synthesized audio."""
        return self.sample_rate
    
    def get_device(self) -> str:
        """Get the device being used."""
        return self.device
