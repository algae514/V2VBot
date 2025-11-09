# Current Status

## System Architecture

### Current Processing Flow
```
Browser → WebRTC → Server → Audio Pipeline → VAD → STT → LLM → TTS → Audio Response
   ↓         ↓        ↓           ↓         ↓     ↓      ↓     ↓        ↓
Click → Connect → Receive → Process → Detect → Transcribe → Generate → Synthesize → Play
```

### Component Interaction Diagram
```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Browser   │    │    Server    │    │   Models    │
│             │    │              │    │             │
│ ┌─────────┐ │    │ ┌──────────┐ │    │ ┌─────────┐ │
│ │getUser- │ │───▶│ │WebRTC    │ │    │ │Silero   │ │
│ │Media()  │ │    │ │Track     │ │───▶│ │VAD      │ │
│ └─────────┘ │    │ └──────────┘ │    │ └─────────┘ │
│             │    │              │    │             │
│ ┌─────────┐ │    │ ┌──────────┐ │    │ ┌─────────┐ │
│ │Audio    │ │◀───│ │Audio     │ │◀───│ │Faster-  │ │
│ │Playback │ │    │ │Pipeline  │ │    │ │Whisper  │ │
│ └─────────┘ │    │ └──────────┘ │    │ └─────────┘ │
│             │    │              │    │             │
│ ┌─────────┐ │    │ ┌──────────┐ │    │ ┌─────────┐ │
│ │Web      │ │◀───│ │LLM +     │ │◀───│ │Gemini   │ │
│ │Audio    │ │    │ │TTS       │ │    │ │+ MeloTTS│ │
│ └─────────┘ │    │ └──────────┘ │    │ └─────────┘ │
└─────────────┘    └──────────────┘    └─────────────┘
```

## Current Implementation

### ✅ Working Components
- **WebRTC Connection**: Real-time audio streaming (20ms frames)
- **Audio Processing**: Centralized resampling at ingestion (SOC principle)
- **Voice Activity Detection**: Silero VAD with pause detection
  - End of utterance: 1000ms (configurable via VAD_END_MS, default 1000ms for real-time conversation)
  - Optimized for faster turn detection and lower latency
- **Speech-to-Text**: Faster-Whisper (small.en model) for high-accuracy transcription
- **LLM Integration**: Google Gemini (gemini-2.0-flash, configurable) for conversational AI
  - Streaming responses for real-time feedback
  - Conversation history maintained
  - Retry logic with exponential backoff for rate limits
- **TTS Integration**: HTTP-based TTS service (RunPod endpoint) for speech synthesis
  - Streaming TTS: Starts synthesis as soon as sentences are detected from LLM stream (Phase 3)
  - Parallel TTS requests: Multiple sentences synthesized concurrently (Phase 2)
  - HTTP/2 connection pooling for reduced network latency (Phase 1)
  - Ordered delivery: Sentences sent to client in LLM response order
  - 22050Hz audio output (sample rate from TTS service)
- **Barge-In Functionality**: Interrupt AI speech when user starts speaking
  - Immediate audio interruption and queue clearing
  - Natural conversation flow with interruption detection
- **Data Channel**: Event-based bidirectional communication
- **Frontend**: Complete voice-to-voice UI with audio playback and interruption handling

### 🔄 Complete Voice-to-Voice Pipeline (FINALIZED)
1. **Audio Capture**: Browser captures microphone audio
2. **WebRTC Transport**: 20ms frames sent to server
3. **Sample Rate Detection**: Dynamic detection from frame samples
4. **Stereo Conversion**: Automatic stereo-to-mono if needed
5. **Centralized Resampling**: Single resampling point to 16kHz (main.py)
6. **VAD Processing**: Silero VAD processes 16kHz audio, detects speech/pauses
   - Detects speech start → `turn_started` event
   - Detects pause (1000ms default) → `turn_complete` event (end of turn, ready for LLM)
7. **Audio Buffering**: 16kHz audio buffered during active speech
8. **Sequential STT**: Complete transcription on VAD-detected pause
9. **LLM Processing**: Gemini generates conversational response
   - Streaming text chunks sent in real-time
   - Conversation history maintained for context
   - Retry logic handles API rate limits gracefully
10. **TTS Synthesis**: HTTP-based TTS service converts LLM response to speech (Phase 3: Streaming TTS)
    - **Streaming**: TTS starts as soon as complete sentences are detected from LLM stream
    - **Parallel Processing**: Multiple sentences synthesized concurrently (Phase 2)
    - **Ordered Delivery**: Sentences sent to client in LLM response order using sequence numbers
    - **Connection Pooling**: HTTP/2 with connection reuse for reduced network latency (Phase 1)
    - Audio transmitted via DataChannel as base64-encoded chunks with sequence numbers
    - 22050Hz audio output (sample rate from TTS service)
