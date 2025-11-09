# GPU Deployment Guide for V2VBot

This guide covers deploying V2VBot on GPU-enabled infrastructure, specifically optimized for RunPod with RTX 2000 Ada or similar GPUs.

## Overview

V2VBot supports GPU acceleration for compute-intensive components:
- **Faster-Whisper STT**: CUDA acceleration with float16 precision
- **Silero VAD**: ONNX Runtime with CUDA execution provider
- **TTS**: HTTP-based service (remote, no local GPU needed)

## System Requirements

### Minimum Requirements
- **GPU**: NVIDIA GPU with CUDA Compute Capability 7.0+ (e.g., RTX 2000 Ada, T4, RTX 3060, etc.)
- **GPU Memory**: 4GB+ VRAM
- **RAM**: 8GB+ system RAM
- **CPU**: 4+ cores
- **Storage**: 10GB+ for models and application

### Recommended Requirements (RunPod RTX 2000 Ada)
- **GPU**: RTX 2000 Ada (1x)
- **GPU Memory**: 8GB VRAM
- **vCPU**: 6 cores
- **RAM**: 16GB
- **Storage**: 20GB SSD

## GPU Configuration

### Automatic GPU Detection

V2VBot automatically detects and uses available GPUs. No manual configuration needed!

```python
# Models automatically detect CUDA
# - Whisper: Uses float16 on GPU, int8 on CPU
# - Silero VAD: Uses CUDAExecutionProvider if available
# - TTS: HTTP-based service (remote, no local GPU needed)
```

### Manual GPU Control

If you need to control GPU usage, set these environment variables:

```bash
# Enable/disable GPU
USE_GPU=true

# Select specific GPU (for multi-GPU systems)
CUDA_VISIBLE_DEVICES=0

# Disable GPU completely
CUDA_VISIBLE_DEVICES=-1
```

## Deployment Methods

### Method 1: RunPod Deployment (Recommended)

#### Step 1: Create RunPod Pod

