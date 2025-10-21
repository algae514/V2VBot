# Docker Hub Deployment Guide

This guide explains how to build and deploy V2VBot as a Docker image to Docker Hub.

## Prerequisites

1. **Docker**: Install Docker Desktop or Docker Engine
2. **Docker Hub Account**: Sign up at [hub.docker.com](https://hub.docker.com)
3. **GitHub Repository**: Your V2VBot code should be in a GitHub repository
4. **Gemini API Key**: Get your API key from [Google AI Studio](https://aistudio.google.com/)

## Quick Deployment

### 1. Configure Docker Hub Credentials

```bash
# Set your Docker Hub username
export DOCKER_USERNAME="algae514"

# Login to Docker Hub
docker login
```

### 2. Run Deployment Script

```bash
# Make script executable and run
chmod +x deploy_dockerhub.sh
./deploy_dockerhub.sh
```

The script will:
- Build the Docker image
- Test it locally (optional)
- Push to Docker Hub
- Create docker-compose.yml for easy deployment

## Manual Deployment

### 1. Build the Image

```bash
# Build using the optimized Dockerfile
docker build -f Dockerfile.dockerhub -t your-username/v2vbot:latest .
```

### 2. Test Locally

```bash
# Run the container
docker run -d -p 8080:8080 -p 3478:3478 -p 5349:5349 \
  -p 50000-50050:50000-50050/udp \
  your-username/v2vbot:latest

# Check if it's running
docker ps

# View logs
docker logs <container-id>

# Test the application
curl http://localhost:8080/
```

### 3. Push to Docker Hub

```bash
# Push the image
docker push your-username/v2vbot:latest
```

## Docker Image Features

### Optimized Dockerfile
- **Base Image**: `nvidia/cuda:12.2.0-runtime-ubuntu22.04`
- **User Security**: Runs as non-root `appuser`
- **GPU Support**: Full CUDA 12.2 support
- **WebRTC Support**: Includes TURN server (coturn)
- **Multi-stage Build**: Optimized for size and security

### Port Configuration
- **8080**: Main V2VBot application
- **3478/tcp & 3478/udp**: TURN server for WebRTC
- **5349/tcp**: TURNS server (TLS)
- **50000-50050/udp**: TURN relay ports

### Environment Variables
```env
USE_GPU=true
CUDA_VISIBLE_DEVICES=0
GEMINI_API_KEY=your_api_key_here
```

## Deployment Options

### Option 1: Docker Compose (Recommended)

```bash
# Use the generated docker-compose file
docker-compose -f docker-compose.dockerhub.yml up -d

# View logs
docker-compose -f docker-compose.dockerhub.yml logs -f

# Stop
docker-compose -f docker-compose.dockerhub.yml down
```

### Option 2: Direct Docker Run

```bash
# CPU only
docker run -d -p 8080:8080 -p 3478:3478 -p 5349:5349 \
  -p 50000-50050:50000-50050/udp \
  -v $(pwd)/.env:/home/appuser/.env:ro \
  your-username/v2vbot:latest

# With GPU support
docker run --gpus all -d -p 8080:8080 -p 3478:3478 -p 5349:5349 \
  -p 50000-50050:50000-50050/udp \
  -v $(pwd)/.env:/home/appuser/.env:ro \
  your-username/v2vbot:latest
```

### Option 3: Cloud Deployment

#### VastAI
```bash
# Pull and run on VastAI instance
docker pull your-username/v2vbot:latest
docker run --gpus all -d -p 8080:8080 -p 3478:3478 -p 5349:5349 \
  -p 50000-50050:50000-50050/udp \
  your-username/v2vbot:latest
```

#### RunPod
```bash
# Use in RunPod Docker template
docker pull your-username/v2vbot:latest
docker run --gpus all -d -p 8080:8080 -p 3478:3478 -p 5349:5349 \
  -p 50000-50050:50000-50050/udp \
  your-username/v2vbot:latest
```

## Configuration

### Environment File Setup

Create a `.env` file with your configuration:

```env
# Required
GEMINI_API_KEY=your_actual_gemini_api_key_here

# GPU Configuration
USE_GPU=true
CUDA_VISIBLE_DEVICES=0

# Model Configuration
GEMINI_MODEL=gemini-2.0-flash

# VAD Settings
VAD_END_MS=1500
VAD_TURN_END_MS=2000
```

### Volume Mounts

```bash
# Mount environment file
-v $(pwd)/.env:/home/appuser/.env:ro

# Mount logs directory
-v $(pwd)/logs:/home/appuser/logs

# Mount models directory (for persistence)
-v $(pwd)/models:/home/appuser/models
```

## Troubleshooting

### Common Issues

1. **Container Won't Start**:
   ```bash
   # Check logs
   docker logs <container-id>
   
   # Check if ports are available
   netstat -tulpn | grep :8080
   ```

2. **GPU Not Detected**:
   ```bash
   # Check NVIDIA Docker runtime
   docker run --rm --gpus all nvidia/cuda:12.2.0-runtime-ubuntu22.04 nvidia-smi
   
   # Verify GPU support in container
   docker exec <container-id> nvidia-smi
   ```

3. **WebRTC Connection Issues**:
   ```bash
   # Check TURN server
   docker exec <container-id> netstat -tulpn | grep :3478
   
   # Test TURN server
   docker exec <container-id> turnserver --listening-port=3478 --test
   ```

4. **API Key Issues**:
   ```bash
   # Check environment file
   docker exec <container-id> cat .env
   
   # Verify API key is loaded
   docker exec <container-id> python3 -c "import os; from dotenv import load_dotenv; load_dotenv(); print('API Key set:', bool(os.getenv('GEMINI_API_KEY')))"
   ```

### Performance Optimization

1. **GPU Memory**: Monitor with `nvidia-smi`
2. **Container Resources**: Limit CPU and memory if needed
3. **Model Caching**: Mount models directory for persistence
4. **Log Management**: Mount logs directory for persistence

### Security Considerations

1. **Non-root User**: Container runs as `appuser`
2. **Read-only Mounts**: Environment file mounted read-only
3. **Network Security**: Only necessary ports exposed
4. **API Keys**: Never hardcode in Dockerfile

## Image Management

### Tagging Strategy

```bash
# Tag with version
docker tag your-username/v2vbot:latest your-username/v2vbot:v1.0.0

# Tag with date
docker tag your-username/v2vbot:latest your-username/v2vbot:$(date +%Y%m%d)

# Push multiple tags
docker push your-username/v2vbot:latest
docker push your-username/v2vbot:v1.0.0
```

### Image Size Optimization

The Dockerfile is optimized for:
- **Multi-stage builds**: Separate build and runtime
- **Layer caching**: Requirements installed first
- **Minimal dependencies**: Only necessary packages
- **Model downloading**: Models downloaded during build

### Cleanup

```bash
# Remove unused images
docker image prune -a

# Remove unused containers
docker container prune

# Remove unused volumes
docker volume prune
```

## Monitoring and Logs

### Health Checks

The container includes health checks:
```bash
# Check container health
docker ps

# View health check logs
docker inspect <container-id> | grep -A 10 Health
```

### Log Management

```bash
# View application logs
docker logs <container-id>

# Follow logs in real-time
docker logs -f <container-id>

# View logs with timestamps
docker logs -t <container-id>
```

## Support

- **Docker Hub**: [hub.docker.com](https://hub.docker.com)
- **Docker Documentation**: [docs.docker.com](https://docs.docker.com)
- **V2VBot Issues**: Create an issue in the GitHub repository
- **Community**: Join Docker community forums

## Next Steps

After successful deployment:

1. **Test the Application**: Verify all functionality works
2. **Monitor Performance**: Check logs and resource usage
3. **Scale as Needed**: Deploy multiple instances if required
4. **Backup Configuration**: Save your working configuration
5. **Documentation**: Update any custom configurations

---

Your V2VBot Docker image is now ready for deployment! 🚀