11. **Audio Playback**: Browser plays synthesized speech using Web Audio API
    - Sequential sentence playback for natural flow
    - Audio interruption when user starts speaking (barge-in)
12. **Barge-In Detection**: VAD detects user speech during TTS playback
    - Immediate interruption of current audio
    - Queue clearing and pipeline restart
    - Conversation history preserved
13. **Response**: All events sent via DataChannel for real-time UI updates

### 📊 Performance Characteristics (Benchmarked - January 2025)
- **Audio Latency**: ~20-40ms (WebRTC transport)
- **VAD Response**: ~20ms (real-time speech detection)
- **VAD Thresholds**: 
  - Speech detection: 1 frame (20ms)
  - Turn end: 1000ms silence (configurable, optimized for real-time conversation)
- **STT Latency**: ~1.3-1.4s (small.en model on CPU)
  - Configurable: tiny.en (~0.3-0.5s), base.en (~0.6-0.8s), small.en (~1.3s)
  - GPU acceleration available (5-7x faster if GPU present)
- **LLM Latency**: 
  - TTFB (Time To First Byte): ~0.7-1.0s (gemini-2.0-flash)
  - Streaming responses for real-time feedback
- **TTS Latency** (HTTP-based service):
  - First sentence: ~1.4-4.0s (includes network latency)
  - Parallel synthesis: 26 sentences in ~4.8s (vs ~65s sequential)
  - Network overhead: ~1.5-2.0s per request (RunPod proxy)
  - Actual synthesis: ~0.1-0.2s per sentence
- **End-to-End Latency**: 
  - Average: ~4.4s (from speech end to first audio)
  - Breakdown: STT (1.3s) + LLM TTFB (0.8s) + First TTS (2.3s)
  - See `docs/latency-optimization-guide.md` for optimization options
- **Memory Efficiency**: 67% reduction (16kHz vs 48kHz buffering)
- **CPU Efficiency**: 50% reduction (single vs double resampling)
- **Sample Rate Support**: All rates (resampled to 16kHz at ingestion)
- **Audio Quality**: Preprocessed at 16kHz (DC offset, high-pass filter, normalization)

### 📡 DataChannel Events
The system emits structured events for real-time communication:

**STT Event Types:**
```json
{"event": "turn_started"}                              // Speech detected
{"event": "turn_final", "text": "..."}                 // Short pause (1.5s) - utterance end
{"event": "turn_complete", "text": "..."}              // Long pause (2s) - turn end, ready for LLM
```

**LLM Event Types:**
```json
{"event": "llm_started"}                               // LLM generation started
{"event": "llm_chunk", "text": "..."}                  // Streaming text chunk
{"event": "llm_complete", "text": "..."}               // Complete LLM response
{"event": "llm_error", "error": "..."}                 // LLM error occurred
```

**TTS Event Types:**
```json
{"event": "tts_started"}                               // TTS synthesis started
{"event": "tts_chunk", "sequence": 0, "audio": "...", "sample_rate": 22050}  // Audio chunk (base64) with sequence number
{"event": "tts_complete"}                              // TTS synthesis complete
{"event": "tts_interrupted"}                           // TTS interrupted by user speech
{"event": "tts_error", "error": "..."}                // TTS error occurred
```

**Complete Event Flow:**
1. User speaks → `turn_started`
2. User pauses (1000ms) → `turn_complete` with transcription
3. LLM starts → `llm_started` (thinking indicator)
4. LLM streams response → multiple `llm_chunk` events
5. **Streaming TTS (Phase 3)**: As sentences are detected from LLM stream:
   - TTS starts → `tts_started` (synthesis indicator)
   - Each sentence synthesized in parallel → `tts_chunk` events with sequence numbers
   - Sentences sent in order (sequence 0, 1, 2, ...) to maintain LLM response order
6. LLM finishes → `llm_complete` with full response
7. TTS finishes → `tts_complete` (audio playback complete)
8. **Barge-In**: User speaks during TTS → `turn_started` → `tts_interrupted` → restart pipeline

## Processing Architecture

### ✅ Asynchronous Processing
- **WebRTC Tasks**: Audio streaming + DataChannel messaging + ICE gathering
- **AsyncIO Tasks**: Ping task (every 10s) + Stats logging (every 1s) + Audio processing
- **Thread Pool**: STT processing runs in separate thread to avoid blocking event loop
- **VAD-Controlled Buffering**: VAD controls when audio is buffered for transcription
- **Sequential STT**: Complete transcription on VAD-detected pause (prioritizes accuracy)
- **Single Resampling**: All audio resampled once at ingestion (SOC principle)

