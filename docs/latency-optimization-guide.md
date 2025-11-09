# Latency Optimization Guide

## Current Performance
- **Average E2E Latency**: 4.67s (from speech end to first audio)
- **Target**: <2.5s for natural conversation

## Quick Wins (Easy to Implement)

### 1. Faster STT Model (Save ~0.7-1.0s)

**Current**: `small.en` (1.3s)
**Options**:
- `tiny.en`: ~0.3-0.5s (3-4x faster, slight accuracy loss)
- `base.en`: ~0.6-0.8s (2x faster, minimal accuracy loss)

**Implementation**:
```bash
# In .env file
WHISPER_MODEL=tiny.en  # or base.en
```

**Trade-off**: Slight accuracy reduction, but much faster

### 2. Reduce VAD Pause Time (Save ~0.5s)

**Current**: 1.5s pause detection
**Recommended**: 1.0s (faster turn detection)

**Implementation**:
```bash
# In .env file
VAD_END_MS=1000  # Reduced from 1500ms
```

**Trade-off**: May occasionally cut off slow speakers

### 3. Enable GPU Acceleration (Save ~0.8-1.0s)

**Current**: CPU-only processing
**With GPU**: 5-7x faster STT

**Implementation**:
```bash
# In .env file
USE_GPU=true
# Remove device="cpu" from pipeline.py line 27
```

**Requirements**: GPU with CUDA support

## Medium Effort (Higher Impact)

### 4. Local TTS (Save ~1.2-3.7s)

**Current**: HTTP-based TTS (1.4-4.0s with network latency)
**Local TTS**: ~0.1-0.3s per sentence

**Options**:
- **Coqui TTS**: Fast, good quality, easy setup
- **Local MeloTTS**: If you have the model files
- **Piper TTS**: Very fast, lightweight

**Impact**: Biggest single improvement (removes network latency)

## Implementation Priority

1. **Immediate** (5 minutes):
   - Change `WHISPER_MODEL=tiny.en` in `.env`
   - Change `VAD_END_MS=1000` in `.env`
   - **Expected**: 3.5-4.0s latency (25-30% improvement)

2. **Short-term** (30 minutes):
   - Enable GPU if available
   - **Expected**: 2.5-3.0s latency (40-50% improvement)

3. **Medium-term** (2-4 hours):
   - Implement local TTS
   - **Expected**: 1.5-2.0s latency (60-70% improvement)

## Advanced Optimizations

### Streaming STT (Hard, but high impact)
- Process audio chunks as user speaks
- Start LLM with partial transcript
- **Impact**: Perceived latency reduction of 0.5-1.0s

### LLM Optimization
- Use smaller context window
- Pre-warm model
- **Impact**: 0.2-0.4s reduction

## Expected Results

| Optimization | Latency | Improvement |
|--------------|---------|-------------|
| Current | 4.67s | - |
| Quick Wins (1+2) | 3.5s | 25% |
| + GPU | 2.5s | 47% |
| + Local TTS | 1.5s | 68% |

