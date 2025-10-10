# V2VBot Documentation

This folder contains the project plan, requirements, folder structure, architectural rules, and code rules for the low-latency voice-to-voice bot.

- Plan: see `plan.md`
- Requirements: see `requirements.md`
- Folder structure: see `folder-structure.md`
- Architectural rules: see `architecture-rules.md`
- Code rules/standards: see `code-rules.md`
- **Current Status**: see `current-status.md` ⭐
- Cursor instructions: see repo root file `.cursorrules`

## Quick Start (macOS)

```bash
# Install dependencies (if needed)
# Models are automatically downloaded by faster-whisper

# Start the server
./start_macos.sh

# Open browser to http://localhost:8000
```

## Current Status (January 2025)

✅ **Working:**
- WebRTC real-time audio streaming
- Voice Activity Detection (Silero VAD) with energy-based fallback
- Audio pipeline processing with dynamic sample rate detection
- WebRTC DataChannel communication
- Minimal web UI with click-to-talk
- **Speech-to-Text: Faster-Whisper integration working!**
  - High accuracy transcription with audio preprocessing
  - Dynamic sample rate detection (16k-96kHz support)
  - Stereo-to-mono conversion
  - Production-ready with clean code

✅ **Recently Fixed:**
- Sample rate mismatch issues (browser stereo vs mono)
- VAD sensitivity and false positives
- Audio quality and preprocessing
- Code cleanup and production readiness

For implementation, start with the plan, then follow the folder structure and rules. The `.cursorrules` file guides Cursor to keep edits consistent with these docs.
