#!/bin/bash
# V2VBot Server Setup Script (Non-Docker)
# Run this script after SSH into your AWS/RunPod server

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
    print_info "Running as root user - this is fine for AWS/RunPod environments"
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
    print_info "Running as regular user - will use sudo for system commands"
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
$SUDO_CMD apt-get update -qq
print_success "System packages updated"
echo ""

# 4. Install system dependencies
print_info "Installing system dependencies..."
$SUDO_CMD apt-get install -y -qq \
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
    libssl-dev \
    sox \
    libsox-dev \
    libsox-fmt-all \
    mecab \
    libmecab2 \
    libmecab-dev \
    mecab-ipadic-utf8 \
    lsb-release \
    > /dev/null 2>&1
print_success "System dependencies installed"
echo ""

# 4a. Install cuDNN libraries (required for GPU-accelerated deep learning)
print_info "Installing cuDNN libraries..."
if command -v nvidia-smi &> /dev/null; then
    # Detect Ubuntu version for CUDA repository
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "22.04")
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
    
    # Check if CUDA repository is already configured
    CUDA_REPO_EXISTS=false
    if [ -d /etc/apt/sources.list.d ]; then
        for repo_file in /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/cuda-ubuntu*.list; do
            if [ -f "$repo_file" ]; then
                CUDA_REPO_EXISTS=true
                break
            fi
        done
    fi
    
    if [ "$CUDA_REPO_EXISTS" = false ]; then
        print_info "Adding NVIDIA CUDA repository for Ubuntu $UBUNTU_VERSION..."
        CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION//./}/x86_64/cuda-keyring_1.1-1_all.deb"
        
        if wget -q "$CUDA_KEYRING_URL" -O /tmp/cuda-keyring.deb 2>/dev/null; then
            $SUDO_CMD dpkg -i /tmp/cuda-keyring.deb > /dev/null 2>&1 || {
                print_error "Failed to install CUDA keyring"
                rm -f /tmp/cuda-keyring.deb
            }
            rm -f /tmp/cuda-keyring.deb
            $SUDO_CMD apt-get update -qq > /dev/null 2>&1 || true
            print_success "CUDA repository added"
        else
            print_info "Could not download CUDA keyring, trying alternative method..."
            # Try alternative keyring URL
            ALTERNATIVE_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb"
            if wget -q "$ALTERNATIVE_URL" -O /tmp/cuda-keyring.deb 2>/dev/null; then
                $SUDO_CMD dpkg -i /tmp/cuda-keyring.deb > /dev/null 2>&1 || true
                rm -f /tmp/cuda-keyring.deb
                $SUDO_CMD apt-get update -qq > /dev/null 2>&1 || true
                print_success "CUDA repository added (alternative method)"
            else
                print_info "CUDA repository setup skipped (may already be configured or network issue)"
            fi
        fi
    else
        print_info "CUDA repository already configured"
    fi
    
    # Try to install cuDNN 9 (for CUDA 12.x) - REQUIRED for PyTorch 2.9+
    CUDNN_INSTALLED=false
    print_info "Installing cuDNN libraries..."
    
    # Check what's already installed
    if dpkg -l | grep -q "libcudnn9-cuda-12\|libcudnn9"; then
        print_info "cuDNN 9 already installed"
        CUDNN_INSTALLED=true
    elif dpkg -l | grep -q "libcudnn8"; then
        print_info "cuDNN 8 detected, installing cuDNN 9 for PyTorch 2.9+ compatibility..."
        # Install cuDNN 9 for CUDA 12 (can coexist with cuDNN 8)
        if $SUDO_CMD apt-get install -y libcudnn9-cuda-12 2>&1 | grep -q "Setting up\|is already"; then
            print_success "cuDNN 9 (CUDA 12) installed"
            CUDNN_INSTALLED=true
        else
            # Try generic libcudnn9 package
            if $SUDO_CMD apt-get install -y libcudnn9 2>&1 | grep -q "Setting up\|is already"; then
                print_success "cuDNN 9 installed"
                CUDNN_INSTALLED=true
            else
                print_error "Failed to install cuDNN 9"
                print_info "cuDNN 8 may work but PyTorch 2.9+ prefers cuDNN 9"
            fi
        fi
    else
        # First, try cuDNN 9 for CUDA 12 (required for PyTorch 2.9+)
        print_info "Installing cuDNN 9 for CUDA 12..."
        if $SUDO_CMD apt-get install -y libcudnn9-cuda-12 2>&1 | grep -q "Setting up\|is already"; then
            print_success "cuDNN 9 (CUDA 12) installed"
            CUDNN_INSTALLED=true
        # Try generic libcudnn9 package
        elif $SUDO_CMD apt-get install -y libcudnn9 2>&1 | grep -q "Setting up\|is already"; then
            print_success "cuDNN 9 installed"
            CUDNN_INSTALLED=true
        # Fallback to cuDNN 8 (for CUDA 11.x and 12.0) - not recommended for PyTorch 2.9+
        elif $SUDO_CMD apt-get install -y libcudnn8 2>&1 | grep -q "Setting up\|is already"; then
            print_success "cuDNN 8 installed (fallback - may cause issues with PyTorch 2.9+)"
            CUDNN_INSTALLED=true
            print_info "Warning: PyTorch 2.9+ expects cuDNN 9. Consider upgrading to cuDNN 9"
        else
            print_error "cuDNN installation from repository failed"
            print_info "PyTorch includes bundled cuDNN, but system libraries may be needed"
            print_info "If you encounter cuDNN errors, try: sudo apt-get install -y libcudnn9-cuda-12"
        fi
    fi
    
    # Update library cache (critical for cuDNN to be found)
    print_info "Updating library cache..."
    $SUDO_CMD ldconfig
    print_success "Library cache updated"
    
    # Verify cuDNN installation and set LD_LIBRARY_PATH
    CUDNN_LIB=$(find /usr/lib/x86_64-linux-gnu /usr/local/cuda*/lib64 -name "libcudnn*.so*" 2>/dev/null | head -n 1)
    if [ -n "$CUDNN_LIB" ]; then
        CUDNN_DIR=$(dirname "$CUDNN_LIB")
        export LD_LIBRARY_PATH="${CUDNN_DIR}:${LD_LIBRARY_PATH}"
        print_success "cuDNN library found at: $CUDNN_LIB"
        
        # Also add to ld.so.conf for permanent configuration
        if [ "$EUID" -eq 0 ]; then
            if ! grep -q "$CUDNN_DIR" /etc/ld.so.conf.d/*.conf 2>/dev/null; then
                echo "$CUDNN_DIR" > /etc/ld.so.conf.d/cudnn.conf
                ldconfig
            fi
        else
            if ! grep -q "$CUDNN_DIR" /etc/ld.so.conf.d/*.conf 2>/dev/null; then
                echo "$CUDNN_DIR" | $SUDO_CMD tee /etc/ld.so.conf.d/cudnn.conf > /dev/null
                $SUDO_CMD ldconfig 2>/dev/null || true
            fi
        fi
    else
        if [ "$CUDNN_INSTALLED" = true ]; then
            print_info "cuDNN installed but library not found in standard locations"
            print_info "This is normal - PyTorch will use its bundled cuDNN"
        fi
    fi
    
    # Add standard CUDA library paths to LD_LIBRARY_PATH
    if [ -d "/usr/local/cuda/lib64" ]; then
        export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
    fi
    export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
else
    print_info "No GPU detected, skipping cuDNN installation"
fi
echo ""

# 4b. Configure mecab library cache
print_info "Configuring mecab library..."
MECAB_LIB=$(find /usr/lib /usr/local/lib -name "libmecab.so.2*" 2>/dev/null | head -n 1)
if [ -n "$MECAB_LIB" ]; then
    MECAB_DIR=$(dirname "$MECAB_LIB")
    echo -e "${GREEN}Found mecab library at: $MECAB_LIB${NC}"
    if [ "$EUID" -eq 0 ]; then
        echo "$MECAB_DIR" > /etc/ld.so.conf.d/mecab.conf
        ldconfig
    else
        echo "$MECAB_DIR" | $SUDO_CMD tee /etc/ld.so.conf.d/mecab.conf > /dev/null
        $SUDO_CMD ldconfig 2>/dev/null || ldconfig 2>/dev/null || true
    fi
    export LD_LIBRARY_PATH="${MECAB_DIR}:${LD_LIBRARY_PATH}"
    print_success "Mecab library configured"
else
    print_error "libmecab.so.2 not found after installation!"
    exit 1
fi
echo ""

# 4c. Install Rust compiler (needed for tokenizers)
print_info "Installing Rust compiler..."
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env" || true
    export PATH="$HOME/.cargo/bin:$PATH"
    print_success "Rust compiler installed"
else
    print_info "Rust already installed"
    source "$HOME/.cargo/env" || true
    export PATH="$HOME/.cargo/bin:$PATH"
fi
echo ""

# 5. Check Python version
print_info "Checking Python version..."
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo "Python version: $PYTHON_VERSION"
print_success "Python is available"
echo ""

# 6. Determine application directory
# If current directory is a git repo, use it; otherwise use /workspace/V2VBot
if [ -d ".git" ]; then
    APP_DIR="$(pwd)"
    print_info "Using current directory as application directory: $APP_DIR"
else
    APP_DIR="/workspace/V2VBot"
    print_info "Setting up application directory: $APP_DIR"
    
    if [ -d "$APP_DIR" ]; then
        print_info "Directory already exists. Using existing directory."
    else
        $SUDO_CMD mkdir -p /workspace
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
fi

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
# Install base requirements first
pip install --no-cache-dir -r server/requirements.txt || {
    print_error "Failed to install base Python dependencies"
    exit 1
}

# Ensure onnxruntime-gpu is installed (may be needed if requirements.txt has issues)
# Uninstall regular onnxruntime first to avoid conflicts
print_info "Verifying onnxruntime-gpu installation..."
pip uninstall -y onnxruntime 2>/dev/null || true
pip install --no-cache-dir --upgrade onnxruntime-gpu>=1.16.0 || {
    print_info "onnxruntime-gpu installation had issues, but continuing..."
}

# Install MeloTTS without dependencies to avoid transformers conflict
print_info "Installing MeloTTS..."
pip install --no-cache-dir --no-deps git+https://github.com/myshell-ai/MeloTTS.git@main || {
    print_error "Failed to install MeloTTS"
    exit 1
}

# Install MeloTTS dependencies (excluding transformers which is already installed)
print_info "Installing MeloTTS dependencies..."
pip install --no-cache-dir \
    anyascii==0.3.2 \
    cached_path \
    cn2an==0.5.22 \
    eng_to_ipa==0.0.2 \
    fugashi==1.3.0 \
    g2p_en==2.1.0 \
    'g2pkk>=0.1.1' \
    'gruut[de,es,fr]==2.2.3' \
    inflect==7.0.0 \
    jamo==0.4.1 \
    jieba==0.42.1 \
    langid==1.1.6 \
    librosa==0.9.1 \
    loguru==0.7.2 \
    mecab-python3==1.0.9 \
    num2words==0.5.12 \
    pydub==0.25.1 \
    pykakasi==2.2.1 \
    pypinyin==0.50.0 \
    tensorboard==2.16.2 \
    txtsplit \
    unidecode==1.3.7 \
    unidic==1.1.0 \
    unidic_lite==1.0.8 || {
    print_info "Some MeloTTS dependencies failed to install, continuing..."
}

# Download UniDic dictionary
print_info "Downloading UniDic dictionary (this may take a while)..."
python3 -m unidic download || {
    print_info "UniDic download failed or already exists, continuing..."
}

print_success "Python dependencies installed"
echo ""

# 11. Verify GPU support and TTS installation
print_info "Verifying GPU support and TTS installation..."
MECAB_LIB=$(find /usr/lib /usr/local/lib -name "libmecab.so.2*" 2>/dev/null | head -n 1)
if [ -n "$MECAB_LIB" ]; then
    MECAB_DIR=$(dirname "$MECAB_LIB")
    export LD_LIBRARY_PATH="${MECAB_DIR}:${LD_LIBRARY_PATH}"
fi

# Add cuDNN to library path if available
CUDNN_LIB=$(find /usr/lib/x86_64-linux-gnu /usr/local/cuda*/lib64 -name "libcudnn*.so*" 2>/dev/null | head -n 1)
if [ -n "$CUDNN_LIB" ]; then
    CUDNN_DIR=$(dirname "$CUDNN_LIB")
    export LD_LIBRARY_PATH="${CUDNN_DIR}:${LD_LIBRARY_PATH}"
