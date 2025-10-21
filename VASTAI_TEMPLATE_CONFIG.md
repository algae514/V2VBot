# VastAI Template Configuration for V2VBot

## Template Settings

**Base Image:** `docker.io/vastai/kvm:ubuntu_cli_22.04-2025-05-16`

### Docker Run Options

```bash
docker run -it --gpus all --shm-size=8g \
  -p 8080:8080 \
  -p 3478:3478 \
  -p 3478:3478/udp \
  -p 5349:5349 \
  -p 50000-50050:50000-50050/udp \
  -v /tmp:/tmp \
  --name v2vbot \
  docker.io/vastai/kvm:ubuntu_cli_22.04-2025-05-16
```

### Port Configuration

| Port | Protocol | Purpose |
|------|----------|---------|
| 8080 | TCP | Main V2VBot Web Interface |
| 3478 | TCP/UDP | TURN Server (WebRTC) |
| 5349 | TCP | TURNS Server (TLS) |
| 50000-50050 | UDP | TURN Relay Ports |

### Environment Variables

```bash
export USE_GPU=true
export CUDA_VISIBLE_DEVICES=0
export PYTHONUNBUFFERED=1
```

## Setup Instructions

1. **SSH into VastAI instance**
2. **Clone the repository:**
   ```bash
   git clone https://github.com/algae514/V2VBot.git
   cd V2VBot
   ```

3. **Run setup script:**
   ```bash
   chmod +x setup_server.sh
   ./setup_server.sh
   ```

4. **Configure environment:**
   ```bash
   cp env.example .env
   nano .env  # Add your GEMINI_API_KEY
   ```

5. **Start the server:**
   ```bash
   chmod +x start_vastai.sh
   ./start_vastai.sh
   ```

## WebRTC Requirements

- **TURN Server:** Configured for WebRTC connectivity
- **Port Forwarding:** All necessary ports exposed
- **GPU Support:** CUDA-enabled for Whisper and TTS
- **Shared Memory:** 8GB for model loading

## Troubleshooting

- **GPU Issues:** Check `nvidia-smi` output
- **Port Conflicts:** Ensure ports 8080, 3478, 5349 are available
- **Model Downloads:** Models auto-download on first run
- **WebRTC:** Check TURN server logs in `logs/` directory
