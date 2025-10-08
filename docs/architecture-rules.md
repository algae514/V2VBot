# Architectural Rules

## Core Principles
- Streaming-first: Process audio and tokens incrementally end-to-end.
- Parallel fan-out: Send each 20 ms input frame to STT and VAD concurrently.
- Early partials: Emit STT partials and LLM partial tokens as soon as available.
- Chunked TTS: Segment by punctuation/pauses; stream first chunk asap; overlap/crossfade.
- Single-resample: Normalize to 16 kHz mono once at ingress, avoid re-resampling.
- Barge-in: Mic VAD during TTS triggers cancel of TTS and LLM promptly.

## Turn Detection
- WebRTC VAD (20 ms frames, aggressiveness 2) + endpointing.
- Start-of-speech: 2–3 consecutive voiced frames.
- End-of-utterance: 400–600 ms unvoiced.
- Adaptive RMS gate and debounce to avoid spurious ends.

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

