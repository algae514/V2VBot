#!/bin/bash
# V2VBot Docker Start Script
set -e

echo "=========================================="
echo "V2VBot Docker Container Starting"
echo "=========================================="

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found, creating from template..."
    if [ -f "env.example" ]; then
        cp env.example .env
        echo "📝 Created .env from env.example"
        echo "⚠️  Please configure GEMINI_API_KEY in .env file"
    else
        echo "❌ No env.example found!"
        exit 1
    fi
fi

# Check GPU availability
echo "🔍 Checking GPU availability..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    echo "✅ GPU detected"
else
    echo "⚠️  No GPU detected, will use CPU"
fi

# Check Python GPU support
echo "🔍 Checking Python GPU support..."
python3 << 'PYEOF'
import sys
try:
    import torch
    cuda_available = torch.cuda.is_available()
    print(f"PyTorch CUDA Available: {cuda_available}")
    if cuda_available:
        print(f"GPU Device: {torch.cuda.get_device_name(0)}")
        print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB")
except ImportError as e:
    print(f"Error importing torch: {e}")
    sys.exit(1)

try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    print(f"ONNX Runtime Providers: {providers}")
    if "CUDAExecutionProvider" in providers:
        print("✅ CUDA available for ONNX Runtime")
    else:
        print("⚠️  CUDA not available for ONNX Runtime, will use CPU for VAD")
except ImportError as e:
    print(f"Error importing onnxruntime: {e}")
    sys.exit(1)
PYEOF

# Start TURN server in background (for WebRTC)
echo "🔄 Starting TURN server..."
turnserver --listening-port=3478 --tls-listening-port=5349 \
    --realm=v2vbot --server-name=v2vbot \
    --user=v2vbot:v2vbot123 --lt-cred-mech \
    --no-multicast-peers --no-cli \
    --no-tlsv1 --no-tlsv1_1 --no-sslv2 --no-sslv3 \
    --no-dtls --no-dtlsv1 --no-sslv2 --no-sslv3 \
    --relay-ip=0.0.0.0 --external-ip=0.0.0.0 \
    --min-port=50000 --max-port=50050 &
TURN_PID=$!

# Wait a moment for TURN server to start
sleep 2

# Start V2VBot application
echo "🚀 Starting V2VBot application..."
echo "📡 Server will be available at: http://0.0.0.0:8080"
echo "🔄 TURN server running on ports 3478/5349"
echo ""

# Start the FastAPI application
exec python3 -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1
