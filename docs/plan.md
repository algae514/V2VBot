# Project Plan: V2VBot (Voice-to-Voice Bot)

## Goals
- Ultra-low-latency, full-duplex voice assistant with streaming E2E (WebRTC).
- CPU-first local development (Ryzen 7, 32 GB RAM); upgradeable to GPU later.
- Components: Whisper (faster-whisper) for STT, Gemini for LLM, MeloTTS-English v3 for TTS, Silero VAD + endpointing for turn detection, barge-in support.

## Phases
1. MVP ✅ COMPLETE
   - WebRTC pipeline (audio up/down + DataChannel) ✅
   - Streaming STT partials, endpointing/finals ✅
   - Gemini streaming with partial tokens ✅
   - HTTP-based TTS service with sentence-based streaming, parallel processing, and ordered delivery ✅
   - Barge-in: detect mic speech during TTS → cancel TTS and LLM ✅
2. Latency & UX Tuning ✅ COMPLETE
   - VAD/endpoint thresholds implemented (1000ms turn end, configurable).
   - TTS sentence-based streaming with parallel processing and ordered delivery implemented.
   - Phase 1-3 optimizations: HTTP/2 pooling, parallel TTS, streaming TTS.
3. Reliability & Ops
   - STUN/TURN fallback, reconnection.
   - Metrics/observability (latency budget per stage), health checks.
4. Quality
   - Prosody tuning, noise robustness, speaker profiles.
5. Deploy
   - Containerize for Runpod single-machine; model warmup.

## Latency Budget (targets)
- Capture+uplink: 15–30 ms
- STT partials: 150–250 ms
- Endpoint finalization: ~300–600 ms after last speech (parallel)
- LLM first tokens: 120–250 ms
- TTS first audio: 200–350 ms
- Downlink playout: 20–40 ms
- First audible response: 550–900 ms

## Success Criteria
- p50 first response < 800 ms on local CPU.
- Robust barge-in (< 100–150 ms cancel from new speech onset).
- No crashes during 30-minute continuous session; CPU < 90% sustained.

## References
- See architectural rules (`docs/architecture-rules.md`) and code rules (`docs/code-rules.md`).
- Editor automation in `.cursorrules` at repo root.