fi

# Add standard CUDA library paths
if [ -d "/usr/local/cuda/lib64" ]; then
    export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
fi
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/lib:${LD_LIBRARY_PATH}"

python3 << 'PYEOF'
import sys
import os
import subprocess

# Set library paths
ld_paths = []
mecab_lib = os.popen("find /usr/lib /usr/local/lib -name 'libmecab.so.2*' 2>/dev/null | head -n 1").read().strip()
if mecab_lib:
    mecab_dir = os.path.dirname(mecab_lib)
    ld_paths.append(mecab_dir)

# Add cuDNN paths
cudnn_lib = os.popen("find /usr/lib/x86_64-linux-gnu /usr/local/cuda*/lib64 -name 'libcudnn*.so*' 2>/dev/null | head -n 1").read().strip()
if cudnn_lib:
    cudnn_dir = os.path.dirname(cudnn_lib)
    ld_paths.append(cudnn_dir)

# Add CUDA paths
if os.path.isdir("/usr/local/cuda/lib64"):
    ld_paths.append("/usr/local/cuda/lib64")
ld_paths.extend(["/usr/lib/x86_64-linux-gnu", "/usr/local/lib", "/usr/lib"])

os.environ['LD_LIBRARY_PATH'] = ":".join(ld_paths + [os.environ.get('LD_LIBRARY_PATH', '')])

