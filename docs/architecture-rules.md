# Architectural Rules

## Core Principles
- Streaming-first: Process audio and tokens incrementally end-to-end.
- Parallel fan-out: Send each 20 ms input frame to STT and VAD concurrently.
- Early partials: Emit STT partials and LLM partial tokens as soon as available.
- Chunked TTS: Sentence-based streaming with HTTP-based TTS service; stream first sentence asap; parallel synthesis with ordered delivery; sequential playback.
- Single-resample: Normalize to 16 kHz mono once at ingress, avoid re-resampling.
- Barge-in: Mic VAD during TTS triggers cancel of TTS and LLM promptly.

## Turn Detection
- Silero VAD (20 ms frames) + endpointing.
- Start-of-speech: 20ms of consecutive voiced frames.
- End-of-utterance: 1000ms of unvoiced (configurable, optimized for real-time conversation).
- Fallback to energy-based detection if Silero fails.

## Concurrency & Backpressure
- Async pipelines with bounded queues; drop or coalesce old partials under pressure.
- Cancellation tokens propagate from barge-in to LLM and TTS tasks.
- Avoid per-frame allocations; reuse buffers; pre-warm all models.

## Transport & Codecs
- WebRTC Opus mono 16 kHz; ptime 20 ms; DTX, FEC on.
- STUN always; TURN only when necessary (coturn).

## Observability
- Measure and log timestamps for: ingress, STT partial, endpoint final, LLM first token, TTS first audio, playback start.
- Health and readiness endpoints; include model warm state.

## Security
- HTTPS for signaling; SRTP via WebRTC; sanitize logs; no PII in traces.

## Deployment
- Containerized single-process service with FastAPI + aiortc; uvloop.
- Model artifacts cached on volume; warmup at startup.

