#!/bin/bash
# AWS Startup Script for V2VBot
# This script sets up and runs V2VBot on an AWS EC2 instance

set -euo pipefail

cd "$(dirname "$0")"

echo "==================================="
echo "V2VBot AWS Startup"
echo "==================================="

# Configuration
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
APP="server.app.main:app"
PIDFILE=".uvicorn.pid"

# SSL Configuration
SSL_CERT="${SSL_CERT:-ssl/cert.pem}"
SSL_KEY="${SSL_KEY:-ssl/key.pem}"

# Print instance information
echo ""
echo "Instance Information:"
echo "  Hostname: $(hostname -f 2>/dev/null || hostname)"
echo "  Public IP: $(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo 'unknown')"
echo ""

# Check for GPU (optional, AWS instances may or may not have GPU)
if command -v nvidia-smi &> /dev/null; then
    echo "GPU Information:"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null || echo "  No GPU detected"
    echo ""
    
    # Check CUDA availability
    echo "Checking CUDA availability..."
    if [ -d "venv" ] || [ -d ".venv" ]; then
        VENV_DIR="${VENV_DIR:-venv}"
        [ -d ".venv" ] && VENV_DIR=".venv"
        
        if [ -f "$VENV_DIR/bin/python" ]; then
            "$VENV_DIR/bin/python" -c "import torch; print(f'PyTorch CUDA Available: {torch.cuda.is_available()}')" 2>/dev/null || {
                echo "  ⚠️  PyTorch CUDA check failed (may not be installed)"
            }
        fi
    fi
    echo ""
fi

# Check for virtual environment
if [ -d "venv" ]; then
    VENV_DIR="venv"
elif [ -d ".venv" ]; then
    VENV_DIR=".venv"
else
    echo "⚠️  Warning: Virtual environment not found."
    echo "   Expected: venv/ or .venv/"
    echo "   Continuing with system Python..."
    VENV_DIR=""
fi

# Activate virtual environment if present
if [ -n "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
    echo "Activating virtual environment: $VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    echo ""
fi

# Check for .env file
if [ ! -f ".env" ]; then
    echo "⚠️  WARNING: .env file not found!"
    if [ -f "env.example" ]; then
        echo "Creating .env from env.example..."
        cp env.example .env
        echo ""
        echo "Please edit .env and add your GEMINI_API_KEY:"
        echo "  nano .env"
        echo ""
        read -p "Press Enter after you've set GEMINI_API_KEY to continue, or Ctrl+C to exit..."
    else
        echo "ERROR: env.example not found!"
        exit 1
    fi
fi

# Verify API key is set
if grep -q "your_gemini_api_key_here" .env 2>/dev/null || ! grep -q "GEMINI_API_KEY=" .env 2>/dev/null; then
    echo ""
    echo "⚠️  WARNING: GEMINI_API_KEY may not be set in .env file!"
    echo "   Please verify your .env file contains:"
    echo "   GEMINI_API_KEY=your_actual_api_key"
    echo ""
    read -p "Press Enter to continue anyway, or Ctrl+C to exit..."
fi

# Source environment variables
if [ -f ".env" ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

# Create necessary directories
mkdir -p logs models debug_audio ssl

# Check if models exist
echo ""
echo "Checking models..."
if [ ! -f "models/silero_vad.onnx" ]; then
    echo "  ⚠️  Silero VAD model not found. Downloading..."
    cd models
    wget -q --show-progress https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx || {
        echo "  ❌ Failed to download Silero VAD model"
        exit 1
    }
    cd ..
fi
echo "  ✓ Models ready!"
echo ""

# Check SSL certificates
SSL_AVAILABLE=false
if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
    SSL_AVAILABLE=true
    echo "🔒 SSL certificates found - HTTPS will be enabled"
    echo ""
else
    echo "⚠️  SSL certificates not found - HTTP will be used"
    echo "   To enable HTTPS, run: ./setup_ssl.sh"
    echo ""
fi

# Stop existing server if running
if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        echo "Stopping existing server (PID $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 2
        # Force kill if still running
        if kill -0 "$PID" 2>/dev/null; then
            kill -9 "$PID" 2>/dev/null || true
        fi
    fi
    rm -f "$PIDFILE"
fi

# Check if port is already in use
if command -v lsof &> /dev/null; then
    if lsof -ti:$PORT > /dev/null 2>&1; then
        echo "⚠️  Warning: Port $PORT is already in use!"
        echo "   Attempting to free the port..."
        lsof -ti:$PORT | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
fi

# Start the server
echo "==================================="
echo "Starting V2VBot server..."
echo "==================================="
echo ""

if [ "$SSL_AVAILABLE" = true ]; then
    PROTOCOL="https"
    SSL_ARGS="--ssl-keyfile $SSL_KEY --ssl-certfile $SSL_CERT"
    echo "🔒 Server starting with HTTPS..."
else
    PROTOCOL="http"
    SSL_ARGS=""
    echo "Server starting with HTTP..."
fi

# Get public IP for display
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "your-server-ip")

echo ""
echo "Server will be available at:"
echo "  Local:  $PROTOCOL://localhost:$PORT"
echo "  Public: $PROTOCOL://$PUBLIC_IP:$PORT"
echo ""

if [ "$SSL_AVAILABLE" = true ] && [ ! -f "/etc/letsencrypt/live"/*/fullchain.pem ] 2>/dev/null; then
    echo "⚠️  Note: Using self-signed certificate."
    echo "   Your browser will show a security warning."
    echo "   Click 'Advanced' → 'Proceed to site' to continue."
    echo ""
fi

echo "Press Ctrl+C to stop the server"
echo ""

# Start uvicorn
if [ -n "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/uvicorn" ]; then
    uvicorn "$APP" --host "$HOST" --port "$PORT" $SSL_ARGS --reload &
else
    python3 -m uvicorn "$APP" --host "$HOST" --port "$PORT" $SSL_ARGS --reload &
fi

NEWPID=$!
echo $NEWPID > "$PIDFILE"

echo "✅ Server started (PID: $NEWPID)"
echo ""

# Wait for server to be ready
sleep 2

# Check if server is still running
if ! kill -0 "$NEWPID" 2>/dev/null; then
    echo "❌ Server failed to start. Check logs for errors:"
    echo "   tail -f logs/server.log"
    exit 1
fi

echo "Server is running. View logs with:"
echo "   tail -f logs/server.log"
echo ""

# Keep script running and show logs
tail -f logs/server.log 2>/dev/null || {
    echo "Waiting for server..."
    wait $NEWPID
}
