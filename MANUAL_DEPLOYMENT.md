# Manual Deployment Guide (Non-Docker)

This guide walks you through deploying V2VBot directly on a RunPod server without Docker.

## Quick Start

### Step 1: SSH into Your Server

```bash
ssh -o PubkeyAcceptedKeyTypes=+ssh-rsa shz4o4nrxlt3lw-64411557@ssh.runpod.io -i ~/.ssh/KeyPair-Sekhar_opensshKey
```

### Step 2: Clone Repository

```bash
cd /workspace
git clone <your-github-repo-url> V2VBot
cd V2VBot
```

### Step 3: Run Setup Script

```bash
bash setup_server.sh
```

The script will:
- ✓ Check GPU availability
- ✓ Install system dependencies
- ✓ Create Python virtual environment
- ✓ Install Python packages
- ✓ Download required models
- ✓ Set up systemd service
- ✓ Configure environment

### Step 4: Configure API Key

Edit the `.env` file and add your Gemini API key:

```bash
nano .env
```

Add:
```
GEMINI_API_KEY=your_actual_api_key_here
```

Save (Ctrl+O, Enter, Ctrl+X)

### Step 5: Start Server

**Option A: Run Manually (Recommended for testing)**
```bash
source venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

**Option B: Run as System Service (Recommended for production)**
```bash
sudo systemctl start v2vbot
sudo systemctl enable v2vbot  # Auto-start on boot
```

### Step 6: Access Your Application

Find your RunPod URL in the dashboard:
- Go to your pod in RunPod dashboard
- Click "Connect" → "HTTP Service [Port 8080]"
- Use the provided URL: `https://xxxxx-8080.proxy.runpod.net`

---

## Detailed Manual Setup (If Script Fails)

### 1. Update System and Install Dependencies

```bash
# Update package lists
sudo apt-get update

# Install system dependencies
sudo apt-get install -y \
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
    pkg-config
```

### 2. Verify GPU

```bash
nvidia-smi
```

You should see your RTX 2000 Ada GPU.

### 3. Setup Application

```bash
# Create workspace directory
mkdir -p /workspace
cd /workspace

# Clone repository
git clone <your-repo-url> V2VBot
cd V2VBot

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install dependencies
pip install -r server/requirements.txt
```

### 4. Verify GPU Support

```bash
# Check PyTorch CUDA
python -c "import torch; print(f'CUDA Available: {torch.cuda.is_available()}')"
python -c "import torch; print(f'GPU: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"None\"}')"

# Check ONNX Runtime
python -c "import onnxruntime as ort; print(f'Providers: {ort.get_available_providers()}')"
```

Expected output:
```
CUDA Available: True
GPU: NVIDIA RTX 2000 Ada Generation
Providers: ['CUDAExecutionProvider', 'CPUExecutionProvider']
```

### 5. Configure Environment

```bash
# Copy environment template
cp env.example .env

# Edit and add your API key
nano .env
```

Set:
```bash
GEMINI_API_KEY=your_actual_gemini_api_key_here
USE_GPU=true
CUDA_VISIBLE_DEVICES=0
```

### 6. Create Directories

```bash
mkdir -p logs models debug_audio
```

### 7. Download Models

```bash
# Download Silero VAD model
cd models
wget https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
cd ..
```

Note: Whisper models will be downloaded automatically on first run.

### 8. Run Server

**For Testing (Manual Start):**
```bash
source venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

Press Ctrl+C to stop.

**For Production (Systemd Service):**

Create service file:
```bash
sudo nano /etc/systemd/system/v2vbot.service
```

Add:
```ini
[Unit]
Description=V2VBot Voice-to-Voice AI Service
After=network.target

[Service]
Type=simple
User=<your-username>
WorkingDirectory=/workspace/V2VBot
Environment="PATH=/workspace/V2VBot/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/workspace/V2VBot/venv/bin/python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1
Restart=always
RestartSec=10
StandardOutput=append:/workspace/V2VBot/logs/server.log
StandardError=append:/workspace/V2VBot/logs/server.log

[Install]
WantedBy=multi-user.target
```

Replace `<your-username>` with your actual username (usually `root` on RunPod).

Start service:
```bash
sudo systemctl daemon-reload
sudo systemctl start v2vbot
sudo systemctl enable v2vbot
sudo systemctl status v2vbot
```

---

## Service Management

### Start/Stop/Restart

```bash
# Start
sudo systemctl start v2vbot

