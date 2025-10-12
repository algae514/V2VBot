# V2VBot - RunPod Deployment Quick Start

This is a quick reference for deploying V2VBot to RunPod with GPU support.

## Prerequisites

1. RunPod account: [https://www.runpod.io](https://www.runpod.io)
2. Google Gemini API key: [https://makersuite.google.com/app/apikey](https://makersuite.google.com/app/apikey)

## Deployment Steps

### 1. Create RunPod Pod

Create a new pod with these specifications:

**GPU Configuration:**
- **GPU Type**: RTX 2000 Ada (1x) or similar (T4, RTX 3060, etc.)
- **vCPU**: 6 cores (minimum 4)
- **RAM**: 16GB (minimum 8GB)
- **Disk**: 20GB persistent storage

**Template:**
- Select: **PyTorch 2.1+** with **CUDA 12.1**
- Or: **RunPod PyTorch** base image

**Networking:**
- Expose port: **8080**
- Enable: **HTTP Service**

### 2. Connect to Pod

Once pod is running, click **Connect** and choose **SSH** or **Web Terminal**.

### 3. Deploy Application

```bash
# Clone repository
cd /workspace
git clone <your-repo-url> V2VBot
cd V2VBot

# Set up environment
cp env.example .env
nano .env  # Add your GEMINI_API_KEY (required!)

# Run setup and start script
bash start_runpod.sh
```

The script will:
- ✓ Check GPU availability
- ✓ Download required models
- ✓ Verify CUDA setup
- ✓ Start the server on port 8080

### 4. Access Application

Your application will be available at the RunPod-provided URL:
```
https://xxxxx-8080.proxy.runpod.net
```

You can find this URL in your pod's **Connect** menu under **HTTP Service**.

## Alternative: Docker Deployment

```bash
# Build image
docker build -t v2vbot:latest .

# Run with GPU
docker run --gpus all \
  -p 8080:8080 \
  -e GEMINI_API_KEY=your_key_here \
  v2vbot:latest
```

## Quick Verification

After starting, check the logs for:

```
✓ GPU detected: NVIDIA RTX 2000 Ada Generation (8.00 GB)
✓ Whisper model ready on cuda
✓ Using CUDA for Silero VAD
✓ [TTS] MeloTTS model loaded on cuda
```

## Environment Configuration

Edit `.env` to configure:

```bash
# Required
GEMINI_API_KEY=your_api_key_here

# Optional
USE_GPU=true                    # Enable GPU (default: auto-detect)
GEMINI_MODEL=gemini-2.0-flash   # LLM model
VAD_END_MS=1500                 # Utterance end pause (ms)
VAD_TURN_END_MS=2000           # Turn end pause (ms)
```

## Troubleshooting

### GPU Not Working?

```bash
# Check CUDA
nvidia-smi
python3 -c "import torch; print(torch.cuda.is_available())"

# Check logs
tail -f logs/server.log
```

### Out of Memory?

Use smaller Whisper model:
- Edit: `server/app/audio/pipeline.py`
- Change: `model_size="small.en"` → `model_size="tiny.en"`

### API Key Issues?

```bash
# Verify API key is set
cat .env | grep GEMINI_API_KEY
```

## Cost Management

**RunPod Pricing** (approximate):
- RTX 2000 Ada: $0.30-0.50/hour (on-demand)
- RTX 2000 Ada: $0.15-0.25/hour (spot)

**Tips:**
1. Use **spot instances** for development
2. **Stop pod** when not in use
3. Use **persistent storage** to keep models

## Performance

Expected latency with RTX 2000 Ada:
- **Speech Detection**: <10ms
- **Transcription**: 0.5-1 second
- **LLM Response**: 0.5-2 seconds
- **TTS Synthesis**: 0.5-1 second/sentence
- **Total Round-Trip**: 2-4 seconds

## Full Documentation

For detailed information, see:
- **GPU Deployment Guide**: `docs/gpu-deployment.md`
- **Architecture**: `docs/architecture-rules.md`
- **Current Status**: `docs/current-status.md`
- **Requirements**: `docs/requirements.md`

## Support

Having issues? Check:
1. Application logs: `tail -f logs/server.log`
2. GPU status: `nvidia-smi`
3. Documentation: `docs/gpu-deployment.md`

