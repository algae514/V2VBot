# VastAI Deployment Guide

This guide explains how to deploy V2VBot on VastAI cloud infrastructure.

## Prerequisites

1. **VastAI Account**: Sign up at [vast.ai](https://vast.ai)
2. **GitHub Repository**: Your V2VBot code should be in a GitHub repository
3. **Gemini API Key**: Get your API key from [Google AI Studio](https://aistudio.google.com/)

## Quick Start

### Option 1: Using Docker (Recommended)

1. **Create a VastAI Instance**:
   - Go to [vast.ai](https://vast.ai) and create a new instance
   - Choose a GPU instance (RTX 4090, A100, etc.)
   - Select Ubuntu 22.04 with Docker support
   - Set the Docker image to: `nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04`

2. **Configure the Instance**:
   - **Port**: Set to `8080`
   - **Disk Space**: At least 20GB
   - **Startup Command**: Leave empty (we'll set it up manually)

3. **SSH into your instance** and run:
   ```bash
   # Clone your repository
   git clone https://github.com/yourusername/V2VBot.git
   cd V2VBot
   
   # Set up environment
   cp env.example .env
   nano .env  # Add your GEMINI_API_KEY
   
   # Build and run with Docker
   docker build -t v2vbot .
   docker run --gpus all -p 8080:8080 -v $(pwd)/models:/app/models v2vbot
   ```

### Option 2: Direct Installation

1. **Create a VastAI Instance**:
   - Choose Ubuntu 22.04 without Docker
   - Set **Port** to `8080`
   - **Disk Space**: At least 20GB

2. **SSH into your instance** and run:
   ```bash
   # Clone your repository
   git clone https://github.com/yourusername/V2VBot.git
   cd V2VBot
   
   # Run the setup script
   chmod +x setup_server.sh
   ./setup_server.sh
   
   # Start the server
   chmod +x start_vastai.sh
   ./start_vastai.sh
   ```

## Detailed Setup Instructions

### 1. Environment Configuration

Create a `.env` file with your configuration:

```bash
cp env.example .env
nano .env
```

Required configuration:
```env
GEMINI_API_KEY=your_actual_gemini_api_key_here
USE_GPU=true
```

### 2. Manual Setup (if not using scripts)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y python3 python3-pip python3-venv python3-dev \
    build-essential git wget curl ffmpeg libsndfile1 libopus0 \
    libopus-dev portaudio19-dev

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python packages
pip install --upgrade pip
pip install -r server/requirements.txt

# Download models
mkdir -p models
cd models
wget https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
cd ..
```

### 3. Starting the Server

#### Using the VastAI startup script:
```bash
chmod +x start_vastai.sh
./start_vastai.sh
```

#### Using the standard start script:
```bash
chmod +x start.sh
./start.sh
```

#### Manual start:
```bash
source venv/bin/activate
python -m uvicorn server.app.main:app --host 0.0.0.0 --port 8080 --workers 1
```

## Accessing Your Application

1. **Get the Public URL**: Check your VastAI dashboard for the public URL
2. **Open in Browser**: Navigate to the provided URL
3. **Test the Application**: Click "Start Voice Chat" to test the voice-to-voice functionality

## Troubleshooting

### Common Issues

1. **Port Not Accessible**:
   - Ensure port 8080 is configured in VastAI instance settings
   - Check that the server is binding to `0.0.0.0:8080`

2. **GPU Not Detected**:
   - Verify GPU is available: `nvidia-smi`
   - Check CUDA installation: `nvcc --version`
   - Ensure PyTorch CUDA support: `python -c "import torch; print(torch.cuda.is_available())"`

3. **Models Not Loading**:
   - Check internet connection for model downloads
   - Verify models directory exists and has proper permissions
   - Check logs for specific error messages

4. **API Key Issues**:
   - Verify `.env` file exists and contains valid `GEMINI_API_KEY`
   - Test API key: `python -c "import os; from dotenv import load_dotenv; load_dotenv(); print('API Key set:', bool(os.getenv('GEMINI_API_KEY')))"`

### Logs and Monitoring

- **Application Logs**: `tail -f logs/server.log`
- **System Logs**: `journalctl -u v2vbot -f` (if using systemd)
- **GPU Status**: `nvidia-smi`
- **Process Status**: `ps aux | grep uvicorn`

### Performance Optimization

1. **GPU Memory**: Monitor with `nvidia-smi`
2. **CPU Usage**: Use `htop` to monitor CPU
3. **Disk Space**: Ensure sufficient space for models and logs
4. **Network**: Check bandwidth for real-time audio streaming

## Cost Optimization

1. **Instance Selection**: Choose appropriate GPU based on your needs
2. **Auto-shutdown**: Configure auto-shutdown when not in use
3. **Resource Monitoring**: Monitor usage to avoid unnecessary costs

## Security Considerations

1. **API Keys**: Never commit API keys to version control
2. **Network Access**: VastAI instances are publicly accessible
3. **Data Privacy**: Be aware that audio data is processed on the cloud instance

## Support

- **VastAI Documentation**: [vast.ai/docs](https://vast.ai/docs)
- **V2VBot Issues**: Create an issue in the GitHub repository
- **Community**: Join VastAI Discord for community support

## Next Steps

After successful deployment:

1. **Test the Application**: Verify all functionality works correctly
2. **Monitor Performance**: Check logs and resource usage
3. **Scale as Needed**: Adjust instance size based on usage
4. **Backup Configuration**: Save your working configuration
5. **Documentation**: Update any custom configurations for future deployments
