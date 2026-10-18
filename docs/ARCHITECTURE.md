# IMPERIVM — architecture

How the code is put together. For what the game is and what is built, see [`DESIGN.md`](DESIGN.md).

Status key as in DESIGN.md: **built**, **decided**, **proposed**, **open**.

---

## Layout

Code is under `src/`; Godot has no required layout, and scripts find each other by `class_name`, so files
can move between folders freely. Only `res://` paths (the scene, shaders, assets) name locations.

The folders follow the diagram below. Each box in it is named in the table after the layout, with where it is
in the code, or marked as not built.

| Folder | Role |
|---|---|
| `src/sim/` | **The simulation**: everything that decides what happens, and nothing that shows it. No scene, no window, no input, no clock. At the top, `Simulation` (the game loop, `step()`, and the owner of the parts) and `SimConfig` (the choices that shape a game). |
| `src/sim/state/` | The **game state**, inert data: `Unit`, `Building`, `Deposit`, `GameMap` and `TerrainGen` (the ground), `Fog` (what each people has seen), and `Defs` (the rules' tables). |
| `src/sim/systems/` | The **game systems**, which act on the state: `Commands`, `Orders`, `Movement` (with `UnitGrid`), `Economy`, `Production`, `Eras`, `Vision`, `Wildlife`, `UnitBehavior`, `Combat`, `Placement`, `Roads`, `Victory`, `WorldSetup`. |
| `src/ai/` | The computer players: `AI` and one class per goal. See *The AIs*. |
| `src/replay/` | `Replay` (the file), `Recorder`, `Replayer`. See *Headless play and replays*. |
| `src/ui/` | **The UI, for humans only**: the HUD, menus, lobby, title and opening scroll. |
| `src/ui/views/` | Drawing the state: `World` and the unit, building, ground, fog, weather and overlay views, the minimap, `Iso` (tile and screen maths), `Weather` (cosmetic). Read the simulation, never change it. |
| `src/ui/controls/` | `Person` (mouse, keys, selection, command targeting) and `CameraRig`. |
| `src/app/` | The application: `Main` (starts the world, wires the parts, and is the **tick driver** in play) and the debug scaffolding (`DebugModes`, `EraPreview`). |
| `src/net/` | Networking (`NetSession`, the lobby so far; later the channels). |
| `src/art/` | Sprite drawing code; baked into PNG sheets by `tools/`. |
| `src/infra/` | `GameSettings` (what the player chose; kept in `user://settings.cfg`) and `Perf` (the profiler). |
| `src/audio/`, `src/text/` | `Music`; `Phrases` and `Latin` (the game's words). |
| `tools/` | Headless runners and dev tools (`sim_run` is the headless tick driver; `replay_check`, `lint`, art export). |
| `tests/` | The headless checks, one script each (`just commands-test`, `just replay-test`...). |

### From the diagram to the code

| Box in the diagram | In the code |
|---|---|
| Person | the person |
| Views | `src/ui/views/`, and the HUD's readouts in `src/ui/` |
| Controls | `src/ui/controls/` (`Person`, `CameraRig`), and the HUD's buttons in `src/ui/` |
| AIs | `src/ai/` |
| Headless client | not built (today the UI and the AIs read the `Simulation` directly) |
| View channel, Command channel | not built (`src/net/` will hold them; today `NetSession` is the lobby only) |
| View publisher, Command receiver | not built (today the simulation's signals reach `Main`, which shows them) |
| Command interface, Command queue | not built (today `Commands.submit`, which validates and applies at once) |
| Game loop | `Simulation.step()` in `src/sim/simulation.gd` |
| Game state | `GameState` (`src/sim/state/game_state.gd`), held as `Simulation.state`: the map, units, buildings, stocks, fogs, tick, rng, eras, road plans, shots in flight, who has fallen. Inert; see *Known debts* for what is still not |
| Game systems | `src/sim/systems/`: they hold no game state of their own (only the `Movement` grid, which is rebuilt each tick) |
| Tick driver | `Main._run_sim` (`src/app/main.gd`); `tools/sim_run.gd` and `tools/replay_check.gd` headless |
| Recorder | `src/replay/recorder.gd` (taps `Commands.submitted` today) |
| Replayer | `src/replay/replayer.gd` (calls `Commands.submit` today) |

### How the parts depend on each other

The simulation depends on none of the client: it tells the client what happened through signals, and the client
reads its state to draw it.

![How the parts depend on each other](architecture.svg)

*The key is in the picture. The client is `Views` (the world, the minimap, the HUD's readouts) and `Controls` (the mouse
and keys, which `Person` handles, and the buttons); yellow boxes are proposed, not built.*

**The end state (proposed; the picture above).** None of the yellow boxes exist yet. They are where the design is going:

- **A headless client per player, human or AI.** It holds the player's fog-filtered model of the world and takes their
  commands. The human UI (`Views` and `Controls`, with `Person` as the thing that handles the mouse and keys) is a
  front end wrapped round it, and an AI is another. So a human and an AI see and do exactly the same things, and
  neither can look at the real state. (Today the AIs read `Simulation.units` and the like directly, and only
  discipline keeps them to their own fog.)
- **Two asynchronous channels between client and host**, each an in-process queue or `NetSession`: the **command
  channel** (client to host) and the **view channel** (host to client). On the host a *command receiver* takes commands
  off the first, and a *view publisher* sends each player what it may see, from the game state, on the second.
- **A command interface and queue in the simulation.** Commands from every source enter through the interface, which is
  the only thing that writes to the queue. When a command arrives is up to the world; at the interface it is stamped
  with the tick it is due (a live command for the next tick, a lockstep peer's for an agreed one, a replay's for the tick it
  was recorded at) and its place in the order. The queue holds them in that order. That is where an inherently
  asynchronous transport meets a simulation that consumes input at fixed ticks, and it is the one place where
  the nondeterminism ends.
- **The game loop is the heart, a little like a rules engine.** The **game state** is inert data; the loop invokes the
  **game systems**, which read it and update it. Each tick (one step of the *tick driver*, which turns wall-clock time into ticks): drain
  the commands now due from the queue and have the **game systems** validate and apply them; run the systems over the state, which is what makes the world
  move with nobody issuing anything (a fire burns down, a dog walks towards its goal); and let the state publish
  what changed. The clock reaches the world through the loop, and commands reach it through the drain.
- **Recorder and Replayer are tools, not part of the core, and two sides of one coin.** Whatever is tapped on the way out is what
  is driven on the way back, so that nothing between them can drift. That point is the command interface: it is where
  everything the world tells the simulation arrives, already stamped with its due tick and order. The Recorder writes each
  command there, with a checksum every 5 s. The Replayer loads the recording back through the interface, with the people and AIs
  switched off, so the queue, the drain and the validation run exactly as they did live. A game is then its config (the seed and
  settings) plus that list, nothing more. Everything inside the loop, such as a gatherer picking a new tree or a path being
  worked out, is recomputed, never recorded. Validation happens when a command is applied, so the interface does not
  know its answer (invalid commands are recorded too, and rejected the same way on replay); recording the answers as well, as a check, would be a passive tap in the loop, and the checksums catch the rest. Recording
  commands, not their effects, keeps this compatible with lockstep, where machines exchange commands.

Two consequences. A command no longer gets an answer at once ("err.cant_afford" is flashed in the same frame today), so
the `Controls` show a refusal when it comes back and the AIs, whose `buy` logic reads the answer, need late answers or a
synchronous "would this be allowed?" check. And for a game to stay the same game from the same seed, the host has to
deliver each tick's update to every client and collect their commands in a fixed order (by player), inside the tick
boundary; the cost is that an AI reacts a tick late.

## Players, drivers and commands  (**built**)

The central rule: **a player acts on the game only by submitting a command, and the game cannot tell who
submitted it.**

```
 person (mouse, keys, selection)  ─┐
 AI (computer player)          ─┼─►  Commands.submit(cmd) ─►  game state (units, buildings, stocks)
 replay (a recorded game)      ─┤        validate · pay · apply
 remote peer (network)  [decided] ─┤
 test script                   ─┘
```

- **Game state** is the `Simulation`'s units, buildings, map, per-player `stocks` and `fogs` (both indexed by
  owner). A player is just an owner number; the simulation has no notion of a "local" player. (`Main.LOCAL`
  is the player at this keyboard, and only the client knows it.)
- **A command** is a plain `Dictionary` of numbers, strings and tiles, with `type` and `owner`; units and
  buildings are named by `id` (`Unit.id`, `Building.id`), never by reference. That makes a command
  serializable, so it can be sent over the network, recorded, or written by hand in a test. The set of
  commands and their fields is listed at the top of `src/sim/commands.gd`.
- **`Commands.submit(cmd) -> String`** is the only gate. It checks that the named units and buildings exist
  and belong to `owner` (anything else is trimmed away), checks the rules (affordable, population room,
  placement, era), pays, and applies. It returns `""` on success or a phrase key on refusal (`"err.cant_afford"`; see *Text*), and it never
  touches the selection, mouse, HUD or markers. It emits `submitted(cmd, err)` for everything it is given: that is how
  a game is recorded.
- **Drivers** decide what to ask for:
  - The person's driver is `Person` (`src/ui/controls/person.gd`). It turns clicks and the selection into commands, flashes a refusal, and keeps
    purely interface state (markers, placement mode, attack-move mode) to itself.
  - `AI` (`src/ai/ai.gd`, see *The AIs* below) thinks about once a second and submits commands as its owner through its
    own `do`. It sees the world through its own `Fog`, so it knows only what its people have seen.
  - `Replayer` gives the simulation the commands a recording holds, at the ticks they were given.
- **What is not a command.** Things the simulation does on its own are not player intent and call the order
  functions directly: a gatherer finding a new tree, a fighter picking a fight (`Combat`), a builder
  finishing and going idle. Scripted setup and the `--showcase`/`--demo` debug modes also place and order
  things directly; that changes the game without a command, so a game played with them cannot be replayed (see `taint` below).
- **What the simulation says back** is signals, never calls: `notice(owner, key)` (a message for one player),
  `building_completed`, `building_destroyed`, `era_reached`, `people_fell`, `game_won`, `tile_changed`,
  `road_changed`. `Main` hears them and shows them to the person they concern.

Adding a new action: add a branch in `Commands.submit` and a line in its header comment, make `Person`
and (if the AI needs it) `AI` call it, and add a case to `tests/commands_test.gd`.

## Time and determinism  (**built**)

`Simulation.step()` moves the game on by exactly one **tick**, 1/30 second of game time, whatever the frame
rate. `Main` keeps a running total of real time (already scaled by the game speed) and takes as many ticks as
it holds; the views draw units a fraction of the way between where they stood at the start of the last tick
and where they stand now (`Unit.prev_pos`, `Main.sim_alpha()`), so motion stays smooth at 60 frames a second.
A headless run just calls `step()` as fast as it can.

**The clock.** World time is only the tick count (`Simulation.time()` is `tick x 1/30 s`); the simulation never reads the wall
clock. A *tick driver* outside it decides how many ticks to run for a slice of real time: `Main` in play (one tick
per 1/30 s, more when fast-forwarding, none when paused), the headless runner as fast as it can, `Replayer` up to the
recording's last tick. The size of a tick never changes, so "twice as fast" is twice as many ticks, never bigger steps.

The simulation is **deterministic**: given the same `SimConfig` (the seed and the choices that shape the
world) and the same commands at the same ticks, it plays out the same, tick for tick. That is what makes
replays possible, and it is what lockstep multiplayer will need. It holds because of these rules, which any
change to `src/sim/` and `src/ai/` has to keep:

- **Randomness** comes only from seeded generators: the map's (`TerrainGen`, `GameMap`), the rules' (`Simulation.rng`,
  used by `Wildlife`), and one for each AI (`AI.rng`). The AI's is separate on purpose: an AI's decisions end up in the
  record as commands, so a replay (which has no AIs) must not depend on the dice they rolled. No `randf()`, `randi()`
  or `shuffle()` on the global generator, anywhere in the simulation.
- **No wall clock, frame rate, window, input, scene tree or settings screen.** The simulation reads `Defs` and the
  option tables of `GameSettings`, never the player's saved choices: those reach it only through `SimConfig`.
- **Numbers are per simulation, not global.** Unit and building ids, the eras, the town names all belong to one
  `Simulation`, so two can run in one process (`tests/replay_test.gd` does) and a replay's ids match the original's.
- **Commands are applied between ticks** (a person's) **or at the start of one** (the AIs'), in the order given.
  `Replayer` puts a recording's commands at the same points, so a command always sees the same game.
- **Everything the player should hear or see is a signal.** The simulation never calls the HUD.

`Simulation.checksum()` is a SHA-256 of the whole game as it stands (tick, rng state, stocks, eras, every unit and
building with its position and health, every deposit, every fog). Two games that have played the same have the
same checksum. It is exact to the bit, so it also demonstrates that the arithmetic repeats; this is verified on one
machine and one build of Godot, and not across platforms.

Where the nondeterminism is: when a command *arrives* (the network, the AIs' timing) is up to the world. What the
simulation does with it is not, once it is drained from the command queue at a tick boundary in a fixed order. Recording
the drained sequence (each command with the tick it was applied at) therefore pins the game down, whatever order things
arrived in. Today there is no queue, so commands are applied as they are submitted, between ticks or at the start of one,
which comes to the same thing.

Two things change the game *without* a command, and so are not replayable: the debug aids (`M` lays the map open,
`E` jumps through the eras, and the scene flags `--town`, `--demo`, `--skirmish`...). They call `Simulation.taint(why)`;
a recording notes it, and a replay that then strays says why.

## Headless play and replays  (**built**)

```
just sim 600 --seed=7 --out=game.replay      # a whole game of AIs, no window, as fast as the machine allows
just replay-check game.replay                # play it back with the AIs off; every checksum must match
just replay game.replay --speed=8            # watch it in the window (nothing is played: the commands come from the file)
just replay-test                             # determinism and replay checks (tests/replay_test.gd)
just lint                                    # parse every script and check every member named on the simulation exists
```

`tools/sim_run.gd` builds a `SimConfig` from its flags (never from the saved settings), a `GameMap` and a
`Simulation` with no human player, attaches a `Recorder`, and calls `step()` in a loop. Nothing of the client
is loaded. `tools/replay_check.gd` is the same with a `Replayer` in place of the AIs. A small game runs at
around 8 to 25 times real time; the cost is mostly units steering round one another (see *Known debts*).

A game played by a person is recorded the same way: `./run.sh --replay-out=game.replay` writes the commands
the person and the AIs give and a checksum every five seconds, and the file is good even if the game is quit
part way. `./run.sh --replay=game.replay` plays it back in the window with the same views and interface as a
live game (input is switched off) and prints whether it held when it ends.

The file (`src/replay/replay.gd` has the details) is text, one record to a line:

```
IMPERIVM-REPLAY 1
["head", {"config": {"seed": 3, "map_type": "continens", ...}, "view": {"colors": [...]}, ...}]
["cmd", 0, {"owner": 1,"tile": Vector2i(33, 39),"type": "gather","units": [6]}, ""]   tick, command, the game's answer
["chk", 150, "5f0c9a77e8d2b413"]                                                      tick, checksum
["end", 18000, "d2f74fa69bea350e"]
```

A replay is a few tens of kilobytes for ten game minutes. It records what was *decided*, not what happened, so
it is small and stays valid when the code that carries commands out is fixed, as long as the fix is not meant to
change what happens: when it is, old recordings stop matching (a checksum differs), and that is the point of them.

## Multiplayer today  (**built**: lobby only)

`NetSession` (`src/net/net_session.gd`, ENet and RPC, a node at `/root/NetSession`) runs the lobby: hosting,
joining, the roster, ready flags, and handing every machine the same settings, world seed and slot. Each
machine then builds the same world. After that **play is not synchronized**; commands are not yet sent
between machines. See DESIGN.md for the lobby itself.

What is in place for it: the command layer, a fixed tick, a deterministic simulation and a checksum to detect
desynchronization. What is missing is the exchange itself: each machine sends its person's commands stamped with a
future tick, every machine runs `Commands.submit` for all of them at that tick (as `Replayer` does), and
they compare checksums now and then. The choice between that (lockstep) and a host that runs the one simulation
and sends state back is still open, but the first no longer waits on the simulation.

## Known debts

- **Steering is the cost of a tick.** `Movement` checks each walker against every other unit (avoidance, detours,
  "is this spot taken", separation), so a tick costs O(units²). It is most of the time of a headless run and
  would be cut by a spatial grid.
- **`GameSettings` is two things:** the tables of options the rules read (map types, sizes, terrains, difficulties) and the
  player's saved preferences (colors, volume, speed). The simulation reads only the tables and gets everything else
  through `SimConfig`; the tables should move out to where `Defs` is.
- **The state is inert, with exceptions.** `GameState` holds everything the game is, and the systems keep nothing between ticks. What is left over: `Simulation` still has `add_unit`, `add_building` and `destroy_building`, which change the state and belong to a system (`Production`); `Building` holds a reference to `Eras`; the AIs' own memory (`AI.blocked`, `scouts`, `wave`...) lives in the AI objects, not in the state; and the entities carry the drawing state below.
- **Entities carry a little drawing state:** `selected`, `targeted`, `hit_flash`, `bar_t`, `sdir`, `walk`, `anim` on
  `Unit` and `Building`, and `Movement` computes the facing on the isometric screen. None of it is read by the rules (and none is
  in the checksum), but it belongs to the views.
- **`Fog` keeps a picture of itself** for the players whose fog is drawn (`Simulation.drawn_fogs`), and `Fog.show_all`
  (the `M` key) changes what the simulation sees. The picture belongs to `FogView`, and "see everything" to the
  view.
- Eras are per player (`Eras`), but the interface follows the local player's era alone (`Main.era`).
- The views are still tied to one local viewer in normal play (`game.fog`, "owner 0 is mine"). The spectator
  gets per-AI views with a parallel path (`viewers`, layers) rather than a viewer passed through every view;
  a single `Viewer` object would unify the two.
- Drivers read raw `Simulation.units` and `buildings`. The `AI` filters by its own fog by discipline, not
  by construction. A per-player view (fog-filtered queries) would enforce it, and is what a remote client
  would receive.
- Saved games are not built. The pieces are there (the whole state is plain data), but a replay can only begin from the start.

## The AIs  (**built**)

`src/ai/`: an `AI` plays one people through the same `Commands` as a person, seeing only its own `Fog`. What
it does is organized as **goals** (`AIGoal`, one file each), not one long script:

| Goal | What it is for |
|---|---|
| `WorkersGoal` | idle villagers go to the resource they are most short of (its usual share, less what is in store); hands move off a glut onto what has run out |
| `GrowthGoal` | villagers at every Town or City Center (Settlements cannot), houses (aqueducts later) before it runs out of room, fields at each town, a storehouse by the woods, vineyards in Era II |
| `ExploreGoal` | scouts (one, then two or three while the map is mostly unseen): it has to find land, resources and enemies |
| `ExpandGoal` | new Settlements: the richest explored ground a good way from its own and everyone's towns, once it has the people |
| `PopulateGoal` | sends villagers into its Settlements (15 to become a Town Center) and, with people to spare, its Town Centers (30 to become a City Center) |
| `MilitaryGoal` | an army in proportion to its villagers (barracks as it grows, a stable, counters to what it has seen) |
| `AttackGoal` | waves, attack-moving at the nearest enemy building it has explored; a force cut to 40% falls back |
| `DefendGoal` | idle fighters march at enemy fighters near its buildings; a far-off wave is called home if needed |
| `FishingGoal` | a dock on the shore beside fish near its towns, a few boats, kept at the fish |
| `AdvanceGoal` | saves for and begins the next era once its requirements are met |

`AI.towns()` are the buildings that make villagers (Town and City Centers); `AI.hubs()` also includes Settlements,
which take resources and house people. Each think, every goal says how pressing it is (`priority()`), and they act in that order. A goal that cannot
yet afford what it wants **reserves** the resources (`AI.reserve`, `buy`, `place`) once it is within half of
them, so goals further down leave them alone: that is how an AI saves for a Town Center or an era while still
feeding its people. Eras are per player (`Eras`, `Simulation.era_of`), so each AI advances by itself and its buildings take
on its own era's look. `tests/ai_test.gd` (`just ai-test`) plays four AIs against each other at 10x and
reports towns, era, army, exploration and kills every 150 game seconds.

## Placement and roads  (**built**)

Two small classes of the simulation own the ground rules, each holding a reference to the `Simulation`:
`Placement` (`building_at`, `rects`, `find_site`, and `error`, the reason a building can't go on a tile) and
`Roads` (`plans`, the tiles paid for and waiting to be paved and who is on each; `tile_error`,
`assign_work`, `release`, `finish_tile`; and `Roads.line` for dragging out a road). `Commands`, `AI`,
`Combat` and the views call them as `sim.placement` and `sim.roads`. Pathing is `Orders.set_path`, and a tile that
changes (a road paved) is announced by the simulation's `road_changed` signal, which the world view listens to.

## Combat, destruction and victory  (**built**)

`Combat` owns fighting: units attack units, or buildings (`Unit.atk_building`; `order_attack_building`).
Damage to a building goes through `Combat.hurt_building`, and fire (`update_buildings`) is part of the same
rules, not of the views. When a building falls `Simulation.destroy_building` removes it from the game and emits
`building_destroyed`; the **view** decides how that looks (`World` keeps the burning building up for a few
seconds, then spawns `RuinView` and `RuinFlames`). `Victory` (once a second) decides who is still in the
game and burns the buildings of a people that has fallen. Player actions reach it only through
`Commands` (`attack_building`).

## Scaffolding that is not the game  (**built**)

`DebugModes` (`--demo`, `--showcase`, `--skirmish`, `--town`, ... and the headless `--report`) and
`EraPreview` (the E key, which dresses a fake town for each era) hold code that sets scenes up for looking
at. They are kept out of the simulation, in `src/app/`, because none of it is the rules. `EraPreview.place_display_army` also puts a
few non-population "display" soldiers by the first town in a normal game; it is a placeholder.

## Text  (**built**)

The simulation never produces display text. `Commands`, `Placement`, `Roads` and `Orders` return or pass
**keys** (`err.no_route`), and a client turns a key into words: `Hud.flash_key` looks it up in `Phrases`
(`src/text/phrases.gd`), which holds each message's Latin and English together. That keeps rules separate
from language, so an AI, a test or a remote client can act on a key without parsing a sentence.
Names of buildings, units, resources and eras stay as data in `Defs`; one-word labels and text made up at
the point of use (`"Aetas %s"`, panel readouts) stay where they are drawn. `Latin.t` only applies the
lettering (capitals, V for U). See `LATIN.md` for the vocabulary.

## Watching AIs: the spectator  (**built**)

`just ai4` (or `--spectate`) starts a game with no human: all four players, the first included, are AIs
(`WorldSetup._make_ai`), and the window shows four panes (`src/ui/spectator.gd`).

- **One world, four cameras.** Each pane is a `SubViewport` that shares the main viewport's `World2D`, so
  every pane draws the same scene nodes through its own `Camera2D`. The main window itself draws only
  the panes: its `canvas_cull_mask` is set to a layer the world is not on. The panes render at the screen's
  physical resolution, so the pixel art stays crisp.
- **The views know about several screens.** `World.view_rects()` returns the rectangles being looked at (one
  normally, one per pane when spectating); chunk streaming and unit/building culling use all of them.
- **Each pane shows its own AI's fog.** The AIs' fogs (`Simulation.fogs[owner]`, the same ones the AIs decide from)
  are drawn, one `FogView` per pane. One scene can look different in each pane through **visibility
  layers**: a pane's `SubViewport` has a cull mask of the shared world (bit 1) plus its own bit
  (`Spectator.pane_bit`). A pane's fog overlay sits only on its bit, and `World` puts each unit and building
  on the bits of the panes whose AI can see it (`_seen_by`, `_explored_by`), so a unit is drawn only where
  that AI sees it. Projectile views are per pane for the same reason. Items inherit "all parents must share
  a layer", so only the top node of a unit or building is set.
- **Each pane has a minimap** (`Minimap` with its own `fog`, `viewer` and outline), inked only where that AI
  has seen. The AIs see little early on, so it starts as a speck around their town.
- **Panes** follow the AI's town, or the army it has sent out (`AI.focus()`); drag to look around, wheel to
  zoom, F to follow again, Q to quit. The text strip is `AI.summary()`: people, villagers, soldiers,
  population, stocks, and what it is doing (a `spec.*` phrase).
- The normal HUD is built but hidden, and input to `Main` is switched off. `Main.fog` is a view of its own that shows
  everything and is not drawn (nobody plays the first town: `Simulation.fogs[0]` is the first AI's).

## Weather and fog

Weather (`src/ui/views/weather.gd`) is cosmetic: a small state machine that drives `WeatherView`, the ground
shading and the music's mood. It does not affect play, and is not worth a module of its own. Fog (`Fog`,
in `src/sim/state/`) is different: it is per-player simulation state (`Simulation.fogs`, by owner) that the AI and
`Commands` read to decide what a player may see, explore and build on. `FogView` only draws it.

## Tests

- `just commands-test`: boots a real two-player game headless and submits commands: ownership, payment,
  refusals, orders, the six-worker limit, the dog, and units not squeezing through a diagonal corner.
- `just phrases-test`: every phrase has Latin and English, and every key named in the code exists.
- `just siege-test`: attacking, burning and destroying a building, a people being defeated, and the last one winning.
- `just war-test`: an AI wave marches across the map, burns the enemy town down and defeats the people.
- `just ai-test`: four AIs play each other at 10x for a few thousand game seconds, and it prints each one's towns,
  era, army, how much of the map it has explored, and the kills, every 150 game seconds. This is how AI changes
  are judged: there is no pass/fail, so read the numbers.
- `just settlement-test`: a Settlement absorbing citizens, growing into a Town Center at 15 and a City Center at 30, and refusing more than 50.
- `just farm-test`: a 9x9 farm's eight plots round a granary, one villager to a plot, bare plots growing only while tended, food reaching the granary, a Large Farm at 8 citizens.
- `just herd-test`: the sparse start (a couple of berry bushes, herds, no gold or stone by the town) herds wandering within their range, breeding, capping and being hunted out, and gold spread thinly.
- `just water-test`: a dock only in the shallows touching land, a boat made on water, fish only for boats, 15 a trip to the dock, boats stay on water.
- `just net-test`: the lobby, host and client in two processes.
- `just replay-test`: the simulation is deterministic: two runs of a game agree to the last checksum; a game written down
  plays back, AIs off, to the same checksums (also with a person's commands in it); a tampered replay or one with commands
  missing is found out; a game quit part way is still a replay.
- `just lint`: parses every script, and checks that every member named on `Simulation`, its parts and `Main` exists
  (GDScript only warns about those).
- `--report` (see the justfile): runs a game headless and dumps the state, which is how AI behavior is
  checked.
