# V2VBot Dockerfile for RunPod GPU Deployment
# Optimized for RTX 2000 Ada with CUDA 12.1

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
    libsndfile1-dev \
    libopus0 \
    libopus-dev \
    portaudio19-dev \
    libssl-dev \
    sox \
    libsox-dev \
    libsox-fmt-all \
    mecab \
    libmecab2 \
    libmecab-dev \
    mecab-ipadic-utf8 \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Configure mecab library cache
RUN MECAB_LIB=$(find /usr/lib /usr/local/lib -name "libmecab.so.2*" 2>/dev/null | head -n 1) && \
    if [ -n "$MECAB_LIB" ]; then \
        MECAB_DIR=$(dirname "$MECAB_LIB") && \
        echo "$MECAB_DIR" > /etc/ld.so.conf.d/mecab.conf && \
        ldconfig; \
    fi

# Install Rust compiler (needed for tokenizers)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    export PATH="$HOME/.cargo/bin:$PATH" || true
ENV PATH="/root/.cargo/bin:${PATH}"

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY server/requirements.txt /app/server/requirements.txt

# Install Python dependencies
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel && \
    pip3 install --no-cache-dir --only-binary=tokenizers -r /app/server/requirements.txt

# Install MeloTTS without dependencies to avoid transformers conflict
RUN pip3 install --no-cache-dir --no-deps git+https://github.com/myshell-ai/MeloTTS.git@main

# Install MeloTTS dependencies
RUN pip3 install --no-cache-dir --only-binary=tokenizers \
    anyascii==0.3.2 \
    cached_path \
    cn2an==0.5.22 \
    eng_to_ipa==0.0.2 \
    fugashi==1.3.0 \
    g2p_en==2.1.0 \
    'g2pkk>=0.1.1' \
    'gruut[de,es,fr]==2.2.3' \
    inflect==7.0.0 \
    jamo==0.4.1 \
    jieba==0.42.1 \
    langid==1.1.6 \
    librosa==0.9.1 \
    loguru==0.7.2 \
    mecab-python3==1.0.9 \
    num2words==0.5.12 \
    pydub==0.25.1 \
    pykakasi==2.2.1 \
    pypinyin==0.50.0 \
    tensorboard==2.16.2 \
    txtsplit \
    unidecode==1.3.7 \
    unidic==1.1.0 \
    unidic_lite==1.0.8 || true

# Download UniDic dictionary
RUN python3 -m unidic download || true

# Copy application code
COPY server/ /app/server/
COPY web/ /app/web/
COPY models/ /app/models/

# Create necessary directories
RUN mkdir -p /app/logs /app/debug_audio

# Download and prepare models (if not already in models/)
WORKDIR /app/models
RUN if [ ! -f "silero_vad.onnx" ]; then \
        wget -q https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx; \
    fi && \
    if [ ! -f "ggml-small.en.bin" ]; then \
        echo "Whisper models will be downloaded on first run"; \
    fi

WORKDIR /app

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Set environment variables for GPU usage
ENV USE_GPU=true \
    CUDA_VISIBLE_DEVICES=0

# Run the application
CMD ["python3", "-m", "uvicorn", "server.app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]

