#!/bin/bash
set -euo pipefail

# Build, run, and verify the Home Assistant dev image using the readiness script.
# This is a convenience wrapper for CI or local quick checks.
#
# Flags:
#   --tag <tag>          Image tag to build/use (default: hass-dev-test)
#   --timeout <seconds>  Readiness timeout (default: 300)
#   --no-cache           Pass --no-cache to docker build
#   --keep               Do not remove container on success
#   --log                Require log phrase
#   --api-only           Skip root HTTP check
#   --http-only          Skip API check
#   --json               Produce JSON result
#
# Exit codes:
#   0 success; 1 failure; 2 usage error

TAG="hass-dev-test"
TIMEOUT=300
NO_CACHE=0
KEEP=0
REQUIRE_LOG=0
SKIP_HTTP=0
SKIP_API=0
JSON=0

fail_usage(){ echo "Usage error: $1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --no-cache) NO_CACHE=1; shift ;;
    --keep) KEEP=1; shift ;;
    --log) REQUIRE_LOG=1; shift ;;
    --api-only) SKIP_HTTP=1; shift ;;
    --http-only) SKIP_API=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail_usage "Unknown arg $1" ;;
  esac
done

if [[ $SKIP_HTTP -eq 1 && $SKIP_API -eq 1 ]]; then
  fail_usage "--api-only and --http-only are mutually exclusive"
fi

BUILD_ARGS=()
[[ $NO_CACHE -eq 1 ]] && BUILD_ARGS+=(--no-cache)

PRIMARY_TAG="$TAG"
# If TAG contains spaces (multiple tags), take the first as primary.
if [[ "$TAG" =~ [[:space:]] ]]; then
  # shellcheck disable=SC2206
  TAG_ARR=($TAG)
  PRIMARY_TAG="${TAG_ARR[0]}"
fi

echo "[+] Building image primary tag=${PRIMARY_TAG}" >&2
docker build "${BUILD_ARGS[@]}" -t "$PRIMARY_TAG" .

CID="ha-verify-$(date +%s)"
echo "[+] Running container name=${CID}" >&2
docker run -d --name "$CID" -p 58123:8123 "$PRIMARY_TAG" >/dev/null

cleanup() {
  if [[ $KEEP -eq 0 ]]; then
    docker rm -f "$CID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

SCRIPT="./scripts_ready_check.sh --url http://localhost:58123 --timeout $TIMEOUT --container $CID"
[[ $REQUIRE_LOG -eq 1 ]] && SCRIPT+=" --require-log"
[[ $SKIP_HTTP -eq 1 ]] && SCRIPT+=" --skip-http"
[[ $SKIP_API -eq 1 ]] && SCRIPT+=" --skip-api"
[[ $JSON -eq 1 ]] && SCRIPT+=" --json"

echo "[+] Probing readiness: $SCRIPT" >&2
if $SCRIPT; then
  [[ $JSON -eq 0 ]] && echo "[OK] Image verified" >&2
  exit 0
else
  [[ $JSON -eq 0 ]] && echo "[FAIL] Verification failed" >&2
  exit 1
fi
