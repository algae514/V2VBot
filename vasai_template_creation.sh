#!/usr/bin/env bash
set -euo pipefail

# ========== CONFIG ==========
# Template ID you created earlier
TEMPLATE_ID="${TEMPLATE_ID:-294061}"

# Values to apply (change if you want different)
IMAGE="docker.io/vastai/kvm:ubuntu_cli_22.04-2025-05-16"
DOCKER_OPTIONS="--gpus all --shm-size=8g -v /tmp:/tmp"
# Ports string accepted by Vast API (both UDP and TCP for 3478)
PORTS="8080:8080/tcp,3478:3478/tcp,3478:3478/udp,5349:5349/tcp,50000-50050:50000-50050/udp"
ENV_VARS="USE_GPU=true,CUDA_VISIBLE_DEVICES=0,PYTHONUNBUFFERED=1"
TEMPLATE_NAME="voice-assistant-gpu-template"
# ============================

# helper prints
err() { echo "ERROR: $*" >&2; }
info() { echo "INFO: $*"; }

# check for required tools
if ! command -v curl >/dev/null 2>&1; then
  err "curl is required. Install it and re-run."
  exit 1
fi

# Try to get API key:
if [[ -n "${VAST_API_KEY:-}" ]]; then
  API_KEY="$VAST_API_KEY"
else
  # attempt to extract via vastai CLI if available
  if command -v vastai >/dev/null 2>&1; then
    info "VAST_API_KEY not set — trying 'vastai show api-keys' to obtain key..."
    # try two command variants to be robust
    if vastai show api-keys --raw >/dev/null 2>&1; then
      # try JSON output
      API_KEY="$(vastai show api-keys --json 2>/dev/null | jq -r '.[0].key' 2>/dev/null || true)"
    else
      # fallback
      API_KEY="$(vastai show api-key 2>/dev/null | awk '/key/ {print $2}' || true)"
    fi
    if [[ -z "$API_KEY" ]]; then
      err "Could not extract API key from 'vastai' CLI. Please export VAST_API_KEY and re-run."
      exit 1
    fi
  else
    err "VAST_API_KEY environment variable not set, and 'vastai' CLI is not present. Please set VAST_API_KEY and re-run."
    exit 1
  fi
fi

# confirm API key looks like something
if [[ ${#API_KEY} -lt 10 ]]; then
  err "API key appears too short. Please confirm VAST_API_KEY is correct."
  exit 1
fi

info "Using template id: $TEMPLATE_ID"
info "Patching template to use image: $IMAGE"
info "Docker options: $DOCKER_OPTIONS"
info "Ports: $PORTS"
info "Env: $ENV_VARS"

# Build JSON payload safely
payload=$(jq -n \
  --arg name "$TEMPLATE_NAME" \
  --arg image "$IMAGE" \
  --arg docker_options "$DOCKER_OPTIONS" \
  --arg ports "$PORTS" \
  --arg env "$ENV_VARS" \
  '{
    name: $name,
    image: $image,
    docker_options: $docker_options,
    ports: $ports,
    env: $env
  }')

# If jq not available, fallback to manual JSON (less safe); check jq
if ! command -v jq >/dev/null 2>&1; then
  info "jq not found — building JSON payload via here-doc (ensure none of the values contain double quotes)."
  payload=$(cat <<JSON
{"name":"$TEMPLATE_NAME","image":"$IMAGE","docker_options":"$DOCKER_OPTIONS","ports":"$PORTS","env":"$ENV_VARS"}
JSON
)
fi

API_URL="https://api.vast.ai/v0/templates/${TEMPLATE_ID}/"

info "Patching template via Vast.ai API..."
http_status=$(curl -s -o /tmp/vast_patch_resp.json -w "%{http_code}" \
  -X PATCH "$API_URL" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$payload")

if [[ "$http_status" -ge 200 && "$http_status" -lt 300 ]]; then
  info "Template patched successfully (HTTP $http_status)."
  cat /tmp/vast_patch_resp.json | sed -n '1,200p'
  info ""
  info "Next steps:"
  info "1) Open Vast web console Templates page to confirm ports and docker options."
  info "2) Launch an instance with this template using the CLI: "
  info "   vastai search offers 'gpu_name:RTX_3090 rentable:true' --limit 5"
  info "   vastai create instance <OFFER_ID> --template $TEMPLATE_ID"
  info ""
  info "If you want I can also produce a script to create an instance and run the pre-checks (udp test, coturn health)."
  exit 0
else
  err "API returned HTTP $http_status. Response follows:"
  cat /tmp/vast_patch_resp.json >&2
  err "If this is a permissions error, ensure your API key is from the account that owns the template (ID $TEMPLATE_ID)."
  err "If the web UI blocks duplicate port entries you can still try the web UI method or adjust ports."
  exit 2
fi