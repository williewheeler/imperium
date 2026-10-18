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

# Watch four AIs play each other in four panes of one window (no human player).
# Speed it up with + and - in the window (up to 32x), or start faster: just ai4 --speed=8
# Other options: --seed=N, --difficulty=difficilis, --terrain=snowy, --map=anulus, --size=small
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
    {{godot}} --headless --path . --script tests/net_test.gd -- host > ${TMPDIR:-/tmp}/imperium-host.log 2>&1 &
    sleep 2
    {{godot}} --headless --path . --script tests/net_test.gd -- join 127.0.0.1 > ${TMPDIR:-/tmp}/imperium-join.log 2>&1
    wait
    echo "--- host"; cat ${TMPDIR:-/tmp}/imperium-host.log; echo "--- join"; cat ${TMPDIR:-/tmp}/imperium-join.log
    grep -q "JOIN starting slot=1" ${TMPDIR:-/tmp}/imperium-join.log && echo PASS || { echo FAIL; exit 1; }

# Headless check of attacking, burning and destroying buildings, and of a people being defeated
siege-test:
    {{godot}} --headless --path . --script tests/siege_test.gd -- --nosplash --seed=42 --players=3

# Headless check that an AI wave marches on an enemy town and burns its buildings down
war-test:
    {{godot}} --headless --path . --script tests/war_test.gd -- --nosplash --spectate --seed=3 --size=small --map=continens --terrain=temperate

# Four AIs play each other fast (10x), headless, reporting every 150 game seconds: just ai-test 900
ai-test seconds="900" *args:
    {{godot}} --headless --path . --script tests/ai_test.gd -- --nosplash --spectate --terrain=temperate --size=small --map=continens --seed=3 {{seconds}} {{args}}

# Headless check of settlements: absorbing citizens, growing into a Town Center and a City Center
settlement-test:
    {{godot}} --headless --path . --script tests/settlement_test.gd -- --nosplash --seed=42 --players=3

# Headless check of farms: eight plots round a granary, one villager to a plot, a Large Farm at eight citizens
farm-test:
    {{godot}} --headless --path . --script tests/farm_test.gd -- --nosplash --seed=42 --players=3

# Headless check of the sparse start and of herds that breed and can be hunted out
herd-test:
    {{godot}} --headless --path . --script tests/herd_test.gd -- --nosplash --seed=42 --players=3

# Headless check of docks, fish and fishing boats
water-test:
    {{godot}} --headless --path . --script tests/water_test.gd -- --nosplash --seed=42 --players=3

# Headless check of the phrase table: both languages present, every key used in the code exists
phrases-test:
    {{godot}} --headless --path . --script tests/phrases_test.gd

# Play a whole game of AIs with no window and write it down: just sim 600 --seed=7 --out=game.replay
# (options: --seed --players --size --map --terrain --resources --difficulty --report=N --perf; see tools/sim_run.gd)
sim seconds="300" *args:
    {{godot}} --headless --path . --script tools/sim_run.gd -- --seconds={{seconds}} {{args}}

# Play a recorded game back headless and check it comes out the same, checksum by checksum
replay-check file:
    {{godot}} --headless --path . --script tools/replay_check.gd -- --replay={{file}}

# Watch a recorded game in the window (speed it up with --speed=8). Nobody plays: the commands come from the file.
replay file *args:
    ./run.sh --windowed --nosplash --replay={{file}} {{args}}

# Headless check of the person's driver (selecting, ordering, the keys) on a real game
person-test:
    {{godot}} --headless --path . --script tests/person_test.gd -- --nosplash --seed=42 --players=3

# Headless check of the headless client: what a player's view shows, hides and lets it do
view-test:
    {{godot}} --headless --path . --script tests/view_test.gd

# Headless check of determinism: two runs of one game agree, a replay of it agrees, a doctored replay does not
replay-test:
    {{godot}} --headless --path . --script tests/replay_test.gd

# Parse every script, and check that every member named on the simulation and on Main exists
lint:
    {{godot}} --headless --path . --script tools/lint.gd
    python3 tools/check_members.py

# Headless check of the command layer (ownership, payment, orders) on a real game
commands-test:
    {{godot}} --headless --path . --script tests/commands_test.gd -- --nosplash --seed=42 --players=2

# Redraw the art sheets from src/art/art.gd (overwrites assets/art/*.png!)
art:
    tools/export_art.sh
