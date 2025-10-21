#!/usr/bin/env bash
# V2VBot Start Script for VastAI
set -euo pipefail

PIDFILE=.uvicorn.pid
HOST=0.0.0.0
PORT=8080
APP=server.app.main:app

# Activate venv if present
if [ -d venv ]; then
	# shellcheck disable=SC1091
	source venv/bin/activate
elif [ -d .venv ]; then
	# shellcheck disable=SC1091
	source .venv/bin/activate
fi

# If a server is already running, stop it
if [ -f "$PIDFILE" ]; then
	PID=$(cat "$PIDFILE") || true
	if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
		echo "Stopping existing server (PID $PID)" || true
		kill "$PID" || true
		# Wait a moment for clean shutdown
		sleep 1
	fi
	rm -f "$PIDFILE"
fi

# Start new server
uvicorn "$APP" --host "$HOST" --port "$PORT" --workers 1 &
NEWPID=$!
echo $NEWPID > "$PIDFILE"
echo "V2VBot server started at http://$HOST:$PORT (PID $NEWPID)"
echo "Check your VastAI dashboard for the public URL"

