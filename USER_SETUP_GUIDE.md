# RunPod User Creation and Setup Guide

## The Problem
RunPod servers typically run as `root` by default, but the V2VBot setup script requires a regular user for security reasons.

## Solution: Create User and Setup

I've created a script that handles both user creation and application setup.

## 🚀 Quick Setup (Copy & Paste)

### Step 1: SSH into RunPod as Root
```bash
ssh -o PubkeyAcceptedKeyTypes=+ssh-rsa shz4o4nrxlt3lw-64411557@ssh.runpod.io -i ~/.ssh/KeyPair-Sekhar_opensshKey
```

### Step 2: Clone Repository
```bash
cd /workspace
git clone <your-github-repo-url> V2VBot
cd V2VBot
```

### Step 3: Run User Creation Script
```bash
sudo bash create_user_and_setup.sh
```

This script will:
- ✅ Create user `v2vbot` with sudo privileges
- ✅ Install all system dependencies
- ✅ Set up Python environment
- ✅ Install GPU-accelerated packages
- ✅ Download models
- ✅ Create systemd service
- ✅ Prompt you to add API key

### Step 4: Add API Key
The script will prompt you to edit `.env` file. Add your Gemini API key:
```
GEMINI_API_KEY=your_actual_api_key_here
```

### Step 5: Start Server
```bash
# Option A: As system service (recommended)
sudo systemctl start v2vbot
sudo systemctl enable v2vbot

# Option B: Switch to user and run manually
su - v2vbot
cd /workspace/V2VBot
source venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

---

## 🔧 Manual User Creation (If Script Fails)

### Create User Manually
```bash
# Create user with home directory
sudo useradd -m -s /bin/bash v2vbot

# Add to sudo group
sudo usermod -aG sudo v2vbot

# Add to docker group (if docker installed)
sudo usermod -aG docker v2vbot

# Set up workspace permissions
sudo mkdir -p /workspace
sudo chown v2vbot:v2vbot /workspace
```

### Install Dependencies as Root
```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv python3-dev build-essential git wget curl ffmpeg libsndfile1 libsndfile1-dev libopus0 libopus-dev portaudio19-dev libportaudio2 pkg-config sudo
```

### Setup Application as User
```bash
# Switch to the new user
su - v2vbot

# Clone repository
cd /workspace
git clone <your-repo-url> V2VBot
cd V2VBot

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install packages
pip install --upgrade pip setuptools wheel
pip install -r server/requirements.txt

# Configure environment
cp env.example .env
nano .env  # Add GEMINI_API_KEY

# Create directories and download models
mkdir -p logs models debug_audio
cd models
wget https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
cd ..

# Create systemd service
sudo tee /etc/systemd/system/v2vbot.service > /dev/null << EOF
[Unit]
Description=V2VBot Voice-to-Voice AI Service
After=network.target

[Service]
Type=simple
User=v2vbot
WorkingDirectory=/workspace/V2VBot
Environment="PATH=/workspace/V2VBot/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/workspace/V2VBot/venv/bin/python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1
Restart=always
RestartSec=10
StandardOutput=append:/workspace/V2VBot/logs/server.log
StandardError=append:/workspace/V2VBot/logs/server.log

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl start v2vbot
sudo systemctl enable v2vbot
```

---

## 👤 User Management Commands

### Switch to User
```bash
su - v2vbot
```

### Run Commands as User
```bash
sudo -u v2vbot <command>
```

### Check User Info
```bash
id v2vbot
groups v2vbot
```

### Change User Password (Optional)
```bash
sudo passwd v2vbot
```

---

## 🔍 Verification

### Check User Created
```bash
id v2vbot
# Should show: uid=1001(v2vbot) gid=1001(v2vbot) groups=1001(v2vbot),27(sudo)
```

### Check Application Setup
```bash
sudo -u v2vbot ls -la /workspace/V2VBot/
# Should show: venv/, server/, web/, models/, logs/, .env
```

### Check Service Status
```bash
sudo systemctl status v2vbot
```

### Check GPU Detection
```bash
sudo -u v2vbot bash -c "cd /workspace/V2VBot && source venv/bin/activate && python -c 'import torch; print(f\"CUDA: {torch.cuda.is_available()}\")'"
```

---

## 🛠️ Service Management

### Start/Stop/Restart Service
```bash
sudo systemctl start v2vbot
sudo systemctl stop v2vbot
sudo systemctl restart v2vbot
sudo systemctl status v2vbot
```

### View Logs
```bash
# Service logs
sudo journalctl -u v2vbot -f

# Application logs
tail -f /workspace/V2VBot/logs/server.log
```

### Enable/Disable Auto-start
```bash
sudo systemctl enable v2vbot   # Auto-start on boot
sudo systemctl disable v2vbot  # Don't auto-start
```

---

## 🐛 Troubleshooting

### Problem: Permission Denied
**Solution:**
```bash
# Check ownership
ls -la /workspace/V2VBot/

# Fix ownership if needed
sudo chown -R v2vbot:v2vbot /workspace/V2VBot/
```

### Problem: Service Won't Start
**Solution:**
```bash
# Check service logs
sudo journalctl -u v2vbot -n 50

# Check if user can run the command manually
sudo -u v2vbot bash -c "cd /workspace/V2VBot && source venv/bin/activate && python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080"
```

### Problem: GPU Not Detected
**Solution:**
```bash
# Check as user
sudo -u v2vbot nvidia-smi

# Check Python GPU support
sudo -u v2vbot bash -c "cd /workspace/V2VBot && source venv/bin/activate && python -c 'import torch; print(torch.cuda.is_available())'"
```

### Problem: Port Already in Use
**Solution:**
```bash
# Find what's using port 8080
sudo lsof -i :8080

# Kill the process
sudo kill -9 <PID>

# Or change port in service file
sudo nano /etc/systemd/system/v2vbot.service
# Change --port 8080 to --port 8081
sudo systemctl daemon-reload
sudo systemctl restart v2vbot
```

---

## 📱 Access Application

1. Go to RunPod dashboard
2. Find your pod
3. Click "Connect" → "HTTP Service [Port 8080]"
4. Use URL: `https://xxxxx-8080.proxy.runpod.net`

---

## ✅ Success Checklist

- [ ] User `v2vbot` created with sudo privileges
- [ ] Application cloned to `/workspace/V2VBot`
- [ ] Python virtual environment created
- [ ] GPU packages installed
- [ ] API key configured in `.env`
- [ ] Models downloaded
- [ ] Systemd service created
- [ ] Service running: `sudo systemctl status v2vbot`
- [ ] GPU detected in logs
- [ ] Application accessible via RunPod URL

---

## 🎯 Quick Commands Summary

```bash
# Create user and setup (run as root)
sudo bash create_user_and_setup.sh

# Start service
sudo systemctl start v2vbot

# Check status
sudo systemctl status v2vbot

# View logs
tail -f /workspace/V2VBot/logs/server.log

# Switch to user
su - v2vbot

# Run as user
sudo -u v2vbot <command>
```

---

## 💡 Why Create a User?

1. **Security**: Running as root is a security risk
2. **File Permissions**: Proper ownership of application files
3. **Service Management**: Systemd services work better with dedicated users
4. **Best Practices**: Production applications should run as non-root users

The `create_user_and_setup.sh` script handles all of this automatically! 🚀

