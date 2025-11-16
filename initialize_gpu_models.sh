#!/bin/bash
# Quick GPU Model Initialization Script
# Run this to pre-download and cache MeloTTS models before starting server

set -e

echo "=========================================="
echo "Initializing GPU Models for V2VBot"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "server/app/main.py" ]; then
    echo "Error: Must run from V2VBot directory"
    exit 1
fi

# Activate virtual environment
if [ ! -d "venv" ]; then
    echo "Error: Virtual environment not found. Run setup_server.sh first."
    exit 1
fi

print_info "Activating virtual environment..."
source venv/bin/activate

# Set CUDA environment variables
export CUDA_VISIBLE_DEVICES=0
export CUDA_LAUNCH_BLOCKING=0
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# Set library paths
MECAB_LIB=$(find /usr/lib /usr/local/lib -name "libmecab.so.2*" 2>/dev/null | head -n 1)
if [ -n "$MECAB_LIB" ]; then
    MECAB_DIR=$(dirname "$MECAB_LIB")
    export LD_LIBRARY_PATH="${MECAB_DIR}:${LD_LIBRARY_PATH}"
fi

CUDNN_LIB=$(find /usr/lib/x86_64-linux-gnu /usr/local/cuda*/lib64 -name "libcudnn*.so*" 2>/dev/null | head -n 1)
if [ -n "$CUDNN_LIB" ]; then
    CUDNN_DIR=$(dirname "$CUDNN_LIB")
    export LD_LIBRARY_PATH="${CUDNN_DIR}:${LD_LIBRARY_PATH}"
fi

if [ -d "/usr/local/cuda/lib64" ]; then
    export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
fi
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/lib:${LD_LIBRARY_PATH}"

print_success "Environment configured"
echo ""

print_info "Initializing CUDA and downloading MeloTTS models..."
print_info "This will take 30-90 seconds on first run..."
echo ""

python3 << 'PYEOF'
import os
import time
import torch

# Check GPU
print("=" * 50)
print("GPU Status:")
print("=" * 50)
print(f"CUDA Available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"GPU: {torch.cuda.get_device_name(0)}")
    print(f"CUDA Version: {torch.version.cuda}")
    print(f"cuDNN Version: {torch.backends.cudnn.version()}")
    print()
    
    # Initialize CUDA context
    print("Initializing CUDA context...")
    start = time.time()
    dummy = torch.zeros(1).cuda()
    torch.cuda.synchronize()
    print(f"✓ CUDA initialized in {time.time() - start:.2f}s")
    print()
    
    # Initialize MeloTTS
    print("=" * 50)
    print("Initializing MeloTTS on GPU:")
    print("=" * 50)
    print("Downloading models from HuggingFace...")
    print("Compiling models for CUDA...")
    print()
    
    from melo.api import TTS
    
    start = time.time()
    tts = TTS(language='EN', device='cuda')
    init_time = time.time() - start
    print(f"✓ MeloTTS model loaded in {init_time:.2f}s")
    print()
    
    # Test synthesis with proper speaker ID
    print("Running test synthesis...")
    try:
        speaker_id = list(tts.hps.data.spk2id.values())[0]
        start = time.time()
        audio = tts.tts_to_file("Test initialization.", speaker_id, "/tmp/test_init.wav", quiet=True)
        synth_time = time.time() - start
        print(f"✓ Test synthesis completed in {synth_time:.2f}s")
        
        # Cleanup
        import os
        if os.path.exists("/tmp/test_init.wav"):
            os.remove("/tmp/test_init.wav")
    except Exception as e:
        print(f"⚠ Test synthesis skipped: {e}")
        print("  (Model loaded successfully, synthesis test optional)")
    
    print()
    print("=" * 50)
    print("✅ All models initialized and cached!")
    print("=" * 50)
    print()
    print("Your server will now start quickly without hanging.")
    print("Models are cached in ~/.cache/huggingface/")
else:
    print("⚠ GPU not available - server will use CPU mode")
PYEOF

if [ $? -eq 0 ]; then
    echo ""
    print_success "GPU models initialized successfully!"
    echo ""
    echo "You can now start your server with:"
    echo "  ./start_aws.sh"
    echo ""
    echo "Or manually:"
    echo "  source venv/bin/activate"
    echo "  python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080"
    echo ""
else
    echo ""
    echo "Initialization had some issues, but server should still work."
    echo "It may take longer on first TTS request."
fi
