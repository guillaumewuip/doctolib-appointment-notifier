#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <booking_url> [slot_hint] [--dry-run]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 3
fi

URL="$1"
shift
SLOT_HINT=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) SLOT_HINT="$arg" ;;
  esac
done

PROFILE_DIR="$HOME/.doctolib-booking-agent/chrome-profile"
PORT=9777
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/.doctolib-booking-agent/logs"
MODEL="${BOOKING_AGENT_MODEL:-zai/glm-5.3-flash}"
TIMEOUT="${BOOKING_AGENT_TIMEOUT:-300}"

fail() {
  echo "{\"outcome\":\"failed\",\"detail\":\"$1\"}"
  exit 3
}

LOCK_FILE="$HOME/.doctolib-booking-agent/running.pid"
mkdir -p "$(dirname "$LOCK_FILE")"
if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
  fail "another booking attempt (pid $(cat "$LOCK_FILE")) is still running"
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

ensure_chrome() {
  if curl -s -m 2 "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
    return 0
  fi
  "$CHROME" \
    --user-data-dir="$PROFILE_DIR" \
    --remote-debugging-port="$PORT" \
    --no-first-run \
    --no-default-browser-check \
    "about:blank" >/dev/null 2>&1 &
  local waited=0
  while (( waited < 15 )); do
    if curl -s -m 2 "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

if ! ensure_chrome; then
  fail "Chrome not reachable on CDP port $PORT after 15s"
fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/attempt-$(date +%s).log"

echo "Log: $LOG_FILE"

PI_COMPUTER_USE_CDP_PORT="$PORT" pi -p \
  --no-session \
  --no-skills \
  --no-prompt-templates \
  --no-mcp \
  --no-context-files \
  --model "$MODEL" \
  "@$SCRIPT_DIR/booking-prompt.md" \
  "BOOKING_URL=$URL SLOT_HINT=$SLOT_HINT DRY_RUN=$DRY_RUN" \
  >> "$LOG_FILE" 2>&1 &
PI_PID=$!

elapsed=0
while kill -0 "$PI_PID" 2>/dev/null; do
  if (( elapsed >= TIMEOUT )); then
    kill -TERM "$PI_PID" 2>/dev/null || true
    sleep 5
    kill -KILL "$PI_PID" 2>/dev/null || true
    wait "$PI_PID" 2>/dev/null || true
    fail "agent timeout after ${TIMEOUT}s"
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done
wait "$PI_PID" 2>/dev/null || true

OUTCOME_LINE="$(grep -E '^\s*\{"outcome"' "$LOG_FILE" | tail -1 || true)"

VALID="$(python3 -c '
import json, sys
try:
    o = json.loads(sys.argv[1])
except Exception:
    print("no"); sys.exit()
print("yes" if o.get("outcome") in {"booked","reached_confirmation","not_authenticated","slot_gone","failed"} else "no")
' "$OUTCOME_LINE" 2>/dev/null || echo no)"

if [[ -z "$OUTCOME_LINE" || "$VALID" != "yes" ]]; then
  fail "no outcome JSON from agent"
fi

echo "$OUTCOME_LINE"

case "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["outcome"])' "$OUTCOME_LINE")" in
  booked|reached_confirmation) exit 0 ;;
  not_authenticated) exit 1 ;;
  slot_gone) exit 2 ;;
  *) exit 3 ;;
esac
