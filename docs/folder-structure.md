# Folder Structure

```
.
├─ docs/
│  ├─ README.md
│  ├─ plan.md
│  ├─ requirements.md
│  ├─ folder-structure.md
│  ├─ architecture-rules.md
│  ├─ code-rules.md
│  └─ current-status.md
├─ server/
│  ├─ app/
│  │  ├─ main.py
│  │  ├─ audio/
│  │  │  ├─ pipeline.py
│  │  │  ├─ vad_silero.py
│  │  │  └─ resample.py
│  │  └─ stt/
│  │     └─ whisper_faster.py
│  ├─ requirements.txt
│  └─ start_macos.sh
├─ web/
│  ├─ public/
│  │  └─ index.html
│  └─ src/
│     └─ main.js
├─ models/
│  ├─ silero_vad.onnx
│  └─ (other model files - gitignored)
├─ .gitignore
└─ .cursorrules
```

Notes:
- `server/app` uses FastAPI + aiortc; asyncio-based pipelines.
- Audio supports dynamic sample rates (16k-96kHz) with automatic detection.
- Uses Silero VAD for voice detection and faster-whisper for STT.
- DataChannel carries transcripts, control signals, and metrics.
- Models are gitignored and stored in `models/` directory.

