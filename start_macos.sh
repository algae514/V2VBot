#!/usr/bin/env bash
set -euo pipefail

# V2VBot startup script for macOS
# This script starts the V2VBot server with proper environment variables

cd "$(dirname "$0")"

# Check if virtual environment exists
if [ ! -d .venv ]; then
    echo "Virtual environment not found. Please run install.sh first."
    exit 1
fi

# Check if models exist
if [ ! -f models/ggml-small.en.bin ]; then
    echo "Whisper small.en model not found. Please download models first."
    exit 1
fi

# Set environment variables
export WHISPER_CPP_BIN=/opt/homebrew/bin/whisper-cli
export WHISPER_CPP_MODEL=./models/ggml-small.en.bin
export SILERO_VAD_ONNX=./silero_vad.onnx

echo "killing if a process already running at the port ..."
# kill -9 $(lsof -ti :8000)

echo "Starting V2VBot server..."
export GEMINI_MODEL="gemini-2.0-flash"
echo "Server will be available at: http://localhost:8000"
echo "Press Ctrl+C to stop the server"

# Start the server
.venv/bin/python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8000 --reload
