#!/usr/bin/env bash
# Run Imperium. Extra args pass through to the game, e.g. ./run.sh --seed=42
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
[ -x "$GODOT" ] || { echo "Godot not found. Install with: brew install --cask godot (or set GODOT=/path/to/godot)" >&2; exit 1; }

# First run (or after adding new class_name scripts): register global classes.
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1

exec "$GODOT" --path . -- "$@"
