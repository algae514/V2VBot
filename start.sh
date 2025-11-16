#!/usr/bin/env bash
set -euo pipefail

PIDFILE=.uvicorn.pid
HOST=0.0.0.0
PORT=8080
APP=server.app.main:app

# SSL Configuration
SSL_CERT="${SSL_CERT:-ssl/cert.pem}"
SSL_KEY="${SSL_KEY:-ssl/key.pem}"

# Activate venv if present
if [ -d .venv ]; then
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

# Check if SSL certificates exist
if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
	echo "🔒 Starting server with HTTPS..."
	uvicorn "$APP" --host "$HOST" --port "$PORT" --ssl-keyfile "$SSL_KEY" --ssl-certfile "$SSL_CERT" --reload &
	NEWPID=$!
	echo $NEWPID > "$PIDFILE"
	echo "✅ Server started at https://$HOST:$PORT (PID $NEWPID)"
	echo "⚠️  Note: If using self-signed certificate, your browser will show a security warning."
	echo "   Click 'Advanced' → 'Proceed to site' to continue."
else
	echo "⚠️  SSL certificates not found. Starting server with HTTP..."
	echo "   To enable HTTPS, run: ./setup_ssl.sh"
	uvicorn "$APP" --host "$HOST" --port "$PORT" --reload &
	NEWPID=$!
	echo $NEWPID > "$PIDFILE"
	echo "Server started at http://$HOST:$PORT (PID $NEWPID)"
fi

