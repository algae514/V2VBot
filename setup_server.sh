#!/bin/bash
# V2VBot Server Setup Script (Non-Docker)
# Run this script after SSH into your RunPod server

set -e

echo "=========================================="
echo "V2VBot Server Setup (Non-Docker)"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    print_info "Running as root user - this is fine for RunPod environments"
fi

# 1. System Information
print_info "Checking system information..."
echo "Hostname: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo ""

# 2. Check GPU
print_info "Checking GPU..."
if command -v nvidia-smi &> /dev/null; then
    # Try the full query first, fallback to basic info if it fails
    if nvidia-smi --query-gpu=name,memory.total,driver_version,cuda_version --format=csv,noheader 2>/dev/null; then
        print_success "GPU detected with CUDA info"
    elif nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null; then
        print_success "GPU detected (basic info)"
    else
        # Fallback to basic nvidia-smi
        nvidia-smi
        print_success "GPU detected (basic output)"
    fi
else
    print_error "nvidia-smi not found. GPU may not be available."
fi
echo ""

# 3. Update system packages
print_info "Updating system packages..."
sudo apt-get update -qq
print_success "System packages updated"
echo ""

# 4. Install system dependencies
print_info "Installing system dependencies..."
sudo apt-get install -y -qq \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    git \
    wget \
    curl \
    ffmpeg \
    libsndfile1 \
    libsndfile1-dev \
    libopus0 \
    libopus-dev \
    portaudio19-dev \
    libportaudio2 \
    pkg-config \
    > /dev/null 2>&1
print_success "System dependencies installed"
echo ""

# 5. Check Python version
print_info "Checking Python version..."
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "Python version: $PYTHON_VERSION"
print_success "Python is available"
echo ""

# 6. Create application directory
APP_DIR="/workspace/V2VBot"
print_info "Setting up application directory: $APP_DIR"

if [ -d "$APP_DIR" ]; then
    print_info "Directory already exists. Using existing directory."
else
    mkdir -p /workspace
    print_success "Created /workspace directory"
fi

cd /workspace
echo "Current directory: $(pwd)"
echo ""

# 7. Clone or update repository
if [ -d "$APP_DIR/.git" ]; then
    print_info "Repository already exists. Pulling latest changes..."
    cd $APP_DIR
    git pull
    print_success "Repository updated"
else
    print_info "Cloning repository..."
    print_error "Please clone your repository manually:"
    echo "  cd /workspace"
    echo "  git clone <your-repo-url> V2VBot"
    echo ""
    echo "After cloning, run this script again or continue with manual setup."
    exit 0
fi

cd $APP_DIR
echo ""

# 8. Create Python virtual environment
print_info "Creating Python virtual environment..."
if [ -d "venv" ]; then
    print_info "Virtual environment already exists"
else
    python3 -m venv venv
    print_success "Virtual environment created"
fi
echo ""

# 9. Activate virtual environment and upgrade pip
print_info "Activating virtual environment and upgrading pip..."
source venv/bin/activate
pip install --upgrade pip setuptools wheel -q
print_success "Pip upgraded"
echo ""

# 10. Install Python dependencies
print_info "Installing Python dependencies (this may take a few minutes)..."
pip install -r server/requirements.txt
print_success "Python dependencies installed"
echo ""

# 11. Verify GPU support in Python
print_info "Verifying GPU support in Python..."
python3 << 'PYEOF'
import sys
try:
    import torch
    cuda_available = torch.cuda.is_available()
    print(f"PyTorch CUDA Available: {cuda_available}")
    if cuda_available:
        print(f"GPU Device: {torch.cuda.get_device_name(0)}")
        print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB")
        print(f"CUDA Version: {torch.version.cuda}")
except ImportError as e:
    print(f"Error importing torch: {e}")
    sys.exit(1)

try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    print(f"ONNX Runtime Providers: {providers}")
    if "CUDAExecutionProvider" in providers:
        print("✓ CUDA available for ONNX Runtime")
    else:
        print("⚠ CUDA not available for ONNX Runtime, will use CPU for VAD")
except ImportError as e:
    print(f"Error importing onnxruntime: {e}")
    sys.exit(1)
PYEOF

if [ $? -eq 0 ]; then
    print_success "GPU support verified"
else
    print_error "GPU verification failed"
fi
echo ""

# 12. Setup environment file
print_info "Setting up environment configuration..."
if [ ! -f ".env" ]; then
    if [ -f "env.example" ]; then
        cp env.example .env
        print_success "Created .env from env.example"
        echo ""
        print_info "IMPORTANT: Edit .env file and add your GEMINI_API_KEY"
        echo "  Run: nano .env"
        echo "  Or: vim .env"
        echo ""
        read -p "Press Enter to open nano editor to edit .env file (or Ctrl+C to skip)..." -r
        nano .env
    else
        print_error "env.example not found!"
        exit 1
    fi
else
    print_info ".env file already exists"
fi
echo ""

# 13. Verify API key is set
if grep -q "your_gemini_api_key_here" .env 2>/dev/null; then
    print_error "GEMINI_API_KEY not set in .env file!"
    echo "Please edit .env and add your API key before starting the server"
    exit 1
else
    print_success "API key appears to be configured"
fi
echo ""

# 14. Create necessary directories
print_info "Creating necessary directories..."
mkdir -p logs models debug_audio
print_success "Directories created"
echo ""

# 15. Download models
print_info "Checking for required models..."
if [ ! -f "models/silero_vad.onnx" ]; then
    print_info "Downloading Silero VAD model..."
    cd models
    wget -q --show-progress https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
    cd ..
    print_success "Silero VAD model downloaded"
else
    print_success "Silero VAD model already exists"
fi

if [ ! -f "models/ggml-small.en.bin" ]; then
    print_info "Whisper model will be downloaded automatically on first run"
fi
echo ""

# 16. Create systemd service (optional)
print_info "Creating systemd service for automatic startup..."
cat > /tmp/v2vbot.service << EOF
[Unit]
Description=V2VBot Voice-to-Voice AI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$APP_DIR/venv/bin/python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/server.log
StandardError=append:$APP_DIR/logs/server.log

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/v2vbot.service /etc/systemd/system/v2vbot.service
sudo systemctl daemon-reload
print_success "Systemd service created"
echo ""

# 17. Final information
echo ""
echo "=========================================="
print_success "Setup Complete!"
echo "=========================================="
echo ""
echo "Your V2VBot server is ready to run!"
echo ""
echo "📝 Next Steps:"
echo ""
echo "1. Start the server manually:"
echo "   cd $APP_DIR"
echo "   source venv/bin/activate"
echo "   python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080"
echo ""
echo "2. Or start as a system service:"
echo "   sudo systemctl start v2vbot"
echo "   sudo systemctl enable v2vbot  # Enable auto-start on boot"
echo "   sudo systemctl status v2vbot  # Check status"
echo ""
echo "3. View logs:"
echo "   tail -f $APP_DIR/logs/server.log"
echo "   # Or if using systemd:"
echo "   sudo journalctl -u v2vbot -f"
echo ""
echo "4. Access your application:"
echo "   Check your RunPod dashboard for the public URL"
echo "   Port: 8080"
echo ""
echo "📊 Useful Commands:"
echo "   Stop service:    sudo systemctl stop v2vbot"
echo "   Restart service: sudo systemctl restart v2vbot"
echo "   View logs:       tail -f logs/server.log"
echo "   GPU status:      nvidia-smi"
echo ""
print_info "For troubleshooting, see docs/gpu-deployment.md"
echo ""