### ✅ Architecture Optimizations Implemented
- **Centralized Resampling**: Main.py resamples to 16kHz at ingestion (SOC principle)
- **VAD Gate Control**: VAD state controls buffering start/end
- **Event-Based Communication**: turn_started, turn_final events
- **Memory Efficient**: 67% memory reduction (buffer 16kHz instead of 48kHz)
- **CPU Efficient**: 50% CPU reduction (single vs double resampling)

### 🎯 Complete Voice-to-Voice Pipeline ✅ FULLY IMPLEMENTED
**All core functionality implemented and working:**
- ✅ **LLM Integration**: Gemini with streaming responses
- ✅ **TTS Integration**: MeloTTS-English v3 with sentence-based streaming audio
- ✅ **Barge-in**: Full interruption capability during TTS playback
- ✅ **Audio Output**: Complete voice-to-voice conversation pipeline

## Development Strategy

### Phase 1: Make It Work ✅ COMPLETE
- **Focus**: Get basic functionality working correctly
- **Approach**: Sequential processing, batch STT, proper error handling
- **Goal**: Reliable transcription and basic WebRTC communication
- **Status**: Complete and tested

### Phase 2: Audio Processing Optimization ✅ COMPLETE
- **Focus**: Optimize audio processing pipeline for efficiency and accuracy
- **Approach**: Single resampling, VAD-gated buffering, sequential transcription
- **Goal**: High-accuracy transcription with reduced memory and CPU usage
- **Status**: Complete! Sequential STT with 67% memory reduction, 50% CPU reduction
- **Achievements**:
  - ✅ Single resampling point (SOC principle)
  - ✅ 16kHz buffering (3x memory reduction)
  - ✅ Sequential transcription on VAD-detected pauses (high accuracy)
  - ✅ Event-based datachannel communication
  - ✅ Benchmarked STT latency: 2-5 seconds (10x faster than real-time)

### Phase 3: LLM & TTS Integration ✅ COMPLETE
- **Focus**: Add conversation generation and speech synthesis
- **Approach**: Integrated Gemini LLM and HTTP-based TTS service
- **Goal**: Complete voice conversation pipeline
- **Status**: Complete! Full voice-to-voice conversation with barge-in support

### Phase 4: Latency Optimizations ✅ COMPLETE
- **Focus**: Reduce end-to-end latency for real-time conversation
- **Approach**: Multi-phase optimization strategy
- **Status**: Complete! Implemented Phase 1-3 optimizations:
  - **Phase 1**: HTTP/2 connection pooling, LLM retry logic, faster Gemini model
  - **Phase 2**: Parallel TTS requests with ordered delivery
  - **Phase 3**: Streaming TTS (start TTS while LLM generates)
  - **VAD Optimization**: Reduced pause detection to 1000ms for faster turn detection
- **Results**: Average E2E latency ~4.4s (from speech end to first audio)
- **See**: `docs/latency-optimization-guide.md` for optimization options

### Phase 5: Advanced Features ✅ COMPLETE
- **Focus**: Barge-in, TTS streaming, advanced optimizations
- **Approach**: Full duplex conversation with interruption handling
- **Goal**: Natural conversation flow
- **Status**: Complete! All advanced features implemented

## Pending Features

### ✅ All Core Features Complete
- ~~**LLM Integration**~~: ✅ COMPLETE - Gemini (gemini-2.0-flash) for response generation
- ~~**TTS Synthesis**~~: ✅ COMPLETE - HTTP-based TTS service with streaming and parallel processing
- ~~**Barge-in**~~: ✅ COMPLETE - Cancel TTS when user speaks
- ~~**LLM Streaming**~~: ✅ COMPLETE - Stream LLM responses for lower latency
- ~~**Streaming TTS**~~: ✅ COMPLETE - Start TTS synthesis while LLM generates (Phase 3)
- ~~**Parallel TTS**~~: ✅ COMPLETE - Multiple sentences synthesized concurrently (Phase 2)
- ~~**Connection Pooling**~~: ✅ COMPLETE - HTTP/2 with connection reuse (Phase 1)

### 🚀 Future Enhancements
- **Metrics & Observability**: Latency tracking, health checks
- ~~**Containerization**~~: ✅ COMPLETE - Docker deployment with Docker Compose
- ~~**GPU Support**~~: ✅ COMPLETE - Full CUDA acceleration for all models
- **Multi-language**: Support for non-English languages
- **Advanced Streaming**: Sliding window for even lower latency

