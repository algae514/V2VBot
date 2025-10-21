#!/bin/bash
# V2VBot VastAI Startup Script
# This script sets up and starts V2VBot on VastAI

set -e

echo "=========================================="
echo "V2VBot VastAI Startup"
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

# Check if we're in the right directory
if [ ! -f "server/app/main.py" ]; then
    print_error "V2VBot files not found. Please run this script from the V2VBot root directory."
    exit 1
fi

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_error ".env file not found!"
    echo "Please create a .env file with your configuration:"
    echo "  cp env.example .env"
    echo "  nano .env"
    echo ""
    echo "Required variables:"
    echo "  GEMINI_API_KEY=your_gemini_api_key_here"
    exit 1
fi

# Check if API key is configured
if grep -q "your_gemini_api_key_here" .env 2>/dev/null; then
    print_error "GEMINI_API_KEY not configured in .env file!"
    echo "Please edit .env and add your Gemini API key"
    exit 1
fi

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    print_info "Activating virtual environment..."
    source venv/bin/activate
    print_success "Virtual environment activated"
elif [ -d ".venv" ]; then
    print_info "Activating virtual environment..."
    source .venv/bin/activate
    print_success "Virtual environment activated"
else
    print_info "No virtual environment found, using system Python"
fi

# Check GPU availability
print_info "Checking GPU availability..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    print_success "GPU detected"
else
    print_info "No GPU detected, will use CPU"
fi

# Create necessary directories
print_info "Creating necessary directories..."
mkdir -p logs models debug_audio
print_success "Directories created"

# Check for required models
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

# Start TURN server for WebRTC
print_info "Starting TURN server for WebRTC..."
if command -v turnserver &> /dev/null; then
    # Start TURN server in background
    turnserver -a -v -n -u v2vbot:v2vbot123 -r "v2vbot" \
        --no-dtls --no-tls \
        --listening-port 3478 \
        --tls-listening-port 5349 \
        --min-port 50000 --max-port 50050 \
        --log-file logs/turn.log \
        --pidfile logs/turn.pid &
    
    print_success "TURN server started"
else
    print_info "TURN server not found, WebRTC may not work properly"
fi

# Start the server
print_info "Starting V2VBot server..."
echo ""
echo "=========================================="
print_success "Starting V2VBot on VastAI"
echo "=========================================="
echo ""
echo "Server will be available at: http://0.0.0.0:8080"
echo "WebRTC TURN server running on port 3478"
echo "Check your VastAI dashboard for the public URL"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Start the server with proper configuration for VastAI
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1
