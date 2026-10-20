#!/usr/bin/env bash
# Run the Doctolib checker with macOS notifications + Reminders.
# Uses nix for a Python 3.11+ environment with requests.

set -euo pipefail

cd "$(dirname "$0")"

exec nix-shell \
  -p "python3.withPackages (p: [ p.requests ])" \
  --run "python3 doctolib_checker.py --notification --reminder"
