#!/usr/bin/env bash
# Open (or bring to front) the automation Chrome window used by the booking
# agent, on the Doctolib login page. Run this whenever you are asked to log
# back in.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/chrome-profile"
PORT=9777
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
URL="https://www.doctolib.fr/"

if ! curl -s -m 2 "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
  "$CHROME" \
    --user-data-dir="$PROFILE_DIR" \
    --remote-debugging-port="$PORT" \
    --no-first-run \
    --no-default-browser-check \
    "$URL" >/dev/null 2>&1 &
  sleep 2
fi

# Chrome's per-profile process singleton forwards this URL to the running
# instance with the same profile and activates its window.
"$CHROME" --user-data-dir="$PROFILE_DIR" "$URL" >/dev/null 2>&1 &
