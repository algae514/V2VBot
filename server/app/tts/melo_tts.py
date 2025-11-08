import os
import asyncio
import numpy as np
from typing import Optional, AsyncGenerator
import time
import logging
import httpx
import soundfile as sf

logger = logging.getLogger(__name__)


class MeloTTS:
    """
    HTTP-based text-to-speech synthesis using RunPod TTS service.
    Maintains compatibility with the existing MeloTTS interface.
    """
    
    def __init__(self, device: str = None, language: str = "EN", tts_url: str = None):
        """
        Initialize HTTP-based TTS service.
        
        Args:
            device: Ignored (kept for compatibility)
            language: Ignored (kept for compatibility)
            tts_url: TTS service URL (defaults to RunPod endpoint)
        """
        # Get TTS URL from environment or parameter
        # TTS_URL environment variable must be set when RunPod service is available
        self.tts_url = tts_url or os.getenv("TTS_URL")
        if not self.tts_url:
            logger.warning("TTS_URL not configured. TTS service will be unavailable.")
            print("[TTS] ⚠️  TTS_URL not configured. Set TTS_URL environment variable to enable TTS.")
        
        self.sample_rate = 22050  # Default sample rate (common for TTS services)
        self.is_ready_flag = False  # Will be set to True after initialization
        self.http_client: Optional[httpx.AsyncClient] = None
        
        # Initialize HTTP client asynchronously
        asyncio.create_task(self._initialize_client())
    
    async def _initialize_client(self):
        """Initialize the HTTP client."""
        if not self.tts_url:
            self.is_ready_flag = False
            return
            
        init_start = time.time()
        try:
            # Enable connection pooling and HTTP/2 for better performance
            # Fallback to HTTP/1.1 if HTTP/2 is not available
            # Try to enable HTTP/2, fallback to HTTP/1.1 if not available
            http_version = "HTTP/1.1"  # Default
            try:
                # Check if h2 is available
                try:
                    import h2
                    h2_available = True
                    logger.debug(f"h2 package found: version {h2.__version__}")
                except ImportError:
                    h2_available = False
                    logger.warning("h2 package not found, HTTP/2 will not be available")
                
                if h2_available:
                    # Try to create HTTP/2 client
                    try:
                        self.http_client = httpx.AsyncClient(
                            timeout=60.0,
                            limits=httpx.Limits(max_keepalive_connections=10, max_connections=20),
                            http2=True  # Enable HTTP/2 for connection multiplexing
                        )
                        http_version = "HTTP/2"
                        logger.info("HTTP/2 client created successfully")
                    except Exception as e:
                        # httpx might raise an exception even if h2 is installed
                        logger.warning(f"HTTP/2 client creation failed ({type(e).__name__}: {e}), falling back to HTTP/1.1")
                        self.http_client = httpx.AsyncClient(
                            timeout=60.0,
                            limits=httpx.Limits(max_keepalive_connections=10, max_connections=20)
                        )
                        http_version = "HTTP/1.1"
                else:
                    # h2 not available, use HTTP/1.1
                    self.http_client = httpx.AsyncClient(
                        timeout=60.0,
                        limits=httpx.Limits(max_keepalive_connections=10, max_connections=20)
                    )
                    http_version = "HTTP/1.1"
            except Exception as e:
                # Fallback to HTTP/1.1 on any error
                logger.warning(f"HTTP client initialization error ({type(e).__name__}: {e}), using HTTP/1.1 fallback")
                self.http_client = httpx.AsyncClient(
                    timeout=60.0,
                    limits=httpx.Limits(max_keepalive_connections=10, max_connections=20)
                )
                http_version = "HTTP/1.1"
            
            init_latency = (time.time() - init_start) * 1000
            print(f"[TTS] ⏱️  INIT: HTTP TTS service initialized in {init_latency:.2f}ms ({http_version})")
            print(f"[TTS] 📍 TTS URL: {self.tts_url}")
            logger.info(f"[TTS] HTTP client initialized in {init_latency:.2f}ms at {self.tts_url} ({http_version})")
            self.is_ready_flag = True
        except Exception as e:
            init_latency = (time.time() - init_start) * 1000
            print(f"[TTS] ❌ INIT ERROR after {init_latency:.2f}ms: {e}")
            logger.exception(f"HTTP client initialization failed after {init_latency:.2f}ms")
            self.is_ready_flag = False
    
    async def __aenter__(self):
        """Async context manager entry."""
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit - cleanup HTTP client."""
        if self.http_client:
            await self.http_client.aclose()
    
    def is_ready(self) -> bool:
        """Check if TTS service is ready."""
        return self.is_ready_flag and self.http_client is not None
    
    async def synthesize_sentences(self, text: str, speed: float = 1.0) -> AsyncGenerator[np.ndarray, None]:
        """
        Synthesize text sentence by sentence using parallel requests for better performance.
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
            
            # Filter out empty sentences and track original indices
            sentence_tasks = []
            for i, sentence in enumerate(sentences):
                if not sentence.strip():
                    continue
                sentence_tasks.append((i, sentence.strip()))
            
            if not sentence_tasks:
                return
            
            # Phase 2: Send all requests in parallel
            parallel_start = time.time()
            print(f"[TTS] 🚀 PARALLEL: Sending {len(sentence_tasks)} requests simultaneously")
            logger.info(f"[TTS] Phase 2: Sending {len(sentence_tasks)} parallel TTS requests")
            
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
            print(f"[TTS] ⏱️  PARALLEL: All {len(sentence_tasks)} requests completed in {parallel_latency:.2f}ms")
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
        Synthesize text to audio via HTTP service (async operation).
        
        Args:
            text: Text to synthesize
            speed: Speech speed
            
        Returns:
            Audio data as numpy array
        """
        if not self.http_client:
            raise RuntimeError("HTTP client not initialized")
        
        total_start = time.time()
        try:
            # Build JSON payload
            payload = {
                "text": text,
                "speed": speed
            }
            
            # Make HTTP request with JSON body
            http_start = time.time()
            print(f"[TTS] ⏱️  HTTP: Calling TTS service: {self.tts_url} (text: {len(text)} chars, speed: {speed})")
            logger.info(f"[TTS] HTTP request: {len(text)} chars, speed={speed}")
            
            response = await self.http_client.post(
                self.tts_url,
                json=payload,
                headers={"Content-Type": "application/json"}
            )
            response.raise_for_status()
            
            http_latency = (time.time() - http_start) * 1000
            response_size = len(response.content)
            print(f"[TTS] ⏱️  HTTP: Response received in {http_latency:.2f}ms ({response_size} bytes, status: {response.status_code})")
            logger.info(f"[TTS] HTTP response received in {http_latency:.2f}ms ({response_size} bytes)")
            
            # Read audio from response
            # Assuming the response is WAV audio data
            process_start = time.time()
            import io
            audio_bytes = io.BytesIO(response.content)
            
            # Read audio file using soundfile
            read_start = time.time()
            audio_data, sample_rate = sf.read(audio_bytes)
            read_latency = (time.time() - read_start) * 1000
            print(f"[TTS] ⏱️  AUDIO: Read audio in {read_latency:.2f}ms (shape: {audio_data.shape}, sr: {sample_rate}Hz)")
            logger.info(f"[TTS] Audio read completed in {read_latency:.2f}ms")
            
            # Ensure it's float32 and mono
            convert_start = time.time()
            if len(audio_data.shape) > 1:
                audio_data = audio_data[:, 0]  # Take first channel if stereo
            
            audio_data = audio_data.astype(np.float32)
            convert_latency = (time.time() - convert_start) * 1000
            print(f"[TTS] ⏱️  AUDIO: Converted to float32 mono in {convert_latency:.2f}ms (final shape: {audio_data.shape})")
            
            # Update sample rate if different
            if sample_rate != self.sample_rate:
                print(f"[TTS] 📊 Sample rate update: {self.sample_rate}Hz → {sample_rate}Hz")
                self.sample_rate = sample_rate
            
            total_latency = (time.time() - total_start) * 1000
            process_latency = (time.time() - process_start) * 1000
            print(f"[TTS] ⏱️  BREAKDOWN: HTTP={http_latency:.2f}ms, Processing={process_latency:.2f}ms, TOTAL={total_latency:.2f}ms")
            logger.info(f"[TTS] Synthesis breakdown: HTTP={http_latency:.2f}ms, Processing={process_latency:.2f}ms, Total={total_latency:.2f}ms")
            
            return audio_data
            
        except httpx.HTTPError as e:
            total_latency = (time.time() - total_start) * 1000
            print(f"[TTS] ❌ HTTP ERROR after {total_latency:.2f}ms: {e}")
            logger.error(f"[TTS] HTTP error after {total_latency:.2f}ms: {e}")
            raise RuntimeError(f"TTS HTTP request failed: {e}")
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
            
            # Call HTTP service
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
        """Get the device being used (kept for compatibility)."""
        return "http"