1. Go to [RunPod.io](https://www.runpod.io)
2. Create a new pod with:
   - **GPU**: RTX 2000 Ada (or similar)
   - **Template**: PyTorch 2.1+ with CUDA 12.1
   - **Disk**: 20GB+ persistent storage
   - **Ports**: Expose port 8080

#### Step 2: Deploy Application

SSH into your RunPod instance:

```bash
# Clone repository
git clone <your-repo-url> /workspace/V2VBot
cd /workspace/V2VBot

# Create environment file
cp env.example .env
nano .env  # Add your GEMINI_API_KEY

# Install dependencies
pip install -r server/requirements.txt

# Run application
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

#### Step 3: Access Application

Access via RunPod's provided URL (e.g., `https://xxxxx-8080.proxy.runpod.net`)

### Method 2: Docker Deployment

#### Build and Run with Docker

```bash
# Build image
docker build -t v2vbot:latest .

# Run with GPU support
docker run --gpus all \
  -p 8080:8080 \
  -v $(pwd)/models:/app/models \
  -v $(pwd)/logs:/app/logs \
  -e GEMINI_API_KEY=your_api_key_here \
  v2vbot:latest
```

#### Using Docker Compose

```bash
# Set API key in .env file
echo "GEMINI_API_KEY=your_key_here" > .env

# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### Method 3: Manual Installation on GPU Server

```bash
# Install CUDA 12.1+ and cuDNN
# Follow NVIDIA's official installation guide

# Clone repository
git clone <your-repo-url> V2VBot
cd V2VBot

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r server/requirements.txt

# Configure environment
cp env.example .env
nano .env  # Set GEMINI_API_KEY and other settings

# Run application
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

## Performance Expectations

### GPU vs CPU Performance

| Component | CPU (int8) | GPU (float16) | Speedup |
|-----------|------------|---------------|---------|
| Whisper STT | 1.3-1.4 sec | 0.2-0.4 sec | 5-7x |
| TTS (HTTP) | 1.4-4.0 sec/sentence | N/A (remote service) | N/A |
| Silero VAD | ~20ms | ~10ms | 2x |

### Expected Latency on RTX 2000 Ada

- **Speech Detection**: <10ms
- **Transcription**: 0.2-0.4 second (GPU) or 1.3-1.4 second (CPU)
- **LLM Response**: 0.7-1.0 second TTFB (depends on Gemini API)
- **TTS Synthesis**: 1.4-4.0 seconds per sentence (HTTP service, includes network latency)
- **Total Round-Trip**: ~2.5-5.5 seconds (GPU) or ~3.5-6.5 seconds (CPU)

## Troubleshooting

### GPU Not Detected

```bash
# Check CUDA availability
python -c "import torch; print(f'CUDA Available: {torch.cuda.is_available()}')"
python -c "import torch; print(f'GPU: {torch.cuda.get_device_name(0)}')"

# Check ONNX Runtime providers
python -c "import onnxruntime as ort; print(ort.get_available_providers())"
```

Expected output:
```
CUDA Available: True
GPU: NVIDIA RTX 2000 Ada Generation
['CUDAExecutionProvider', 'CPUExecutionProvider']
```

### Out of Memory Errors

If you encounter CUDA OOM errors:

1. **Reduce model sizes**:
   ```bash
   # Use smaller Whisper model
   # Edit server/app/audio/pipeline.py
   # Change: model_size="small.en" to model_size="tiny.en"
   ```

2. **Monitor GPU memory**:
   ```bash
   nvidia-smi -l 1  # Monitor GPU usage
   ```

3. **Fallback to CPU**: Set `USE_GPU=false` in `.env`

### Slow Performance

1. **Check GPU utilization**:
   ```bash
   nvidia-smi
   # Look for GPU usage % and memory usage
   ```

2. **Verify CUDA version**:
   ```bash
   nvcc --version
   python -c "import torch; print(f'PyTorch CUDA: {torch.version.cuda}')"
   ```

3. **Check model loading**:
   Look for these messages in logs:
   ```
   Auto-detected device: cuda
   GPU detected: NVIDIA RTX 2000 Ada Generation (8.00 GB)
   ✓ Whisper model ready on cuda
   Using CUDA for Silero VAD
   [TTS] HTTP TTS service initialized
   ```

## Environment Variables Reference

See `env.example` for complete list:

```bash
# GPU Configuration
USE_GPU=true
CUDA_VISIBLE_DEVICES=0

# API Keys
GEMINI_API_KEY=your_key_here

# Model Configuration
GEMINI_MODEL=gemini-2.0-flash

# VAD Settings
VAD_THRESHOLD=0.5
VAD_END_MS=1500
VAD_TURN_END_MS=2000
```

## Security Considerations

1. **API Keys**: Never commit `.env` file to git
2. **Firewall**: Use HTTPS in production, restrict port access
3. **CORS**: Configure proper CORS settings for your domain
4. **Rate Limiting**: Implement rate limiting for production use

## Cost Optimization

### RunPod Cost Estimation

RTX 2000 Ada on RunPod:
- **On-Demand**: ~$0.30-0.50/hour
- **Spot**: ~$0.15-0.25/hour (can be terminated)

**Tips**:
1. Use spot instances for development
2. Stop pod when not in use
3. Use persistent storage to avoid re-downloading models

### Model Storage

Models are cached in `/app/models`:
- **Silero VAD**: ~2MB (included)
- **Whisper small.en**: ~466MB (auto-downloaded)
- **TTS**: HTTP-based service (no local models needed)
- **Total**: ~468MB

Use persistent volumes to avoid re-downloading.

## Monitoring and Logs

### Application Logs

```bash
# View live logs
tail -f logs/server.log

# Check GPU initialization
grep -i "gpu\|cuda" logs/server.log
```

### GPU Monitoring

```bash
# Real-time GPU stats
nvidia-smi -l 1

# Detailed GPU info
nvidia-smi --query-gpu=timestamp,name,temperature.gpu,utilization.gpu,utilization.memory,memory.total,memory.used --format=csv -l 1
```

## Next Steps

1. ✅ Deploy to RunPod or GPU server
2. ✅ Test GPU acceleration
3. ✅ Monitor performance and costs
4. Consider implementing:
   - Metrics and observability
   - Auto-scaling
   - Load balancing for multiple instances
   - Model optimization (quantization, pruning)

## Support

For issues or questions:
1. Check logs in `logs/server.log`
2. Verify GPU setup with troubleshooting commands
3. Review documentation in `docs/` folder
4. Check current status in `docs/current-status.md`

