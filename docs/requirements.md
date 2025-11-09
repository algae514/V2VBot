# Requirements

## Functional Requirements
- WebRTC streaming between browser and backend with upstream mic audio, downstream TTS audio, and a DataChannel.
- Streaming STT (Whisper via faster-whisper or whisper.cpp) with partial and final transcripts.
- Turn detection using WebRTC VAD + endpointing for end-of-utterance and barge-in detection.
- LLM integration (Gemini) with streaming partial tokens.
- TTS synthesis (HTTP-based service) with sentence-based streaming, parallel processing, and chunked output.
- Barge-in: new user speech interrupts TTS and cancels ongoing LLM/TTS pipeline.
- Minimal UI: one button to start, live transcript, speaking indicator, latency metrics.

## Non-Functional Requirements
- Low latency: first audible token target 550–900 ms on CPU machine.
- Robustness: maintain stable session for 30 minutes; graceful recovery on network hiccups.
- Observability: per-stage latencies, CPU utilization, event timeline; health/readiness endpoints.
- Security: HTTPS for signaling; SRTP via WebRTC; sanitized logs (no PII).
- Portability: runnable on local Windows dev and deployable to Runpod single-machine.

## Assumptions & Constraints
- CPU-first dev machine (Ryzen 7, 32 GB RAM); modest or no GPU.
- STUN server available; TURN optional for NAT traversal.
- Models pre-warmed at service start; model weights cached on disk.
- Audio format unified at 16 kHz mono; Opus 20 ms frames; DTX and FEC enabled.

