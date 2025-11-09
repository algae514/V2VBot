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

✅ **Complete Voice-to-Voice Pipeline Working:**
- **WebRTC real-time audio streaming** (20ms frames)
- **Voice Activity Detection (Silero VAD)** with energy-based fallback
- **Speech-to-Text: Faster-Whisper integration** (small.en model)
  - High accuracy transcription with audio preprocessing
  - Dynamic sample rate detection (16k-96kHz support)
  - Stereo-to-mono conversion
- **LLM Integration: Google Gemini** (gemini-2.0-flash, configurable)
  - Streaming responses for real-time feedback
  - Conversation history maintained
  - Retry logic with exponential backoff for rate limits
- **TTS Integration: HTTP-based TTS service** 
  - Streaming TTS: Starts synthesis as soon as sentences are detected from LLM stream
  - Parallel processing: Multiple sentences synthesized concurrently
  - HTTP/2 connection pooling for reduced network latency
  - Ordered delivery: Sentences sent in LLM response order
  - Audio output: 22050Hz (from TTS service)
- **Barge-In Functionality**: Interrupt AI speech when user starts speaking
  - Immediate audio interruption and queue clearing
  - Natural conversation flow with interruption detection
- **WebRTC DataChannel communication** with event-driven architecture
- **Complete web UI** with voice input/output and interruption handling

✅ **Recently Implemented:**
- Complete voice-to-voice conversation pipeline
- TTS synthesis with sentence-based streaming
- Barge-in functionality for natural interruptions
- Audio quality improvements and sequential playback
- Console logging optimization

For implementation, start with the plan, then follow the folder structure and rules. The `.cursorrules` file guides Cursor to keep edits consistent with these docs.
