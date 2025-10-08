param(
	[string]$HostAddr = "0.0.0.0",
	[int]$Port = 8000,
	[string]$WhisperBin = $null,
	[string]$WhisperModel = $null,
	[string]$SileroOnnx = $null,
	[string]$VadEnergyFallback = $null,
	[string]$VadThreshold = $null,
	[string]$VadEndMs = $null
)

$ErrorActionPreference = "Stop"

$activate = Join-Path ".venv" "Scripts\Activate.ps1"
if (Test-Path $activate) {
	. $activate
}

if ($WhisperBin) { $env:WHISPER_CPP_BIN = $WhisperBin }
if ($WhisperModel) { $env:WHISPER_CPP_MODEL = $WhisperModel }
if ($SileroOnnx) { $env:SILERO_VAD_ONNX = $SileroOnnx }
if ($VadEnergyFallback) { $env:VAD_ENERGY_FALLBACK = $VadEnergyFallback }
if ($VadThreshold) { $env:VAD_THRESHOLD = $VadThreshold }
if ($VadEndMs) { $env:VAD_END_MS = $VadEndMs }

Write-Host "Using env:"
Write-Host "  WHISPER_CPP_BIN=$($env:WHISPER_CPP_BIN)"
Write-Host "  WHISPER_CPP_MODEL=$($env:WHISPER_CPP_MODEL)"
Write-Host "  SILERO_VAD_ONNX=$($env:SILERO_VAD_ONNX)"
Write-Host "  VAD_ENERGY_FALLBACK=$($env:VAD_ENERGY_FALLBACK)"
Write-Host "  VAD_THRESHOLD=$($env:VAD_THRESHOLD)"
Write-Host "  VAD_END_MS=$($env:VAD_END_MS)"

python -m uvicorn server.app.main:app --host $HostAddr --port $Port --reload
