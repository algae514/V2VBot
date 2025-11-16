#!/bin/bash
# AWS Startup Script for V2VBot
# This script sets up and runs V2VBot on an AWS instance

set -e

echo "==================================="
echo "V2VBot AWS Startup"
echo "==================================="

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo ""
    echo "ERROR: Virtual environment not found!"
    echo "Please run setup_server.sh first to set up the environment."
    exit 1
fi

# Activate virtual environment
source venv/bin/activate

# Set CUDA environment variables to prevent hanging
export CUDA_VISIBLE_DEVICES=0
export CUDA_LAUNCH_BLOCKING=0
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# Set up library paths for cuDNN and CUDA
# Use direct path instead of find for speed
if command -v nvidia-smi &> /dev/null; then
    # Ensure ldconfig cache is up to date (important for cuDNN)
    if command -v ldconfig &> /dev/null; then
        sudo ldconfig 2>/dev/null || true
    fi
    
    # Set LD_LIBRARY_PATH with standard library directory first (contains cuDNN 9)
    # This directory is already in default search path, but explicitly setting ensures it's first
    export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
    
    # Add CUDA library paths if they exist
    if [ -d "/usr/local/cuda/lib64" ]; then
        export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
    fi
    
    # Verify cuDNN 9 libraries are accessible
    if [ -f "/usr/lib/x86_64-linux-gnu/libcudnn_ops.so.9" ] || [ -f "/usr/lib/x86_64-linux-gnu/libcudnn.so.9" ]; then
        echo "✓ cuDNN 9 libraries found in /usr/lib/x86_64-linux-gnu"
    else
        echo "⚠ Warning: cuDNN 9 libraries not found - may cause errors"
    fi
fi
# Ensure standard library paths are included
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/lib:${LD_LIBRARY_PATH}"

# Print GPU information if available
echo ""
if command -v nvidia-smi &> /dev/null; then
    echo "GPU Information:"
    nvidia-smi --query-gpu=name,memory.total,driver_version,cuda_version --format=csv,noheader 2>/dev/null || nvidia-smi
    echo ""
    
    # Check CUDA availability
    echo "Checking CUDA availability..."
    python3 -c "import torch; print(f'PyTorch CUDA Available: {torch.cuda.is_available()}')" || {
        echo "Warning: PyTorch CUDA not available"
    }
    echo ""
else
    echo "No GPU detected (nvidia-smi not found)"
    echo "Server will run on CPU"
    echo ""
fi

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
set -a
source .env
set +a

# Create necessary directories
mkdir -p logs models debug_audio

# Check if models exist
echo ""
echo "Checking models..."
if [ ! -f "models/silero_vad.onnx" ]; then
    echo "Downloading Silero VAD model..."
    cd models
    wget -q --show-progress https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx || {
        echo "Warning: Failed to download Silero VAD model"
    }
    cd ..
fi

if [ ! -f "models/ggml-small.en.bin" ]; then
    echo "Whisper model will be downloaded automatically on first run"
fi

echo ""
echo "Models ready!"

# Verify GPU setup if GPU is available
if command -v nvidia-smi &> /dev/null; then
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
fi

# Check for SSL certificates
SSL_CERT="ssl/cert.pem"
SSL_KEY="ssl/key.pem"
USE_SSL=false

if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
    USE_SSL=true
    echo ""
    echo "✓ SSL certificates found - HTTPS will be enabled"
    echo ""
fi

# Start the application
echo ""
echo "Starting V2VBot server..."

if [ "$USE_SSL" = true ]; then
    echo "Server will be available at https://0.0.0.0:${PORT:-8080}"
    echo "SSL Certificate: $SSL_CERT"
    echo "SSL Key: $SSL_KEY"
else
    echo "Server will be available at http://0.0.0.0:${PORT:-8080}"
    echo "Note: SSL certificates not found. For microphone access, HTTPS is required."
fi

echo ""
echo "Press Ctrl+C to stop"
echo ""

# Run with uvicorn
if [ "$USE_SSL" = true ]; then
    python3 -m uvicorn server.app.main:app --host "${HOST:-0.0.0.0}" --port "${PORT:-8080}" --workers 1 --ssl-keyfile "$SSL_KEY" --ssl-certfile "$SSL_CERT"
else
    python3 -m uvicorn server.app.main:app --host "${HOST:-0.0.0.0}" --port "${PORT:-8080}" --workers 1
fi
