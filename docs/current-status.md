# Current Status

## System Architecture

### Current Processing Flow
```
Browser → WebRTC → Server → Audio Pipeline → VAD → STT → Response
   ↓         ↓        ↓           ↓         ↓     ↓       ↓
Click → Connect → Receive → Process → Detect → Transcribe → Display
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
└─────────────┘    └──────────────┘    └─────────────┘
```

## Current Implementation

### ✅ Working Components
- **WebRTC Connection**: Real-time audio streaming (20ms frames)
- **Audio Processing**: Centralized resampling at ingestion (SOC principle)
- **Voice Activity Detection**: Silero VAD with two-level pause detection
  - Short pause (1.5s): Natural utterance breaks
  - Long pause (2s): End of turn, ready for LLM
- **Speech-to-Text**: Faster-Whisper (small.en model) for high-accuracy transcription
- **LLM Integration**: Google Gemini (gemini-1.5-flash) for conversational AI
  - Streaming responses for real-time feedback
  - Conversation history maintained
- **Data Channel**: Event-based bidirectional communication
- **Frontend**: Minimal UI with transcription display, turn-complete indicator, and LLM response streaming

### 🔄 Complete Voice-to-Voice Pipeline (FINALIZED)
1. **Audio Capture**: Browser captures microphone audio
2. **WebRTC Transport**: 20ms frames sent to server
3. **Sample Rate Detection**: Dynamic detection from frame samples
4. **Stereo Conversion**: Automatic stereo-to-mono if needed
5. **Centralized Resampling**: Single resampling point to 16kHz (main.py)
6. **VAD Processing**: Silero VAD processes 16kHz audio, detects speech/pauses
   - Detects speech start → `turn_started` event
   - Detects short pause (1.5s) → `turn_final` event (utterance break)
   - Detects long pause (2s) → `turn_complete` event (end of turn, ready for LLM)
7. **Audio Buffering**: 16kHz audio buffered during active speech
8. **Sequential STT**: Complete transcription on VAD-detected pause
9. **LLM Processing**: Gemini generates conversational response
   - Streaming text chunks sent in real-time
   - Conversation history maintained for context
10. **Response**: All events sent via DataChannel for real-time UI updates

### 📊 Performance Characteristics (Benchmarked)
- **Audio Latency**: ~20-40ms (WebRTC transport)
- **VAD Response**: ~20ms (real-time speech detection)
- **VAD Thresholds**: 
  - Speech detection: 1 frame (20ms)
  - Utterance end: 1.5s silence
  - Turn end: 2s silence
- **STT Latency**: 2-5 seconds (measured: 2.29s for 21s, 1.46s for 8s, 4.63s for 54s)
- **STT Speed**: ~0.1x real-time (10x faster than audio duration)
- **Accuracy**: High (small.en model optimized for quality)
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

**Complete Event Flow:**
1. User speaks → `turn_started`
2. User pauses briefly (1.5s) → `turn_final` with transcription (still listening)
3. User pauses longer (2s) → `turn_complete` with transcription
4. LLM starts → `llm_started` (thinking indicator)
5. LLM streams response → multiple `llm_chunk` events
6. LLM finishes → `llm_complete` with full response

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

### 🎯 Remaining for Full Real-Time Conversation
**STT + LLM pipeline complete! Next critical items:**
- ~~**LLM Integration**~~: ✅ COMPLETE - Gemini with streaming responses
- **No TTS**: Missing text-to-speech synthesis (OpenVoice)
- **No Barge-in**: Can't interrupt during TTS playback
- **No Audio Output**: LLM responses are text-only, need voice synthesis

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

### Phase 3: LLM & TTS Integration (Next)
- **Focus**: Add conversation generation and speech synthesis
- **Approach**: Integrate Gemini LLM and OpenVoice TTS
- **Goal**: Complete voice conversation pipeline
- **Priority**: High - needed for end-to-end conversation

### Phase 4: Advanced Features (Future)
- **Focus**: Barge-in, TTS streaming, advanced optimizations
- **Approach**: Full duplex conversation with interruption handling
- **Goal**: Natural conversation flow

## Pending Features

### 🔄 Critical for Full Conversation
- **LLM Integration**: Gemini for response generation
- **TTS Synthesis**: OpenVoice for text-to-speech
- **Barge-in**: Cancel TTS when user speaks
- **LLM Streaming**: Stream LLM responses for lower latency

### 🚀 Future Enhancements
- **Metrics & Observability**: Latency tracking, health checks
- **Containerization**: Docker deployment
- **GPU Support**: CUDA acceleration for models
- **Multi-language**: Support for non-English languages
- **Advanced Streaming**: Sliding window for even lower latency

## Next Steps (Priority Order)
1. ~~**Optimize STT pipeline**~~ ✅ COMPLETE
2. ~~**Add two-level pause detection**~~ ✅ COMPLETE
3. ~~**Add LLM integration**~~ ✅ COMPLETE
   - ~~Listen for `turn_complete` events~~
   - ~~Send transcribed text to LLM~~
   - ~~Stream LLM response back~~
4. **Implement TTS** - Add text-to-speech synthesis (OpenVoice)
   - Convert LLM text response to audio
   - Stream audio back to frontend
   - Play audio through WebRTC
5. **Add barge-in** - Detect mic during TTS, cancel synthesis
6. **Add metrics** - Implement observability and health checks

## Recent Updates

### 2025-10-10: Gemini LLM Integration Implemented ✅
- Integrated Google Gemini (gemini-1.5-flash) for conversational AI
- **Streaming responses**: Real-time text chunks sent as they're generated
- **Conversation history**: Context maintained across turns
- **Event-driven**: `llm_started`, `llm_chunk`, `llm_complete`, `llm_error` events
- **Auto-trigger**: LLM automatically called on `turn_complete` event
- **Environment config**: API key and model configurable via `.env` file
- **Frontend display**: Real-time streaming response in dedicated UI section
- **Complete V2V pipeline**: Speech → Text → LLM → Text (TTS pending)

### 2025-10-10: Two-Level Pause Detection Implemented ✅
- Added intelligent turn detection with dual pause thresholds
- **Short pause (1.5s)**: Natural utterance breaks → `turn_final` event
- **Long pause (2s)**: End of turn → `turn_complete` event (ready for LLM)
- VAD automatically distinguishes between utterance breaks and turn completion
- Frontend displays turn-complete with green checkmark indicator
- Configurable via `VAD_END_MS` and `VAD_TURN_END_MS` environment variables
- Triggers LLM response generation automatically

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
