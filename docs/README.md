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
# Install dependencies
brew install whisper-cpp

# Start the server
./start_macos.sh

# Open browser to http://localhost:8000
```

## Current Status (October 2024)

✅ **Working:**
- WebRTC real-time audio streaming (28-31 kbps)
- Voice Activity Detection (VAD) with energy-based fallback
- Audio pipeline processing (16kHz mono, 87-144 fps)
- WebRTC DataChannel communication
- Minimal web UI with click-to-talk
- **Speech-to-Text: Whisper.cpp integration working!**
  - Successfully transcribing speech
  - Fixed binary path and output parsing issues

🔧 **Needs Tuning:**
- VAD sensitivity: Reduces false positives from background noise
- Whisper hallucinations on ambient sounds (e.g., "(dramatic music)", "(sigh)")

For implementation, start with the plan, then follow the folder structure and rules. The `.cursorrules` file guides Cursor to keep edits consistent with these docs.
