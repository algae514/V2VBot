#!/usr/bin/env bash
set -euo pipefail

PY=${PYTHON:-python3}

if [ ! -d .venv ]; then
	$PY -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip install --upgrade pip
pip install -r server/requirements.txt

echo "Installation complete. To start the server: bash start.sh"
