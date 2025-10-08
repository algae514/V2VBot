param(
	[string]$Python = "python"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path .venv)) {
	& $Python -m venv .venv
}

$activate = Join-Path ".venv" "Scripts\Activate.ps1"
. $activate

python -m pip install --upgrade pip
python -m pip install -r server/requirements.txt

Write-Host "Installed dependencies into .venv"
