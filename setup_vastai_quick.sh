#!/bin/bash
# Quick VastAI Setup Script for V2VBot
# Run this after cloning the repository on VastAI

set -e

echo "=========================================="
echo "V2VBot Quick VastAI Setup"
echo "=========================================="

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }

# 1. Install system dependencies
print_info "Installing system dependencies..."
apt-get update
apt-get install -y \
    python3.10 python3-pip python3-dev \
    build-essential git wget curl \
    ffmpeg libsndfile1 libopus0 libopus-dev \
    portaudio19-dev libportaudio2 \
    coturn \
    && rm -rf /var/lib/apt/lists/*

print_success "System dependencies installed"

# 2. Install Python dependencies
print_info "Installing Python dependencies..."
pip3 install --upgrade pip setuptools wheel
pip3 install -r server/requirements.txt
pip3 install git+https://github.com/myshell-ai/MeloTTS.git

print_success "Python dependencies installed"

# 3. Create directories
print_info "Creating directories..."
mkdir -p logs models debug_audio
print_success "Directories created"

# 4. Download models
print_info "Downloading models..."
cd models
if [ ! -f "silero_vad.onnx" ]; then
    wget -q --show-progress https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
fi
cd ..

print_success "Models downloaded"

# 5. Create environment file
print_info "Creating environment file..."
if [ ! -f ".env" ]; then
    cp env.example .env
    print_info "Created .env file - please edit it with your GEMINI_API_KEY"
fi

print_success "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env file: nano .env"
echo "2. Add your GEMINI_API_KEY"
echo "3. Run: ./start_vastai.sh"
echo ""
