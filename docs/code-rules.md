# Code Rules / Standards

## General
- Prefer clarity over cleverness; write descriptive names.
- No deep nesting; use guard clauses; handle errors explicitly.
- Keep functions short and single-purpose.

## Python
- Runtime: FastAPI/Starlette + aiortc; use async/await; enable uvloop.
- Typing: add type hints to public functions and data structures.
- Performance: reuse numpy buffers; avoid per-frame allocations; pin threads for STT.
- Logging: structured logs with event timestamps; avoid chatty logs in hot paths.

## Frontend (Web)
- Keep UI minimal; do not block on main thread; use Web Workers if needed later.
- WebRTC constraints: mono 16 kHz, ptime 20 ms; disable stereo; keep bitrate modest.
- Send control via DataChannel; handle cancel/barge-in immediately.

## Testing
- Add latency assertions on critical path.
- Include soak tests for 30-minute sessions.

## Git & Formatting
- Keep unrelated reformatting out of edits.
- One logical change per commit; meaningful messages.

## Docs & Cursor
- Update `docs/` when architecture changes.
- Follow `.cursorrules` for edit conventions.

