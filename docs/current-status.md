# Current Status

## Completed ✅
- Define low-latency E2E architecture and latency budget
- Author docs: overall plan and requirements in docs
- Document folder structure in docs
- Write architectural rules in docs
- Write code rules/standards in docs
- Create Cursor instruction file and reference it from docs
- Scaffold repo with backend (FastAPI+aiortc) and minimal web client
- Serve static files via FastAPI and prefix API routes
- Create start.sh to bootstrap venv and run server
- **WebRTC signaling (REST+WebSocket) and media/data channels** ✅
- **Real-time audio streaming and processing** ✅
- **Voice Activity Detection (VAD) with energy-based fallback** ✅
- **Audio pipeline with 16kHz mono processing** ✅
- **WebRTC DataChannel communication** ✅
- **Minimal web UI with click-to-talk functionality** ✅
- **Environment setup for macOS with Homebrew dependencies** ✅
- **Speech-to-Text (STT) with Whisper.cpp integration** ✅
  - Fixed binary path: using `/opt/homebrew/bin/whisper-cli`
  - Fixed deadlock issue in audio pipeline
  - Fixed output parsing to extract transcriptions correctly
  - Successfully transcribing speech (e.g., "Oh, that's nice.")

## Working but Needs Tuning 🔧
- **VAD Sensitivity**: Currently triggering on background noise
  - Whisper hallucinates sounds from noise: "(dramatic music)", "(sigh)", "[SOUND]"
  - Fallback energy-based VAD may be too sensitive
  - Considers: adjusting threshold or using Silero VAD ONNX model
  - End-of-speech detection set to 1.5s of silence

## Pending
- Tune VAD thresholds to reduce false positives on background noise
- Download/configure Silero VAD ONNX model for better accuracy
- Integrate streaming STT with partials and endpointing
- Wire LLM (Gemini streaming) with partials and tool hooks
- Implement TTS (OpenVoice) with chunked/streamed synthesis
- Add barge-in: detect mic during TTS, cancel synth and LLM
- Plumb parallel fan-out: audio to STT and VAD concurrently
- Optimize CPU paths (Opus 16k, frame sizes, threads, pinning)
- Containerize for Runpod single-machine; add STUN config
- Add metrics/observability and health checks

## Current System Status (October 2024)
- **WebRTC Connection**: ✅ Working perfectly
- **Audio Streaming**: ✅ Real-time audio capture and processing (87-144 fps)
- **VAD Detection**: ✅ Turn start/end detection working (with false positives)
- **Audio Quality**: ✅ Good RMS levels (0.001-0.004 ambient, 0.029+ during speech)
- **DataChannel**: ✅ Bidirectional communication working
- **STT Integration**: ✅ Whisper.cpp transcribing successfully
- **Audio Bitrate**: ✅ Stable 28-31 kbps send rate

## Issues Fixed (October 9, 2024)
1. ✅ **Deadlock in audio pipeline**: Fixed by releasing lock before calling `_on_utterance_end()`
2. ✅ **Wrong Whisper binary**: Changed from Python Whisper to `whisper-cli`
3. ✅ **Invalid command parameters**: Updated to use correct whisper-cli flags
4. ✅ **Output parsing**: Now correctly extracts transcription from timestamp lines

## Next Steps (immediate)
1. **Tune VAD sensitivity**: Reduce false positives on background noise
2. **Add Silero VAD model**: Download and configure for better speech detection
3. **Add LLM integration**: Connect Gemini for response generation
4. **Implement TTS**: Add text-to-speech synthesis
5. **Add UI feedback**: Display transcriptions in the web interface
