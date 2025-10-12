# RunPod Deployment Steps (Copy & Paste)

Follow these steps after SSH-ing into your RunPod server.

## 🚀 Quick Deploy (Copy and paste these commands)

### 1. SSH into Your Server

```bash
ssh -o PubkeyAcceptedKeyTypes=+ssh-rsa shz4o4nrxlt3lw-64411557@ssh.runpod.io -i ~/.ssh/KeyPair-Sekhar_opensshKey
```

---

### 2. Clone Repository

```bash
cd /workspace
git clone https://github.com/<your-username>/V2VBot.git V2VBot
cd V2VBot
```

**Note:** Replace `<your-username>` with your actual GitHub username/URL

---

### 3. Run Automated Setup

```bash
bash setup_server.sh
```

This will:
- Install all system dependencies
- Create Python virtual environment
- Install Python packages with GPU support
- Download models
- Create systemd service

**Follow the prompts!** It will ask you to edit the `.env` file to add your API key.

---

### 4. If Setup Script Worked - Start Server

```bash
# Option A: Start as service (recommended)
sudo systemctl start v2vbot
sudo systemctl enable v2vbot
sudo systemctl status v2vbot

# Option B: Or run manually
source venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

---

### 5. Check Logs

```bash
# If using systemd service
sudo journalctl -u v2vbot -f

# Or check log file
tail -f logs/server.log
```

---

### 6. Verify GPU is Working

Look for these lines in the logs:
```
✓ Auto-detected device: cuda
✓ GPU detected: NVIDIA RTX 2000 Ada Generation (8.00 GB)
✓ Whisper model ready on cuda
✓ Using CUDA for Silero VAD
✓ [TTS] MeloTTS model loaded on cuda
```

---

## 🔧 Manual Setup (If Script Fails)

If the automated script doesn't work, follow these manual steps:

### Step 1: Install System Dependencies

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv python3-dev build-essential git wget curl ffmpeg libsndfile1 libsndfile1-dev libopus0 libopus-dev portaudio19-dev libportaudio2 pkg-config
```

### Step 2: Setup Python Environment

```bash
cd /workspace
git clone https://github.com/<your-username>/V2VBot.git V2VBot
cd V2VBot

python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r server/requirements.txt
```

### Step 3: Configure Environment

```bash
cp env.example .env
nano .env
```

Add your API key:
```
GEMINI_API_KEY=your_actual_api_key_here
```

Save: Ctrl+O, Enter, Ctrl+X

### Step 4: Create Directories and Download Models

```bash
mkdir -p logs models debug_audio
cd models
wget https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
cd ..
```

### Step 5: Run Server

```bash
source venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

---

## 📱 Access Your Application

1. Go to your RunPod dashboard
2. Find your pod
3. Click "Connect" button
4. Look for "HTTP Service [Port 8080]"
5. Click the link (format: `https://xxxxx-8080.proxy.runpod.net`)

---

## 🛠️ Useful Commands

```bash
# Check GPU
nvidia-smi

# Check if Python sees GPU
python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}')"

# View logs
tail -f /workspace/V2VBot/logs/server.log

# Restart service
sudo systemctl restart v2vbot

# Stop service
sudo systemctl stop v2vbot

# Check service status
sudo systemctl status v2vbot

# Check what's running on port 8080
sudo netstat -tulpn | grep 8080
```

---

## 🐛 Troubleshooting

### Problem: API Key Error

**Solution:**
```bash
cd /workspace/V2VBot
nano .env
# Make sure GEMINI_API_KEY is set correctly
```

### Problem: Port 8080 Already in Use

**Solution:**
```bash
# Find what's using the port
sudo lsof -i :8080

# Kill the process
sudo kill -9 <PID>

# Or use different port
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8081
```

### Problem: GPU Not Working

**Solution:**
```bash
# Check NVIDIA driver
nvidia-smi

# Reinstall PyTorch with CUDA
source /workspace/V2VBot/venv/bin/activate
pip uninstall torch torchaudio -y
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121
```

### Problem: Out of Memory

**Solution:**
Edit the Whisper model size:
```bash
nano /workspace/V2VBot/server/app/audio/pipeline.py
# Change line ~18 from "small.en" to "tiny.en"
```

---

## 📊 Expected Performance

With RTX 2000 Ada, you should see:
- **Transcription**: 0.5-1 second
- **LLM Response**: 0.5-2 seconds (depends on Gemini)
- **TTS**: 0.5-1 second per sentence
- **Total Round-Trip**: 2-4 seconds

---

## 💾 Keep Running After Disconnect

If you want the server to keep running after you close SSH:

**Option 1: Use systemd service (recommended)**
```bash
sudo systemctl start v2vbot
sudo systemctl enable v2vbot
```

**Option 2: Use screen**
```bash
screen -S v2vbot
source venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
# Press Ctrl+A then D to detach
# To reattach: screen -r v2vbot
```

**Option 3: Use nohup**
```bash
nohup python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 > logs/server.log 2>&1 &
```

---

## ✅ Verification Checklist

After deployment, verify:

- [ ] GPU is detected: `nvidia-smi` shows RTX 2000 Ada
- [ ] Python sees GPU: `python -c "import torch; print(torch.cuda.is_available())"` returns `True`
- [ ] Server is running: `curl http://localhost:8080` returns HTML
- [ ] Logs show GPU: `tail logs/server.log` shows "cuda" messages
- [ ] Can access from browser using RunPod URL

---

## 🎉 Success!

If everything is working:
1. Your server is running at `https://xxxxx-8080.proxy.runpod.net`
2. GPU acceleration is enabled (3-5x faster)
3. Logs show no errors
4. You can access the web interface

**Enjoy your GPU-accelerated V2VBot!** 🚀

