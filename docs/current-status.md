# Current Status

## Completed
- Define low-latency E2E architecture and latency budget
- Author docs: overall plan and requirements in docs
- Document folder structure in docs
- Write architectural rules in docs
- Write code rules/standards in docs
- Create Cursor instruction file and reference it from docs
- Scaffold repo with backend (FastAPI+aiortc) and minimal web client
- Serve static files via FastAPI and prefix API routes
- Create start.sh to bootstrap venv and run server

## In Progress
- Implement WebRTC signaling (REST+WebSocket) and media/data channels

## Pending
- Integrate streaming STT (faster-whisper/whisper.cpp) with CPU INT8
- Add lightweight turn detection (webrtcvad + endpointing)
- Wire LLM (Gemini streaming) with partials and tool hooks
- Implement TTS (OpenVoice) with chunked/streamed synthesis
- Add barge-in: detect mic during TTS, cancel synth and LLM
- Plumb parallel fan-out: audio to STT and VAD concurrently
- Build minimal UI: click-to-talk, real-time transcript, audio out
- Optimize CPU paths (Opus 16k, frame sizes, threads, pinning)
- Containerize for Runpod single-machine; add STUN config
- Add metrics/observability and health checks

## Next Steps (short-term)
- Finish signaling stability and confirm end-to-end WebRTC connection.
- Integrate streaming STT with partials and endpointing.
- Add VAD-based turn detection and surface events over DataChannel.
