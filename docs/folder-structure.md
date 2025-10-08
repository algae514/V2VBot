# Folder Structure

```
.
├─ docs/
│  ├─ README.md
│  ├─ plan.md
│  ├─ requirements.md
│  ├─ folder-structure.md
│  ├─ architecture-rules.md
│  └─ code-rules.md
├─ server/
│  ├─ app/
│  │  ├─ main.py
│  │  ├─ webrtc/
│  │  │  ├─ signaling.py
│  │  │  ├─ rtc_peer.py
│  │  │  └─ codecs.py
│  │  ├─ audio/
│  │  │  ├─ pipeline.py
│  │  │  ├─ vad.py
│  │  │  └─ resample.py
│  │  ├─ stt/
│  │  │  ├─ faster_whisper.py
│  │  │  └─ streaming.py
│  │  ├─ llm/
│  │  │  └─ gemini.py
│  │  ├─ tts/
│  │  │  ├─ openvoice.py
│  │  │  └─ streaming.py
│  │  ├─ control/
│  │  │  ├─ messages.py
│  │  │  └─ state.py
│  │  └─ metrics/
│  │     ├─ latency.py
│  │     └─ health.py
│  ├─ requirements.txt
│  └─ Dockerfile
├─ web/
│  ├─ public/
│  │  └─ index.html
│  └─ src/
│     ├─ main.js
│     ├─ webrtc.js
│     └─ ui.js
└─ .cursorrules
```

Notes:
- `server/app` uses FastAPI + aiortc; asyncio-based pipelines.
- All audio fixed at 16 kHz mono; Opus 20 ms frames.
- DataChannel carries transcripts, LLM partials, control signals, and metrics.

