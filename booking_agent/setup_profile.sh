#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="$HOME/.doctolib-booking-agent/chrome-profile"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

mkdir -p "$PROFILE_DIR"

if pgrep -f -- "--user-data-dir=$PROFILE_DIR" >/dev/null 2>&1; then
  echo "Chrome is already running with profile $PROFILE_DIR."
  echo "Log in to doctolib.fr in that window if not already logged in, then run run_booking_agent.sh."
  exit 0
fi

"$CHROME" \
  --user-data-dir="$PROFILE_DIR" \
  --no-first-run \
  --no-default-browser-check \
  "https://www.doctolib.fr/login" &

echo "Chrome opened with the booking profile at $PROFILE_DIR."
echo "1. Log in to doctolib.fr in the window that opened (email/password or Google)."
echo "2. Once logged in, close that Chrome window. The session cookie persists in the profile."
echo "3. Then run booking_agent/run_booking_agent.sh to book."
