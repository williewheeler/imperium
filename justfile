# Recipes for running and testing Imperium. `just` lists them; extra args pass through to the game,
# e.g. `just dev --map=anulus --players=6` or `just shot out.png --town`.

godot := env_var_or_default("GODOT", "godot")

default:
    @just --list

# Play (full flow: scroll, title, game)
run *args:
    ./run.sh {{args}}

# Windowed, no opening scroll, a fixed map: the quick edit-and-look loop
dev *args:
    ./run.sh --windowed --nosplash --seed=42 {{args}}

# Register new class_name scripts and assets (needed after adding one)
import:
    {{godot}} --headless --path . --import

# Screenshot of a scene after a while: just shot out.png --town --era=1
shot file *args:
    {{godot}} --path . -- --windowed --shot={{file}} --shot-frame=60 {{args}}

# Two armies a few tiles apart
skirmish *args:
    ./run.sh --windowed --nosplash --skirmish {{args}}

# A built-up town round the Forum
town *args:
    ./run.sh --windowed --nosplash --town --reveal {{args}}

# Frame-time report over 400 frames
perf *args:
    {{godot}} --path . -- --windowed --nosplash --perf {{args}}

# Watch four AIs play each other in four panes of one window (no human player)
ai4 *args:
    ./run.sh --windowed --nosplash --spectate --terrain=temperate --size=1600x900 {{args}}

# Multiplayer: host a lobby in the title flow (127.0.0.1:7777)
host *args:
    ./run.sh --windowed --splash --lobby=host {{args}}

# Multiplayer: join a host (default: this machine)
join addr="127.0.0.1" *args:
    ./run.sh --windowed --splash --lobby=join:{{addr}} {{args}}

# Multiplayer: both copies on this machine; the host starts as soon as the joiner is ready
mp:
    ./run.sh --windowed --splash --lobby=host --autostart --size=1000x620 & sleep 3; ./run.sh --windowed --splash --lobby=join:127.0.0.1 --size=1000x620; wait

# Headless check of the networking layer (host and client in two processes)
net-test:
    #!/usr/bin/env bash
    set -euo pipefail
    {{godot}} --headless --path . --script tools/net_test.gd -- host > ${TMPDIR:-/tmp}/imperium-host.log 2>&1 &
    sleep 2
    {{godot}} --headless --path . --script tools/net_test.gd -- join 127.0.0.1 > ${TMPDIR:-/tmp}/imperium-join.log 2>&1
    wait
    echo "--- host"; cat ${TMPDIR:-/tmp}/imperium-host.log; echo "--- join"; cat ${TMPDIR:-/tmp}/imperium-join.log
    grep -q "JOIN starting slot=1" ${TMPDIR:-/tmp}/imperium-join.log && echo PASS || { echo FAIL; exit 1; }

# Headless check of the phrase table: both languages present, every key used in the code exists
phrases-test:
    {{godot}} --headless --path . --script tools/phrases_test.gd

# Headless check of the command layer (ownership, payment, orders) on a real game
commands-test:
    {{godot}} --headless --path . --script tools/commands_test.gd -- --nosplash --seed=42 --players=2

# Redraw the art sheets from src/art/art.gd (overwrites assets/art/*.png!)
art:
    tools/export_art.sh
