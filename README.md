# V2VBot - Voice-to-Voice AI Assistant

A real-time voice-to-voice conversational AI system with GPU acceleration, optimized for low-latency interactions.

## Features

✨ **Complete Voice-to-Voice Pipeline**
- Real-time speech detection and transcription
- Conversational AI responses with Google Gemini
- High-quality text-to-speech synthesis
- Natural barge-in support (interrupt AI when speaking)

🚀 **GPU Accelerated**
- Full CUDA support for all models
- Automatic GPU detection and fallback
- 3-5x faster inference on GPU
- Optimized for NVIDIA GPUs (RTX 2000 Ada, T4, RTX 3060+)

⚡ **Low Latency**
- 2-4 second total round-trip time
- Streaming responses for instant feedback
- WebRTC for real-time audio transport
- Optimized audio processing pipeline

🎯 **Production Ready**
- Docker deployment with GPU support
- RunPod optimized with startup scripts
- Comprehensive monitoring and logging
- Graceful error handling and fallbacks

## Quick Start

### Local Development

```bash
# Clone repository
git clone <repo-url> V2VBot
cd V2VBot

# Install dependencies
pip install -r server/requirements.txt

# Configure environment
cp env.example .env
nano .env  # Add GEMINI_API_KEY

# Run server
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080
```

### Docker Deployment

```bash
# Build and run
docker-compose up -d

# View logs
docker-compose logs -f
```

### RunPod Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed RunPod setup instructions.

Quick deploy:
```bash
cd /workspace
git clone <repo-url> V2VBot
cd V2VBot
cp env.example .env
nano .env  # Add GEMINI_API_KEY
bash start_runpod.sh
```

## System Requirements

### Minimum (CPU)
- 4+ CPU cores
- 8GB RAM
- 10GB storage

### Recommended (GPU)
- NVIDIA GPU with CUDA 12.1+ (RTX 2000 Ada, T4, RTX 3060+)
- 4GB+ VRAM
- 8GB+ RAM
- 6+ CPU cores
- 20GB storage

## Architecture

```
Browser → WebRTC → Server → Audio Pipeline → VAD → STT → LLM → TTS → Audio Response
```

**Components:**
- **VAD**: Silero VAD for speech detection
- **STT**: Faster-Whisper for transcription
- **LLM**: Google Gemini for conversation
- **TTS**: MeloTTS for speech synthesis

## Performance

### CPU (Baseline)
- Transcription: 2-5 seconds
- TTS: 2-3 seconds/sentence
- Total: 5-8 seconds

### GPU (RTX 2000 Ada)
- Transcription: 0.5-1 second (**3-5x faster**)
- TTS: 0.5-1 second/sentence (**2-3x faster**)
- Total: 2-4 seconds

## Configuration

Key environment variables (see `env.example`):

```bash
# Required
GEMINI_API_KEY=your_api_key_here

# GPU (auto-detects by default)
USE_GPU=true

# Model Selection
GEMINI_MODEL=gemini-2.0-flash

# VAD Settings
VAD_END_MS=1500        # Utterance end pause
VAD_TURN_END_MS=2000   # Turn end pause
```

## Documentation

- **[Deployment Guide](DEPLOYMENT.md)**: Quick start for RunPod
- **[GPU Deployment](docs/gpu-deployment.md)**: Comprehensive GPU setup
- **[Architecture](docs/architecture-rules.md)**: System design principles
- **[Current Status](docs/current-status.md)**: Implementation status
- **[Requirements](docs/requirements.md)**: Detailed requirements

## Project Structure

```
V2VBot/
├── server/              # Backend application
│   ├── app/
│   │   ├── audio/      # Audio processing pipeline
│   │   ├── stt/        # Speech-to-text (Whisper)
│   │   ├── tts/        # Text-to-speech (MeloTTS)
│   │   ├── llm/        # LLM integration (Gemini)
│   │   └── main.py     # FastAPI server
│   └── requirements.txt
├── web/                 # Frontend application
│   ├── public/
│   └── src/
├── models/              # Model files (cached)
├── docs/                # Documentation
├── Dockerfile           # Docker build
├── docker-compose.yml   # Docker orchestration
├── start_runpod.sh     # RunPod startup script
└── env.example          # Environment template
```

## Development

### Setup Development Environment

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r server/requirements.txt

# Run in development mode
uvicorn server.app.main:app --reload --host 0.0.0.0 --port 8080
```

### Testing GPU

```bash
# Check CUDA availability
python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}')"

# Check GPU info
nvidia-smi

# Monitor GPU usage
nvidia-smi -l 1
```

## Troubleshooting

### GPU Not Detected
```bash
# Verify CUDA installation
nvidia-smi
python -c "import torch; print(torch.cuda.is_available())"

# Check logs
tail -f logs/server.log | grep -i "gpu\|cuda"
```

### Out of Memory
- Use smaller Whisper model: Change `small.en` to `tiny.en` in `server/app/audio/pipeline.py`
- Reduce batch size or disable GPU: Set `USE_GPU=false` in `.env`

### API Key Issues
```bash
# Verify API key is set
grep GEMINI_API_KEY .env
```

## Contributing

Contributions welcome! Please:
1. Follow existing code style
2. Update documentation
3. Add tests for new features
4. Follow DRY principle (see `docs/`)

## License

[Add your license here]

## Support

- **Issues**: Check logs in `logs/server.log`
- **GPU Problems**: See `docs/gpu-deployment.md`
- **Architecture**: See `docs/architecture-rules.md`

## Roadmap

- [x] Voice-to-voice pipeline
- [x] GPU acceleration
- [x] Docker deployment
- [x] RunPod support
- [ ] Metrics and monitoring
- [ ] Multi-language support
- [ ] Model quantization
- [ ] Auto-scaling

---

Built with ❤️ using FastAPI, WebRTC, Faster-Whisper, Gemini, and MeloTTS

