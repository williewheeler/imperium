# Performance: stutter investigation

Status: **partly done.** The big stalls are fixed; a residue of small hitches is unexplained and needs
testing on the player's own machine. Follow-up steps are at the end.

## The report

Animation "stutters a lot, as if there is GC going on", first noticed on the rain animation.

## Is it garbage collection?

No. GDScript has no tracing garbage collector. `RefCounted` objects (units, buildings, maps) are freed the
moment nothing refers to them, and nodes are freed explicitly with `queue_free()`. Allocation can cost a
little, but there are no random collection pauses. A hitch from allocation would show as a jump in object
count or memory at the stall; none of the stalls below did.

## Tools added

- **F3 in game** (`src/ui/frame_monitor.gd`): live frame time (average, 99th percentile, worst), script,
  render-CPU and GPU time, object / node / orphan counts, memory, draw calls, stall count and the last stall.
- **Stall log**: every frame over 24 ms is appended to `user://stutter.log` (macOS:
  `~/Library/Application Support/Godot/app_userdata/Imperium/stutter.log`), with the three slowest parts of the
  game code in that frame. Columns are in the file's header line.
  - `--stutter` logs from the start without the panel; `--stutter=all` logs every frame.
- **Per-part timing** (`src/core/perf.gd`): `Perf.start()` / `Perf.stop("name", t0)` marks. With `Perf.trace` on
  (the monitor turns it on when logging) each frame's time per part is kept. Marked: pan, ais, unit logic
  (split per state and player, e.g. `unit_explore_p3`), separate units, buildings, world tip, fog, hud,
  scenery streaming, tree sway, unit views, pathfinding, `set_path`, `retarget scan`.
- `--perf` (older): average and worst frame time and per-part milliseconds over 400 frames, then quits.

Caveats about the numbers: Godot's `TIME_PROCESS` monitor updates about once a second, so the "script" column
is only a rough guide; the per-part marks are the reliable attribution. GPU time reads 0 on the OpenGL
compatibility renderer.

## Test setup

iMac, AMD Radeon Pro 560X, macOS 24.6, Godot 4.7.2, renderer `gl_compatibility` (OpenGL 4.1), v-sync on.
A virtual machine was using ~70% of a CPU in the background and the test window was unfocused, so absolute
numbers are pessimistic and noisy. Runs: `godot --path . -- --seed=3 --nosplash --windowed --weather=rain --stutter`
(about 45 s each; `--weather=clear` for comparison).

## Findings

Baseline: median frame about 8.8 ms, p95 about 14 ms. Rain and clear weather were the same (153 draw calls,
render CPU ~2 ms). **The rain shader is not the cause.** (The raindrop ripples were stepped at 8 pictures a
second by design, which looks jerky; raised to 15, a cosmetic change.)

The real stalls were CPU time in GDScript, found by the per-part marks:

| Cause | Where | Cost per hit | Fix |
|---|---|---|---|
| Choosing where to explore | `Main._explore_next`: built a list of every unseen spot (thousands) and sorted it with a GDScript comparator, every time an explorer arrived | 130 to 280 ms, about once a second with two explorers | Keep only the nearest 8 while scanning (`EXPLORE_TRIES`), no sort |
| Looking for the next tree | `Main._retarget`: scanned **every deposit on the map** (tens of thousands of forest tiles) when a gatherer's target ran out | 250 to 600 ms | Look only at the tiles within 12 of the unit |
| AI searching for a deposit | `AI._nearest_deposit`: for each ring it walked the whole square and skipped the inside, so O(R^3) | 20 to 40 ms | Walk only the ring's cells (`GameMap.ring`, now public) |

These hit the player too: AIs always exist, and `_retarget` runs for the player's villagers.

After the fixes: worst frame in the same run 45 ms (was 680 ms). AI behavior unchanged (a 400 s headless
simulation still ends with 9 villagers each) and that simulation runs much faster.

## Still open

1. **About 4% of frames take about 25 ms (v. 8.8 median) with under 8 ms of game code in them.** Of 143 stalls
   in one 42 s run, 114 were like this. They are irregular (not on a timer), involve no change in object count
   or memory, and are not rain related. Not explained. Candidates: the busy test machine and unfocused window;
   v-sync / display pacing; the OpenGL compatibility renderer on an older AMD GPU; texture swaps when the wind
   changes every tree's sprite.
2. **Remaining one-off CPU hitches of 20 to 40 ms**: an AI's think step (`ais`, 20 to 38 ms), a unit
   finishing a building (`_on_complete`, about 30 ms), an explorer's scan (about 8 ms each), tree sway when a
   gust flips every tree (up to 11 ms).
3. **Startup**: the first 3 to 10 seconds have stalls of 0.5 to 3 s while the world and the first scenery
   chunks are built. Normal runs show a loading screen over most of it; not measured separately.
4. **Not tested**: the full-screen native resolution on a high-density display (the ground shader runs per
   physical pixel, so a very large window could be GPU-bound; my size tests did not take effect, so there is
   no valid comparison), larger maps (400 and 480), 8 players, late-game unit counts, and Metal or the
   Forward+ renderer.

## Follow-up

1. **Get data from the player's machine.** Play a normal game, press F3 when it stutters, then send
   `stutter.log`. The slow part named in each line says whether it is game code (fixable here) or "none", which
   points at rendering or display pacing.
2. **If stalls show no game code**, try in this order: run with `--rendering-driver metal` or switch the project
   to the `mobile` renderer (Metal on macOS) and compare `stutter=all` logs; try v-sync off to see whether the
   25 ms frames vanish (pacing); play in a smaller window or at higher `--zoom` to test GPU fill rate. If the
   ground shader is the limit, render the world at art-pixel resolution in a `SubViewport` and scale it up with
   nearest filtering (cuts fragment work by the pixel-zoom squared).
3. **Remove the remaining CPU spikes** (item 2 above): spread an AI's thinking over several frames, make
   building completion cheaper, and swap tree textures a few at a time instead of all at once.
4. **Look for other full-map scans in per-frame or per-order code.** The three fixed bugs share one shape:
   O(map) or O(n log n) work with a GDScript comparator inside code that runs often. Grep for loops over
   `map.deposits`, `map.w * map.h` loops outside map generation, and `sort_custom` on large arrays.
   `Main._explore_next` still scans the whole map every call (about 8 ms); an outward search would be cheaper.
5. **Guard against regressions.** Add a headless benchmark (a seeded 400 s simulation with 7 AIs reporting
   worst per-part time) that fails if any part exceeds a budget, e.g. 16 ms; the `r.gd` simulation harness is a
   starting point.
6. **Test list for the next pass**: sizes Magna and Maxima, 8 players, Archipelago and island maps (explorers
   find unreachable spots there), 15 minutes of simulated play, and a map with the Hilly and Wooded grounds.
