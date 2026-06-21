#!/bin/bash
set -euo pipefail

PORT=""

while getopts "p:" opt; do
  case $opt in
    p) PORT="$OPTARG" ;;
    *) echo "Usage: $0 [-p PORT]" >&2; exit 1 ;;
  esac
done

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Work directory: $WORK_DIR"

echo "Creating virtual environment..."
python3 -m venv "$WORK_DIR/.venv"

echo "Installing esptool..."
"$WORK_DIR/.venv/bin/pip" install "esptool<5"

echo "Downloading firmware..."
curl -fsSL "https://install.wingbits.com/geosigner-v1.0.0.merged.bin" -o "$WORK_DIR/geosigner-v1.0.0.merged.bin"

PORT_ARGS=()
if [[ -n "$PORT" ]]; then
  PORT_ARGS=(--port "$PORT")
fi

WINGBITS_WAS_RUNNING=false
if systemctl is-active --quiet wingbits 2>/dev/null; then
  WINGBITS_WAS_RUNNING=true
  echo "Stopping wingbits service..."
  systemctl stop wingbits
fi
trap 'rm -rf "$WORK_DIR"; if [[ "$WINGBITS_WAS_RUNNING" == "true" ]]; then echo "Restarting wingbits..."; systemctl start wingbits || true; fi' EXIT


MAX_ATTEMPTS=5
ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "Flash attempt $ATTEMPT of $MAX_ATTEMPTS..."
  if "$WORK_DIR/.venv/bin/python3" -m esptool \
      "${PORT_ARGS[@]}" \
      --chip esp32c3 \
      --no-stub \
      write_flash \
      --flash_mode keep \
      --flash_freq 80m \
      --flash_size 4MB \
      0x0 "$WORK_DIR/geosigner-v1.0.0.merged.bin"; then
    echo "Firmware flashed successfully"
    exit 0
  fi
  if [[ $ATTEMPT -ge $MAX_ATTEMPTS ]]; then
    echo "All $MAX_ATTEMPTS flash attempts failed" >&2
    exit 1
  fi
  echo "Retrying in 5 seconds..."
  sleep 5
done
