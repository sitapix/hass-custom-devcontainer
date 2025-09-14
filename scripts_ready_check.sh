#!/bin/bash
set -euo pipefail

## Home Assistant readiness probe
# Features:
#  - Polls root and /api/ endpoints
#  - Optional log phrase verification ("Starting Home Assistant")
#  - JSON output mode for CI integration
#  - Colored human-readable output (auto-disabled for non-TTY unless forced)
#  - Configurable inclusion/exclusion of checks
#
# Usage examples:
#   ./scripts_ready_check.sh --url http://localhost:8123
#   ./scripts_ready_check.sh --url http://localhost:8123 --timeout 300 --require-log --container hass-test
#   ./scripts_ready_check.sh --json --url http://localhost:8123 || echo "Not ready"
#   ./scripts_ready_check.sh --skip-api --url http://localhost:8123
#
# Exit codes:
#   0 success (all required checks passed)
#   1 timeout / failure
#   2 invalid usage

URL="http://localhost:8123"
TIMEOUT=180
INTERVAL=3
CONTAINER=""
REQUIRE_LOG=0
CHECK_HTTP=1
CHECK_API=1
JSON=0
COLOR_AUTO=1
FORCE_COLOR=0
NO_COLOR=0
LOG_PHRASE="Starting Home Assistant"

usage() {
  sed -n 's/^##\s\{0,1\}//p' "$0"
  exit 0
}

fail_usage() {
  echo "Usage error: $1" >&2
  echo "Run with --help for details" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --require-log) REQUIRE_LOG=1; shift ;;
    --log-phrase) LOG_PHRASE="$2"; shift 2 ;;
    --skip-http) CHECK_HTTP=0; shift ;;
    --skip-api) CHECK_API=0; shift ;;
    --json) JSON=1; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    --color) FORCE_COLOR=1; shift ;;
    -h|--help) usage ;;
    *) fail_usage "Unknown argument: $1" ;;
  esac
done

if ! [[ $TIMEOUT =~ ^[0-9]+$ ]]; then fail_usage "--timeout must be integer"; fi
if ! [[ $INTERVAL =~ ^[0-9]+$ ]]; then fail_usage "--interval must be integer"; fi

if [[ $CHECK_HTTP -eq 0 && $CHECK_API -eq 0 ]]; then
  fail_usage "Cannot skip both HTTP and API checks"
fi

# Color handling
if [[ $NO_COLOR -eq 1 ]]; then COLOR_AUTO=0; FORCE_COLOR=0; fi
if [[ -t 1 && $COLOR_AUTO -eq 1 || $FORCE_COLOR -eq 1 ]]; then
  GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; CYAN='\033[36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

deadline=$(( $(date +%s) + TIMEOUT ))
pass_http=0
pass_api=0
pass_log=0
attempt=0
start_ts=$(date +%s)

log() { [[ $JSON -eq 1 ]] && return 0; echo -e "$@" >&2; }

log "${CYAN}[*] Probing Home Assistant at${RESET} ${BOLD}${URL}${RESET} (timeout=${TIMEOUT}s interval=${INTERVAL}s)"
[[ $REQUIRE_LOG -eq 1 ]] && log "${CYAN}[*] Requiring log phrase:${RESET} '${LOG_PHRASE}'"

while (( $(date +%s) < deadline )); do
  attempt=$((attempt+1))
  now=$(date +%s)
  elapsed=$((now - start_ts))

  # Root HTTP check
  root_code=""
  if [[ $CHECK_HTTP -eq 1 ]]; then
    root_code=$(curl -fsS -o /dev/null -w '%{http_code}' "${URL}" || true)
    if [[ -n "$root_code" && $root_code != "000" ]]; then
      pass_http=1
    fi
  fi

  # API check
  api_code=""
  if [[ $CHECK_API -eq 1 ]]; then
    api_code=$(curl -fsS -o /dev/null -w '%{http_code}' "${URL%/}/api/" || true)
    # 200 = ready, 401 = starting but needs auth (acceptable), other codes = not ready
    if [[ "$api_code" == "200" || "$api_code" == "401" ]]; then
      pass_api=1
    fi
  fi

  # Log phrase
  if [[ $REQUIRE_LOG -eq 1 && -n "$CONTAINER" ]]; then
    if docker logs "$CONTAINER" 2>&1 | grep -q "$LOG_PHRASE"; then
      pass_log=1
    fi
  elif [[ $REQUIRE_LOG -eq 1 && -z "$CONTAINER" ]]; then
    log "${YELLOW}[warn] --require-log set but no --container provided${RESET}"
  fi

  ready=0
  cond_http=$(( CHECK_HTTP == 0 || pass_http == 1 ))
  cond_api=$(( CHECK_API == 0 || pass_api == 1 ))
  cond_log=$(( REQUIRE_LOG == 0 || pass_log == 1 ))
  if (( cond_http && cond_api && cond_log )); then ready=1; fi

  if (( ready == 1 )); then
    duration=$(( $(date +%s) - start_ts ))
    if [[ $JSON -eq 1 ]]; then
      jq -n --arg url "$URL" --arg elapsed "$duration" --arg root_code "$root_code" --arg api_code "$api_code" \
        --argjson pass_http $pass_http --argjson pass_api $pass_api --argjson pass_log $pass_log '{status:"ready",url:$url,elapsed_seconds:($elapsed|tonumber),http:{code:$root_code,pass:$pass_http},api:{code:$api_code,pass:$pass_api},log:{phrase:"'"$LOG_PHRASE"'",pass:$pass_log}}'
    else
      log "${GREEN}[OK] Home Assistant ready in ${duration}s${RESET} (attempt ${attempt})"
    fi
    exit 0
  fi

  if [[ $JSON -eq 0 ]]; then
    log "Attempt ${attempt} elapsed=${elapsed}s HTTP=${pass_http}/${CHECK_HTTP} API=${pass_api}/${CHECK_API} LOG=${pass_log}/${REQUIRE_LOG}"
  fi
  sleep "$INTERVAL"
done

duration=$(( $(date +%s) - start_ts ))
if [[ $JSON -eq 1 ]]; then
  jq -n --arg url "$URL" --arg elapsed "$duration" --arg root_code "$root_code" --arg api_code "$api_code" \
    --argjson pass_http $pass_http --argjson pass_api $pass_api --argjson pass_log $pass_log '{status:"timeout",url:$url,elapsed_seconds:($elapsed|tonumber),http:{code:$root_code,pass:$pass_http},api:{code:$api_code,pass:$pass_api},log:{phrase:"'"$LOG_PHRASE"'",pass:$pass_log}}'
else
  log "${RED}[FAIL] Timed out after ${duration}s (HTTP=${pass_http}/${CHECK_HTTP} API=${pass_api}/${CHECK_API} LOG=${pass_log}/${REQUIRE_LOG})${RESET}"
fi
exit 1