# Stop
sudo systemctl stop v2vbot

# Restart
sudo systemctl restart v2vbot

# Status
sudo systemctl status v2vbot

# View logs
sudo journalctl -u v2vbot -f
```

### Or use logs file directly

```bash
tail -f /workspace/V2VBot/logs/server.log
```

---

## Monitoring

### Check GPU Usage

```bash
# One-time check
nvidia-smi

# Monitor continuously
nvidia-smi -l 1

# Detailed monitoring
watch -n 1 nvidia-smi
```

### Check Application Logs

```bash
# Application logs
tail -f /workspace/V2VBot/logs/server.log

# System service logs
sudo journalctl -u v2vbot -f

# Last 100 lines
sudo journalctl -u v2vbot -n 100
```

### Check Server Status

```bash
# Check if running
ps aux | grep uvicorn

# Check port
sudo netstat -tulpn | grep 8080

# Test locally
curl http://localhost:8080
```

---

## Troubleshooting

### GPU Not Detected

```bash
# Check NVIDIA driver
nvidia-smi

# Check CUDA in Python
python -c "import torch; print(torch.cuda.is_available())"

# Reinstall PyTorch with CUDA
pip uninstall torch torchaudio
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121
```

### Service Won't Start

```bash
# Check logs
sudo journalctl -u v2vbot -n 50

# Check syntax
source /workspace/V2VBot/venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

### Port Already in Use

```bash
# Find process using port 8080
sudo lsof -i :8080

# Kill process
sudo kill -9 <PID>

# Or use different port
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8081
```

### Out of Memory

```bash
# Check GPU memory
nvidia-smi

# Use smaller Whisper model
# Edit: server/app/audio/pipeline.py
# Change: model_size="small.en" to model_size="tiny.en"
```

### API Key Issues

```bash
# Check if set
cat .env | grep GEMINI_API_KEY

# Test API key
python << 'EOF'
from dotenv import load_dotenv
import os
load_dotenv()
key = os.getenv("GEMINI_API_KEY")
print(f"API Key set: {bool(key and key != 'your_gemini_api_key_here')}")
EOF
```

---

## Performance Tuning

### For RTX 2000 Ada (8GB VRAM)

Current settings in code are optimized:
- Whisper: `small.en` model with `float16`
- MeloTTS: CUDA enabled
- Silero VAD: CUDA enabled

### If You Need More VRAM

Use smaller models:
```python
# Edit: server/app/audio/pipeline.py
# Line ~18: Change to tiny model
model_size="tiny.en"  # Instead of "small.en"
```

### If You Have More VRAM

Use larger models:
```python
# Edit: server/app/audio/pipeline.py
# Line ~18: Change to medium model
model_size="medium.en"  # Instead of "small.en"
```

---

## Security

### Firewall (Optional)

```bash
# Allow port 8080
sudo ufw allow 8080/tcp

# Enable firewall
sudo ufw enable
```

### HTTPS (Production)

For production, use a reverse proxy with SSL:

```bash
# Install nginx
sudo apt-get install -y nginx certbot python3-certbot-nginx

# Configure nginx (example)
sudo nano /etc/nginx/sites-available/v2vbot
```

---

## Updating Application

```bash
cd /workspace/V2VBot

# Pull latest changes
git pull

# Activate venv
source venv/bin/activate

# Update dependencies
pip install -r server/requirements.txt --upgrade

# Restart service
sudo systemctl restart v2vbot
```

---

## Backup

### Important Files to Backup

- `.env` - Your configuration
- `logs/` - Application logs (optional)
- `models/` - Downloaded models (optional, can re-download)

### Backup Command

```bash
tar -czf v2vbot-backup-$(date +%Y%m%d).tar.gz .env logs/
```

---

## Complete Command Reference

```bash
# Setup (one-time)
git clone <repo> /workspace/V2VBot
cd /workspace/V2VBot
bash setup_server.sh

# Start server
sudo systemctl start v2vbot

# Stop server
sudo systemctl stop v2vbot

# View logs
tail -f logs/server.log

# Check GPU
nvidia-smi

# Update code
git pull && pip install -r server/requirements.txt -U && sudo systemctl restart v2vbot
```

---

## Getting Help

1. Check logs: `tail -f logs/server.log`
2. Check GPU: `nvidia-smi`
3. Check service: `sudo systemctl status v2vbot`
4. See documentation: `docs/gpu-deployment.md`

