#!/usr/bin/env bash
# Regenerates the art sheets, the manifest and the Godot TileSet from the drawing code in src/art/art.gd.
# NOTE: this overwrites assets/art/*.png, so hand edits to the sheets will be lost.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
"$GODOT" --headless --path . --script tools/export_art.gd
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . --script tools/build_tileset.gd