## Next Steps (Priority Order)
1. ~~**Optimize STT pipeline**~~ ✅ COMPLETE
2. ~~**Add two-level pause detection**~~ ✅ COMPLETE
3. ~~**Add LLM integration**~~ ✅ COMPLETE
4. ~~**Implement TTS**~~ ✅ COMPLETE - MeloTTS-English v3 with sentence-based streaming
5. ~~**Add barge-in**~~ ✅ COMPLETE - Full interruption capability
6. **Add metrics** - Implement observability and health checks (Next Priority)

## Recent Updates

### 2025-01-XX: Latency Optimizations (Phase 1-3) ✅
- **Phase 1 Optimizations**:
  - HTTP/2 connection pooling for TTS requests (reduces network overhead)
  - LLM retry logic with exponential backoff (handles API rate limits)
  - Faster Gemini model (gemini-2.0-flash)
- **Phase 2 Optimizations**:
  - Parallel TTS requests: Multiple sentences synthesized concurrently
  - Ordered delivery: Sentences sent to client in LLM response order using sequence numbers
  - 13.5x speedup for long responses (26 sentences in 4.8s vs 65s sequential)
- **Phase 3 Optimizations**:
  - Streaming TTS: Start TTS synthesis as soon as sentences are detected from LLM stream
  - Sentence boundary detection: Regex-based detection of complete sentences
  - Reduced perceived latency: TTS starts while LLM is still generating
- **VAD Optimization**:
  - Reduced pause detection from 1500ms to 1000ms for faster turn detection
  - Configurable via `VAD_END_MS` environment variable
- **Performance Results**:
  - Average E2E latency: ~4.4s (from speech end to first audio)
  - All sentences detected and sent correctly with ordered delivery
  - See `docs/latency-optimization-guide.md` for further optimization options

### 2025-10-10: Complete Voice-to-Voice Pipeline with Barge-In ✅
- **TTS Integration**: HTTP-based TTS service (RunPod endpoint) for speech synthesis
- **Sentence-Based Streaming**: Natural sentence-by-sentence audio delivery
- **Audio Quality**: 22050Hz audio output (from TTS service)
- **Barge-In Functionality**: Interrupt AI speech when user starts speaking
  - Immediate audio interruption and queue clearing
  - Natural conversation flow with interruption detection
  - Conversation history preserved during interruptions
- **Sequential Audio Playback**: Sentences play one after another for natural flow (with sequence numbers)
- **Complete Pipeline**: Speech → Text → LLM → Text → Speech (full voice-to-voice)
- **Event-Driven Architecture**: `tts_started`, `tts_chunk` (with sequence), `tts_complete`, `tts_interrupted`, `tts_error` events
- **Performance**: Real-time audio synthesis and streaming with parallel processing

### 2025-10-10: Gemini LLM Integration Implemented ✅
- Integrated Google Gemini (gemini-2.0-flash, configurable) for conversational AI
- **Streaming responses**: Real-time text chunks sent as they're generated
- **Conversation history**: Context maintained across turns
- **Event-driven**: `llm_started`, `llm_chunk`, `llm_complete`, `llm_error` events
- **Auto-trigger**: LLM automatically called on `turn_complete` event
- **Environment config**: API key and model configurable via `.env` file
- **Frontend display**: Real-time streaming response in dedicated UI section
- **Retry logic**: Exponential backoff for handling API rate limits
- **Complete V2V pipeline**: Speech → Text → LLM → Text → Speech (full voice-to-voice)

### 2025-10-10: Pause Detection Implemented ✅
- Added intelligent turn detection with pause threshold
- **Pause (1000ms default)**: End of turn → `turn_complete` event (ready for LLM)
- VAD detects end of utterance and triggers LLM response generation
- Frontend displays turn-complete with green checkmark indicator
- Configurable via `VAD_END_MS` environment variable (default: 1000ms for real-time conversation)
- Optimized for faster turn detection and lower latency

### 2025-10-10: Audio Processing Pipeline Optimized ✅
- Finalized sequential processing mode for optimal accuracy
- Single resampling point at audio ingestion (main.py) - SOC principle
- VAD-gated buffering for intelligent pause detection
- Event-based datachannel communication (turn_started, turn_final, turn_complete)
- 67% memory reduction, 50% CPU reduction
- Benchmarked STT latency: 2.29s for 21s, 1.46s for 8s, 4.63s for 54s audio
- Achieved ~0.1x real-time processing (10x faster than audio duration)
- High accuracy with small.en model
- Clean codebase with no dead code paths
