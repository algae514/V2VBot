# V2VBot Dockerfile for VastAI GPU Deployment
# Optimized for GPU acceleration with CUDA 12.1

FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    python3-dev \
    build-essential \
    git \
    wget \
    curl \
    ffmpeg \
    libsndfile1 \
    libopus0 \
    libopus-dev \
    portaudio19-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY server/requirements.txt /app/server/requirements.txt

# Install Python dependencies
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel && \
    pip3 install --no-cache-dir -r /app/server/requirements.txt

# Copy application code
COPY server/ /app/server/
COPY web/ /app/web/

# Create necessary directories (models will be downloaded during server setup)
RUN mkdir -p /app/logs /app/debug_audio /app/models && \
    if [ ! -f "ggml-small.en.bin" ]; then \
        echo "Whisper models will be downloaded on first run"; \
    fi

WORKDIR /app

# Expose port (VastAI typically uses port 8080)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Set environment variables for GPU usage
ENV USE_GPU=true \
    CUDA_VISIBLE_DEVICES=0

# Run the application
CMD ["python3", "-m", "uvicorn", "server.app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]