# Test 1: PyTorch and CUDA
try:
    import torch
    cuda_available = torch.cuda.is_available()
    print(f"PyTorch CUDA Available: {cuda_available}")
    if cuda_available:
        print(f"GPU Device: {torch.cuda.get_device_name(0)}")
        print(f"GPU Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB")
        print(f"CUDA Version: {torch.version.cuda}")
        # Check cuDNN in PyTorch
        if torch.backends.cudnn.is_available():
            print(f"✓ PyTorch cuDNN Available: {torch.backends.cudnn.version()}")
        else:
            print("⚠ PyTorch cuDNN not available (may use system cuDNN)")
except ImportError as e:
    print(f"Error importing torch: {e}")
    sys.exit(1)

# Test 2: ONNX Runtime
try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    print(f"ONNX Runtime Providers: {providers}")
    if "CUDAExecutionProvider" in providers:
        print("✓ CUDA available for ONNX Runtime (VAD will use GPU)")
    else:
        print("⚠ CUDA not available for ONNX Runtime, will use CPU for VAD")
        print("  Install onnxruntime-gpu: pip install onnxruntime-gpu")
except ImportError as e:
    print(f"✗ Error importing onnxruntime: {e}")
    print("  Installing onnxruntime-gpu...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "onnxruntime-gpu>=1.16.0"])
    import onnxruntime as ort
    providers = ort.get_available_providers()
    print(f"ONNX Runtime Providers (after install): {providers}")
    if "CUDAExecutionProvider" in providers:
        print("✓ CUDA available for ONNX Runtime (VAD will use GPU)")
    else:
        print("⚠ CUDA still not available for ONNX Runtime")

# Test 3: MeCab library
try:
    import ctypes
    ctypes.CDLL('libmecab.so.2')
    print("✓ MeCab library available")
except Exception as e:
    print(f"⚠ MeCab library check failed: {e}")

# Test 4: cuDNN system library check
if cudnn_lib:
    print(f"✓ System cuDNN library found: {cudnn_lib}")
else:
    print("ℹ System cuDNN library not found (PyTorch uses bundled cuDNN)")

# Test 5: MeloTTS import
try:
    from melo.api import TTS
    print("✓ MeloTTS import successful")
except ImportError as e:
    print(f"✗ MeloTTS import failed: {e}")
    sys.exit(1)
PYEOF

if [ $? -eq 0 ]; then
    print_success "GPU support and TTS installation verified"
else
    print_error "Verification failed"
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
if command -v systemctl &> /dev/null; then
    # Check for SSL certificates
    SSL_CERT="$APP_DIR/ssl/cert.pem"
    SSL_KEY="$APP_DIR/ssl/key.pem"
    SSL_ARGS=""
    
    if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
        SSL_ARGS="--ssl-keyfile $SSL_KEY --ssl-certfile $SSL_CERT"
        print_info "SSL certificates found - HTTPS will be enabled in systemd service"
    else
        print_info "SSL certificates not found - HTTP will be used (HTTPS required for microphone access)"
    fi
    
    # Build LD_LIBRARY_PATH for systemd service
    LD_LIBRARY_PATH_VAR="$APP_DIR/venv/lib"
    
    # Add cuDNN path if available
    CUDNN_LIB=$(find /usr/lib/x86_64-linux-gnu /usr/local/cuda*/lib64 -name "libcudnn*.so*" 2>/dev/null | head -n 1)
    if [ -n "$CUDNN_LIB" ]; then
        CUDNN_DIR=$(dirname "$CUDNN_LIB")
        LD_LIBRARY_PATH_VAR="${CUDNN_DIR}:${LD_LIBRARY_PATH_VAR}"
    fi
    
    # Add CUDA paths
    if [ -d "/usr/local/cuda/lib64" ]; then
        LD_LIBRARY_PATH_VAR="/usr/local/cuda/lib64:${LD_LIBRARY_PATH_VAR}"
    fi
    
    # Add MeCab path if available
    MECAB_LIB=$(find /usr/lib /usr/local/lib -name "libmecab.so.2*" 2>/dev/null | head -n 1)
    if [ -n "$MECAB_LIB" ]; then
        MECAB_DIR=$(dirname "$MECAB_LIB")
        LD_LIBRARY_PATH_VAR="${MECAB_DIR}:${LD_LIBRARY_PATH_VAR}"
    fi
    
    # Add standard library paths
    LD_LIBRARY_PATH_VAR="/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/lib:${LD_LIBRARY_PATH_VAR}"
    
    cat > /tmp/v2vbot.service << EOF
[Unit]
Description=V2VBot Voice-to-Voice AI Service
After=network.target

[Service]
Type=simple
User=${SUDO_USER:-root}
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="LD_LIBRARY_PATH=${LD_LIBRARY_PATH_VAR}"
ExecStart=$APP_DIR/venv/bin/python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1 $SSL_ARGS
Restart=always
RestartSec=10
StandardOutput=append:$APP_DIR/logs/server.log
StandardError=append:$APP_DIR/logs/server.log

[Install]
WantedBy=multi-user.target
EOF

    $SUDO_CMD mv /tmp/v2vbot.service /etc/systemd/system/v2vbot.service
    $SUDO_CMD systemctl daemon-reload
    print_success "Systemd service created with proper library paths"
else
    print_info "systemctl not available, skipping systemd service creation"
fi
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
SSL_CERT_CHECK="$APP_DIR/ssl/cert.pem"
SSL_KEY_CHECK="$APP_DIR/ssl/key.pem"
if [ -f "$SSL_CERT_CHECK" ] && [ -f "$SSL_KEY_CHECK" ]; then
    echo "   Server will use HTTPS (SSL certificates found)"
    echo "   Access at: https://<your-ip>:8080"
else
    echo "   Server will use HTTP"
    echo "   Note: HTTPS is required for microphone access"
    echo "   Access at: http://<your-ip>:8080"
fi
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

