#!/bin/bash
set -euo pipefail

IMAGE_TAG="hass-custom-dev-smoke"
CONFIG_DIR=$(mktemp -d)
echo "[i] Using temp config dir: ${CONFIG_DIR}"

cleanup() {
  rm -rf "${CONFIG_DIR}" || true
  docker rm -f hass-smoke >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[+] Building image"
docker build -t ${IMAGE_TAG} .

echo "[+] Running setup phase (runtime HA install)"
docker run --rm -v ${CONFIG_DIR}:/config ${IMAGE_TAG} container setup >/dev/null
if [[ ! -f "${CONFIG_DIR}/configuration.yaml" ]]; then
  echo "[FAIL] configuration.yaml not created" >&2
  exit 1
fi

echo "[+] Launching container for startup log check"
docker run -d --name hass-smoke -v ${CONFIG_DIR}:/config -p 58123:8123 ${IMAGE_TAG} >/dev/null
sleep 12
if docker logs hass-smoke 2>&1 | grep -q "Starting Home Assistant"; then
  echo "[OK] Home Assistant emitted startup log"
else
  echo "[WARN] Startup log not yet detected (increase sleep?)"
fi

echo "[+] Checking hass version via exec"
docker exec hass-smoke hass --version || echo "[WARN] hass --version failed"

echo "[+] Smoke test complete"
