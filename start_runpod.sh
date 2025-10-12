#!/bin/bash
# RunPod Startup Script for V2VBot
# This script sets up and runs V2VBot on a RunPod GPU instance

set -e

echo "==================================="
echo "V2VBot RunPod Startup"
echo "==================================="

# Print GPU information
echo ""
echo "GPU Information:"
nvidia-smi --query-gpu=name,memory.total,driver_version,cuda_version --format=csv,noheader
echo ""

# Check CUDA availability
echo "Checking CUDA availability..."
python3 -c "import torch; print(f'PyTorch CUDA Available: {torch.cuda.is_available()}')" || {
    echo "Error: PyTorch CUDA not available"
    echo "Installing PyTorch with CUDA support..."
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
}

# Check for .env file
if [ ! -f ".env" ]; then
    echo ""
    echo "WARNING: .env file not found!"
    echo "Creating .env from env.example..."
    if [ -f "env.example" ]; then
        cp env.example .env
        echo ""
        echo "Please edit .env and add your GEMINI_API_KEY:"
        echo "  nano .env"
        echo ""
        read -p "Press Enter after you've set GEMINI_API_KEY to continue..."
    else
        echo "ERROR: env.example not found!"
        exit 1
    fi
fi

# Verify API key is set
if grep -q "your_gemini_api_key_here" .env 2>/dev/null; then
    echo ""
    echo "ERROR: GEMINI_API_KEY not set in .env file!"
    echo "Please edit .env and add your API key:"
    echo "  nano .env"
    echo ""
    exit 1
fi

# Source environment variables
export $(cat .env | grep -v '^#' | xargs)

# Create necessary directories
mkdir -p logs models debug_audio

# Check if models exist
echo ""
echo "Checking models..."
if [ ! -f "models/silero_vad.onnx" ]; then
    echo "Downloading Silero VAD model..."
    cd models
    wget -q --show-progress https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
    cd ..
fi

if [ ! -f "models/ggml-small.en.bin" ]; then
    echo "Whisper model will be downloaded automatically on first run"
fi

echo ""
echo "Models ready!"

# Verify GPU setup
echo ""
echo "Verifying GPU setup..."
python3 << 'PYEOF'
import torch
import onnxruntime as ort

print("\n=== GPU Configuration ===")
print(f"PyTorch CUDA Available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"GPU Device: {torch.cuda.get_device_name(0)}")
    print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB")
    print(f"CUDA Version: {torch.version.cuda}")

print(f"\nONNX Runtime Providers: {ort.get_available_providers()}")
if "CUDAExecutionProvider" in ort.get_available_providers():
    print("✓ CUDA available for ONNX Runtime (Silero VAD)")
else:
    print("⚠ CUDA not available for ONNX Runtime, will use CPU")

print("\n=== Ready to start! ===\n")
PYEOF

# Start the application
echo ""
echo "Starting V2VBot server..."
echo "Server will be available at http://0.0.0.0:8080"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Run with uvicorn
python3 -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1

