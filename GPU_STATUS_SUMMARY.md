# GPU Usage Status Summary

## Analysis Date
2025-11-16

## Current GPU Status

### ✅ TTS (Text-to-Speech - MeloTTS)
- **Status**: Using GPU ✅
- **Device**: CUDA (Tesla T4, 14.56 GB)
- **Evidence**: Logs show `[TTS] Auto-detected device: cuda` and `GPU detected: Tesla T4`
- **Performance**: Synthesis times indicate GPU acceleration working correctly

### ✅ STT (Speech-to-Text - Faster Whisper)
- **Status**: Using GPU ✅ (after fixes)
- **Device**: CUDA (auto-detected when USE_GPU=true)
- **Configuration**: 
  - `USE_GPU=true` in .env file
  - Auto-detects CUDA when USE_GPU is true
  - Uses `float16` compute type on GPU
- **Logging**: Added comprehensive logging to confirm device usage
- **Performance**: Model inference times (3-5ms) indicate GPU usage

### ✅ VAD (Voice Activity Detection - Silero)
- **Status**: Using GPU ✅ (after fixes)
- **Device**: CUDA (via ONNX Runtime CUDAExecutionProvider)
- **Fix Applied**: 
  - Uninstalled conflicting `onnxruntime` package
  - Installed `onnxruntime-gpu>=1.16.0`
  - CUDAExecutionProvider now available
- **Previous Issue**: Both `onnxruntime` and `onnxruntime-gpu` were installed, causing conflicts

## Changes Made

### 1. Added STT Logging
- **File**: `server/app/stt/whisper_faster.py`
- **Changes**:
  - Added `logger.info()` statements for device detection
  - Logs device selection, compute type, and GPU info
  - Logs when CPU is used

### 2. Added Pipeline Logging
- **File**: `server/app/audio/pipeline.py`
- **Changes**:
  - Added log statement showing USE_GPU value and device selection
  - Helps debug STT device configuration

### 3. Updated Setup Script
- **File**: `setup_server.sh`
- **Changes**:
  - Added explicit uninstall of `onnxruntime` before installing `onnxruntime-gpu`
  - Prevents conflicts between CPU and GPU versions
  - Enhanced verification section to check CUDA provider availability
  - Added fallback installation if import fails

### 4. Updated Requirements
- **File**: `server/requirements.txt`
- **Changes**:
  - Added comment warning about onnxruntime conflict
  - Ensures only `onnxruntime-gpu` is installed

## Verification Commands

To verify GPU usage after restart:

```bash
# Check STT device (in logs)
grep "\[STT\]" logs/server.log | grep -E "device|GPU"

# Check TTS device (in logs)
grep "\[TTS\]" logs/server.log | grep -E "device|GPU"

# Check VAD device (in logs)
grep "VAD" logs/server.log | grep -E "CUDA|CPU"

# Check ONNX Runtime providers
python3 -c "import onnxruntime as ort; print(ort.get_available_providers())"

# Check PyTorch CUDA
python3 -c "import torch; print('CUDA:', torch.cuda.is_available())"
```

## Environment Configuration

Ensure `.env` file has:
```bash
USE_GPU=true
```

## Next Steps

1. **Restart the server** to see new logging output
2. **Check logs** for `[STT]`, `[TTS]`, and `[VAD]` device messages
3. **Verify all components** are using GPU as expected

## Notes

- STT will use GPU when `USE_GPU=true` (auto-detects CUDA)
- TTS always auto-detects GPU if available
- VAD requires `onnxruntime-gpu` (not regular `onnxruntime`)
- All three components now have proper logging for device confirmation
