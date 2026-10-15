# IMPERIVM — design notes

A real-time strategy game about the rise and fall of Rome, from a village of huts on the Palatine
to the end of the Western Empire. Isometric pixel art, Empire Earth–style play: you start with a few
villagers and a Forum, gather, build, and advance through historical eras.

Status key: **built** (in the game now), **decided** (agreed, not built yet), **proposed** (a first
guess to tune or change), **open** (needs a decision).

---

## Pillars

1. **Period-accurate and Roman.** Art, buildings, names and progression follow Roman history.
2. **Latin on screen, English on hover.** All UI text is Latin in Roman capitals (V for U), and every
   piece of text has an English tooltip. Nothing is shown in English only except tooltips.
3. **Pixel art you can edit.** All art lives in PNG sheets (`assets/art/`), so an artist can replace it
   without touching code.
4. **Rise and fall.** The eras are a story arc: build up through the Kingdom and the Republic, peak
   under the Principate, then hold on through the Late Empire's crises.

---

## The eras

Dates are the traditional ones. Confidence: high from the Republic onward; the Kingdom is partly
legendary (the monarchy itself is generally accepted as real, the individual kings and dates much
less so). "Principate" and "Dominate" are modern scholarly labels, and the fall was gradual, so
historians draw the end points differently.

| # | Latin name (banner) | English | Dates | What it is |
|---|---|---|---|---|
| I | Regnum | The Kingdom | 753–509 BC | Founding by Romulus and seven kings (the last three Etruscan; Tarquin the Proud expelled 509 BC). Archaeology shows a real Iron Age hut village; the Forum is drained and the first temples rise. |
| II | Res Publica | The Early Republic | 509–264 BC | Two annual consuls and the Senate; patricians vs plebeians; the Twelve Tables (c. 450 BC); the Gauls sack Rome (traditionally 390 BC); Italy is conquered through the Latin and Samnite wars and Pyrrhus. First paved road and first aqueduct in 312 BC (the Via Appia, Appius Claudius Caecus). |
| III | Imperium Populi Romani | The Republic Expands | 264–27 BC | The Punic Wars (Carthage destroyed 146 BC), conquest of Greece and Spain, the Gracchi, Marius's army reforms, Sulla, Spartacus, Pompey, Caesar (Gaul 58–50, Rubicon 49, assassinated 44), Actium 31 BC; Octavian becomes Augustus in 27 BC. |
| IV | Principatus | The Empire at its Height | 27 BC–284 AD | Augustus and the Pax Romana (about 200 years); the Colosseum (80 AD); greatest extent under Trajan (117). Ends with the Crisis of the Third Century (235–284): plague, civil war, inflation. |
| V | Dominatus | The Late Empire | 284–476 AD | Diocletian's reforms, Constantine (Christianity legalised 313, Constantinople 330), the permanent split in 395, Rome sacked in 410 and 455, last Western emperor deposed 476. (The Eastern half lasted until 1453; out of scope.) |

The era shows in a banner at the top centre of the screen: `AETAS I` over `REGNVM`, with the English
name and dates on hover, and a progress readout while an advance is under way. **Built.**

### What each era is for (flavour and content)

| Era | Feel | Content (planned) |
|---|---|---|
| I Regnum | A hut village finding its feet | Villagers; Casa (hut); Ager (wheat field); Horreum; **Casa Romuli** (the Hut of Romulus, the town centre); **Arx** (stockaded citadel, trains soldiers); **Aedes Vestae** (round thatched shrine with a sacred fire); **Stabulum** (stable, trains **Eques** cavalry); dirt roads that wear into the ground |
| II Res Publica | Citizens, civic life, first conquests | Stone Domus; **paved roads (Via)**; **Vinea** (vineyards); **Curia** (Senate house); **Aquaeductus**; **Castra** and citizen soldiers (**Milites**); **Templum**. All built (see below) |
| III Imperium Populi Romani | Legions and expansion | Legions, barracks, ships and harbours, provinces, bigger aqueducts |
| IV Principatus | Peak: monuments, baths, amphitheatres | Baths, amphitheatre, triumphal arches, roads and aqueducts at scale |
| V Dominatus | Holding on | Walls and fortifications, barbarian pressure, economic strain; the "fall" gameplay |

---

### Era I town centre: the Casa Romuli (Hut of Romulus)

Early Rome was a cluster of thatched wattle-and-daub huts, and the Forum was a drained marsh (paved c. 600 BC),
not a marble building. So in Era I the town centre is the **Casa Romuli**, the Hut of Romulus (the thatched hut on the Palatine that Romans kept and rebuilt for centuries as the founder's house; the separate royal *Regia* in the Forum came later, traditionally under Numa): a great round hall
beside two lesser huts, a stake palisade and the sacred hearth. Entering Era II upgrades it in place to the
marble **Forum**. It is the same building in the game logic (`town_center`); only its name and sprite (`regia`
vs `town_center`) depend on the era (`Building.era`).

### Era II content — built

| Thing | Latin | Notes |
|---|---|---|
| Domus | *Domus* | stone house, +5 population |
| Paved road | *Via* | dragged out and paved by villagers; 1.7x speed |
| Senate house | *Curia* | brick hall with marble pilasters and bronze doors. Pure prestige for now: its powers (the Senate) come later |
| Aqueduct | *Aquaeductus* | a 4x1 run of arches carrying a water channel; +8 population (fresh water lets a bigger town live here). People walk under the arches |
| Barracks | *Castra* | a palisaded camp; trains soldiers. In Era I the same building is the *Arx*, a stockaded hilltop fortress with a watchtower (`Defs` "early" entry), and it can already be built |
| Temple | *Templum* | a small marble temple on a high podium with four front columns. In Era I the same building is the *Aedes* (Vesta's round thatched shrine with an animated sacred fire). Pure prestige for now, like the Curia |
| Fighting men | *Miles Gravis*, *Pedes*, *Funditor*, *Eques* | Early Roman citizens armed themselves and wore no uniform, so the wealthy fought mounted (*Eques*, from the *Stabulum*), the well-off as heavy infantry in helmet and breastplate (*Miles Gravis*), the middling with a shield and spear (*Pedes*), and the poorest as slingers (*Funditor*). Each kind has three looks (tunic colour, how much armour) so no two neighbours match. A group of them stands near the start for display (they take no population) until training them is wired up |
| Soldier | *Miles* | an early-Republic citizen soldier: bronze helmet with a crest, breastplate, round shield, spear. Can march but not work, and there is no combat yet |
| Vineyard | *Vinea* | a renewable field like the Ager, but its crop is wine, sold for **gold** (200 per crop, ripens again in 30 s) |

**Why vineyards are Era II.** Vines reached Latium early (the Etruscans and Greeks brought viticulture
in the 8th–6th centuries BC), so a few vines in Era I would not be wrong. But large-scale, commercial
winemaking is a Republic story (Cato's *De Agri Cultura*, c. 160 BC, treats vineyards in detail). So wheat
is Era I's farm and wine is Era II's trade crop. (Moderate confidence.)

**Chrome.** Each era has its own HUD frame (`Art.FRAME_STYLES`): Era I is gold Greek key on dark red;
Era II is white marble with a wave scroll on Roman purple. Eras III–V reuse Era II's until they are designed.

**Trying it out.** Press **E** to jump to the next era (**Shift+E** for the previous one). The map is dressed
as a town grown into that era (buildings, a paved avenue, workers, soldiers), clearing woodland as it
goes. This is a temporary tool for looking at the art and interface, not a game mechanic.

## Advancing through eras — decided: option A

The player advances at the **Forum** with an **Advance** button (Latin: *Progredere*), as in Age of
Empires. **Built for Era I → II** (the Forum's command bar; hover the button for the cost and a
checklist of what is still missing). Advancing costs resources and has prerequisites, and takes some time. New buildings and
features unlock only once you have reached the era.

Why this over the alternatives (automatic milestones, or "prestige" points): it is familiar,
predictable, and makes use of the buildings we already have.

### Proposed gates (numbers to be tuned in playtesting)

| To reach | Cost | Prerequisites | Time |
|---|---|---|---|
| II Res Publica | 300 food, 300 wood, 100 stone | population 15; 3 Casae; a working Ager; a Horreum | 45 s — **built** (`Defs.ERA_ADVANCE`) |
| III Imperium Populi Romani | *open* | *open* — should lean on Era II content: Domus, paved road tiles, Curia | |
| IV Principatus | *open* | | |
| V Dominatus | *open* — probably triggered by the Crisis of the Third Century rather than bought | | |

### What each era unlocks — decided: be era-realistic

- **Era I (Regnum):** Forum, Casa, Ager, Horreum, dirt roads (these wear into the ground from foot
  traffic and need no building).
- **Era II (Res Publica):** the stone **Domus** and **paved roads (Via)** are locked until Era II. The
  historical hook is the Via Appia in 312 BC. **Built:** while locked, their buttons show greyed with the
  unlocking era's numeral (II) and a tooltip saying so; placing one is refused (*Nondum licet*, "not yet
  allowed"). The Domus's `era` and `Defs.ROAD_ERA` set the gates.
- Later eras: see the content table above.

A full **tech tree** (upgrades such as better axes or farming) is a separate, larger piece of work;
era gating of buildings comes first.

---

## What is built today

- Isometric pixel-art map (32×16 tiles) with fog of war, minimap, edge-scroll camera, whole-pixel zoom.
- **Villagers:** click / drag-select, right-click to move, gather, build; they walk around each other.
  Animations: walk, chop, mine, forage, till, build.
- **Economy:** wood, food, stone, gold; 15-unit loads hauled to the nearest depot; population cap.
- **Buildings:** Forum (start), Casa (+3 pop), Domus (+5 pop), Horreum (depot), Ager (renewable field).
  The Forum trains villagers.
- **Roads:** dirt roads wear into the ground where villagers walk (faster, preferred by pathfinding);
  **paved roads** can be laid by dragging, paid for in stone and built tile by tile by villagers.
- **Eras:** the banner, the Forum's Advance button (Era I → II), era-gated buildings (Domus, paved roads,
  Vinea, Curia, Aquaeductus and Castra unlock in Era II), per-era HUD chrome, and an E-key era jump for testing.
- **Height map and terraces:** every tile has an elevation (`GameMap.elevation`; plains gentle, hills steeper, mountains steepest). It shows in two ways. Slopes are lit from the top-left like everything else (the `relief` texture in `ground.gdshader`), and the land is cut into six terraces (`GameMap.levels`, 0-5; thresholds in `LEVEL_STARTS`), each lifting the ground 5 px (`Iso.LIFT`) with a drawn earth cliff between steps and a grassy lip. Units, buildings, trees, fog and clicks all follow the lift (`Iso.to_screen` / `Iso.to_tile`, and the shared `terrace.gdshaderinc`); walkers climb a step smoothly rather than popping up. It also drives play: steep ground costs more to walk (`slope_factor`), high ground sees farther (about +1 tile of sight per 0.1 of height), and every building (fields included) must stand on one terrace.
- **Interface:** Latin text with English tooltips; icon command bar; resource panel for a clicked
  deposit; era banner. Every panel shares a gilded Greek-key (meander) frame (`FramedPanel`), and the
  resource bar uses pixel-art icons (logs, wheat, stone, gold ingots, a villager) instead of words.
- **Source layout:** `core/` (the game state and rules: `main`, `defs`, `game_map`, `unit`, `building`, `iso`, `weather`, `fog`, `latin`), `art/` (the drawing code: `art`, `pixel`, `team`), `views/` (everything drawn from that state: `world`, the unit/building/ground/fog/weather/overlay views, the animated bits, the minimap), `ui/` (`hud`, buttons, `splash`, `intro`), `shaders/`. `main.tscn` stays at the top. Scripts find each other by `class_name`, so a script can move between folders; only `res://` paths for the shaders and `main.tscn` need updating.
- **Art pipeline:** sprites are drawn in code (`art/art.gd`) and baked into editable PNG sheets and a Godot
  TileSet (`assets/art/`, `tools/export_art.sh`).

## Open questions

1. Prerequisites and costs for eras III–V.
2. How the fall works in Eras IV–V: scripted crises, barbarian raids, economic strain, civil war?
3. Military: units, combat, and rival factions (Etruscans, Latins, Samnites, Carthaginians, Gauls...).
4. Whether the player is "Rome" in one fixed location, or can found additional cities.
5. A tech tree (upgrades) and how it relates to eras.

## Conventions

- **Latin lettering:** capitals only, V for U (IMPERIVM). Text goes through `Latin.t()`; English
  glosses live next to the Latin (see `latin.gd`, `hud.gd`).
- **Player colours:** every building has an owner (`Building.owner`, an index into `Defs.PLAYER_COLORS`; player 0 is Roman purple, and landmarks such as the Circus have none). The colour is never baked into the art: it is an overlay (a fluttering pennant on the roof, tinted from a grey sprite, `BuildingView`; nothing is drawn on the ground), plus the building's dot on the minimap. A second player only needs a different `owner`. Units are marked the same way (`Unit.owner`): their sprites carry three magenta placeholder colours (`Art.TEAM_KEY`) on the belt, shield rim, spear pennon, slinger's headband and horse's saddle blanket, and `team.gdshader` swaps them for the owner's light, mid and dark colour, so a battle can be read at a glance without a uniform (early Roman soldiers had none).
- **Circus Maximus:** a landmark (`Defs.BUILDINGS["circus"]`, `landmark: true`, so it isn't in the build bar) that stands near Roma from the start, 10x4 tiles, owned by player 0 like everything of ours (purple). It is a rounded stadium, a capsule with a half circle at each end, drawn by marching each pixel along its line of sight over a height map (`Art.circus_height`, `circus_surface`): a sand track round a low spine with two turning posts, four tiers of timber seating all the way round, the starting gates at the far end, and a band of the owner's colour round the outer wall. The crowd and the corner flags are not in the picture but animated in code (`circus_crowd.gd`): spectators sit on the tiers that are actually in view, about a third in the owner's colour, with a wave of cheering (arms up, a hop) running round the stands, and a pennant in the owner's colour flutters on each corner. Tradition has Tarquinius Priscus (the fifth king, c. 600 BC) laying it out in the valley between the Palatine and the Aventine, with wooden seats (the stone circus is much later), and the valley was marshy before the Cloaca Maxima drained it. So the game puts it on the nearest open ground it can find (`_place_circus`): the woods, marsh and scrub are cleared from the site and a tile all round it, and the ground is levelled and raised two terraces so it stands on a platform of its own. It has no function yet; races are the obvious thing to add.
- **The world:** 240 x 240 tiles, nine times the old map: a 3 x 3 grid of 80-tile blocks (`GameMap.BLOCK`, `WORLD_BLOCKS`). The middle block is the Tiber lowland where Rome starts (a basin of water and marsh with the marsh mostly confined to it); the eight around it differ in character by how much higher the land stands and how wet it is (`BLOCK_ELEVATION`, `BLOCK_MOISTURE`: hillier and drier to the north, wooded and wet to the north-east and south-east, drier meadow to the west and south), blended smoothly so there are no seams. Mines and berry patches are scattered over the whole world. The minimap is a flat top-down square.
- **Staying fast on a big map:** nothing off the screen is built, animated or redrawn. Scenery (trees, reeds, hills, mines) is built in 12-tile chunks only near the screen and dropped when well away (`World._stream_terrain`); units and buildings off the screen skip their view updates; the "hidden behind scenery" pixel tests run a few times a second per unit, not every frame; the fog only touches the tiles whose state changed and does nothing when nothing moved (`Fog.update`); the ground, terraces and fog are shaders that cost only for the pixels on screen. Map generation uses fast separable blurs and takes under a second. `--perf` prints where each frame's time goes after 400 frames (`perf.gd`), and `--pan=x,y` scrolls steadily that way to test streaming. On the dev machine the stationary game averages about 10 ms a frame with no hitches.
- **Roma and the marsh:** the first city is called **Roma** (`CITY_NAMES`), and the start is chosen beside a marsh when the map has one (`GameMap.find_start`), because the founding legend has the twins left on the marshy bank of the Tiber and the Forum valley was a swamp until it was drained (traditionally under Tarquinius Priscus, c. 600 BC). Marsh (`Terrain.MARSH`, about 7% of the map) is low, wet ground just above the shore, with pools of standing water and reeds: it is walkable but slow (cost 2.0), and nothing can be built on it. Reaching Era II drains the marsh within 14 tiles of the city (the Cloaca Maxima), turning it into grass; marsh farther away stays. The other city names (Ostia, Veii, ...) are for later cities.
- **Biomes (hidden):** every tile also has a biome (`GameMap.Biome`, computed in `_compute_biomes`) that decides what scenery grows there; the player never sees the names. It is the standard approach: elevation and moisture (and distance to marsh and woodland) classify the ground, so which biomes touch is decided by the fields themselves and borders fade through ecotones (`MEADOW_EDGE`, `WET_EDGE`) instead of meeting at a ruled line. The biomes are `OAK_WOOD` (oaks, the odd pine), `PINE_WOOD` (pines and cypress on dry or high ground), `WET_WOOD` (alders and willows near marsh or on very wet ground), `BOG` (marsh: reeds, dead snags and stunted mossy alders), `MEADOW`, the two edges (scrub, and willows and alders by the marsh), `COAST`, `HIGHLAND` and `CRAG`. Forest tiles stay harvestable whatever the tree; the bog and meadow scenery (snags, bog alders, scrub) is decoration only. The tables are `World._forest_tree` and `World._meadow_scenery`. If hard adjacency rules are ever wanted (say, a desert that may never touch a snowfield), the tool for that is wave function collapse or a compatibility cleanup pass over `biomes`; this map doesn't need one.
- **Weather:** a Markov chain (`weather.gd`) over clear, cloudy, fog, rain and storm (no snow: Rome is mild). Each state lasts one to two minutes; when it ends the next is drawn from that state's row of `TRANSITIONS` (so rain follows cloud, storms follow rain, and the long-run mix is mostly clear and cloudy, with some rain, a little fog and the odd storm). The look eases from one state to the next, so fog rolls in and rain builds. It is drawn as one pixel-art shader over the world and under the interface (`weather_view.gd`, `weather.gdshader`): a darkening tint, drifting cloud shadows, dithered fog banks that drift on the wind, slanted rain streaks in two layers, and lightning flashes in storms. Rain also lands on the water: splashes and spreading rings on the sea, shallows and marsh pools (`raindrop` in `ground.gdshader`), denser the harder it rains, and the water runs faster and breaks into more whitecaps in a storm. It is visual only for now; the game has no weather effects yet (rain could water the fields, fog could shorten sight). The sequence is the same every time for a given map seed. Debug: **W** steps to the next weather, and `--weather=rain` (or fog, storm, cloudy, clear) starts in that weather.
- **Settings** (*Optiones*, a button on the title screen; `ui/settings_screen.gd`, `core/settings.gd`, icons drawn in code by `ui/icons.gd`; kept in `user://settings.cfg` after every change and loaded again at the next start, so nothing changes unless the player changes it). Three pages (tabs):
  - **Tabula** (the map): the **kind of map**, i.e. the shape of the land (18: Continens, Campi, Insulae Parvae, Insulae Magnae, Archipelagus, Mare Nostrum, Paeninsula, Montes, Paludes, Silvae, Lacus, Vallis Tiberis, Ora Maritima, Duae Terrae, Anulus, Colles, Litus Asperum, Insula), each with a picture drawn by the same generator (`GameMap.preview`); the **size** (Minima 160, Parva 240, Media 320, Magna 400, Maxima 480 tiles a side); the **ground** (*Natura soli*), which is separate from the shape: Temperata, Campestris (grassland), Collina (hilly), Silvestris (wooded), Nivalis (snow) and Arida (desert); and the **resources** (Tenuis, Mediocris, Opima: 0.6x, 1x or 1.6x as many berry patches, mines and finds, at the start and scattered over the map).
  - **Populi** (the peoples): the **number** (2 to 8: you plus 1 to 7 computer-run rivals); the **AI skill** (Facilis, Aequus, Difficilis; see below); and a row per people playing, where you pick which people each rival is (the seven in `Defs.RIVAL_ORDER`, each used once; you are always the Romans) and its **colour** (the eight in `Defs.PLAYER_COLORS`, each used once). Choosing something already taken swaps the two. Player numbers are slots (you 0, the rivals 1 and up); `Defs.color_of(owner)` gives a slot's colour.
  - **Instrumenta** (the interface): game **speed** (0.5x, 1x, 1.5x, 2x, applied as `Engine.time_scale` once the world runs), **music** and **effects** volume (0 to 5 notches, set on buses named Music and Effects, made at start-up; there is quiet music, see below; no sound effects yet) and window or full screen.
  Debug flags override the choices without saving: `--map= --size= --players= --resources= --difficulty= --terrain=` (and `--page=map|players|interface` with `--settings`).
- **Music** (`core/music.gd`; the pieces are rendered by `tools/make_music.py` and stored as `assets/audio/<era>_<mode>.ogg`): eight pieces, an era's style in each of four modes. The Kingdom (`regnum_*`) is slow, pastoral ambience (drone, soft chords, sparse lyre notes); the Republic onward (`republic_*`) is livelier, with a pulse (frame drum and shaker, bass, arpeggiated cithara, a reedy tibia melody). The weather picks the mode: clear Lydian or Mixolydian, cloud Mixolydian or Dorian, fog Dorian or Phrygian, rain Dorian or Phrygian, storm Phrygian. A piece that no longer suits when the weather or era changes fades out in 3 seconds and a fitting one begins; otherwise it plays out and the next is picked at random. Later eras reuse the Republic's style until they have music of their own. The modes are a mood choice: almost no Roman music survives, and the modern mode names don't match the Greek ones.
- **Ground** (`GameSettings.TERRAINS`): each adds to the map type's wetness, woodland and marsh, scales every hill and range the recipe lays (`hills`) and adds extra hills (`more_hills`); snow and desert also set a `style` that `ground.gdshader` uses to re-colour the grass, forest floor, hills and marsh (keeping the light and shade), that `season.gdshader` uses to frost or parch trees, scrub and hills, and that the minimap uses for its colours. Grassland and desert keep a few groves, so wood is never missing.
- **How land is made** (`core/terrain_gen.gd`): not by thresholding noise, which scatters specks, but by **stamping shapes** onto the sea. Each kind of map has a recipe: wobbly-edged blobs make continents and islands (a main ellipse with lobes round its rim for capes and bays), ellipses raise hills and chains of them raise mountain ranges, other blobs carve out lakes, bays, a river or a strait, and flat "meadow" patches keep woods, marsh and hills off the ground where people will build. The edge of every stamp is wobbled by noise, so coasts are ragged but smooth. Only then does a little low-frequency noise add texture and decide where woods and marsh clump. Each people's starting ground is levelled and cleared (with woods close by beyond it), and island maps give every people an island of its own. Positions and sizes are fractions of the map's side, so thumbnails show the same shapes as the real map and bigger maps are the same land at a larger scale. About 80-88% of the ground within 20 tiles of Rome is free to build on in the continental maps. The land-heavy maps (Continens, Lacus, Silvae, Colles, Paludes) are a broad **square** reaching nearly to the map's edge, with a strip of open sea all round it (`_sea_margin`: 7 to 12 tiles wide, about 9 on a medium map, enough for ships to pass but no more); **Campi** has no sea at all, its grassland running right off the edge. The stamp takes a `power` (2 is an ellipse, 5 a rounded square).
- **Rivals play fair.** A `Rival` pays for everything from its own stores, builds with its own villagers at the normal speeds, obeys the population cap, and gathers at the normal rate. It also **knows only what its own people have seen**: each rival has its own fog (`Rival.fog`) that it updates from its units and buildings, it can only work deposits it has explored, it can only build on explored ground, and it sends a villager exploring when it has nothing it knows of to gather. It gets no resource or speed bonuses and cannot see the player. The AI skill changes only how often it decides (every 2.6, 1.2 or 0.6 seconds), how fast it aims to grow (one more villager every 45, 25 or 14 seconds of its history), how large a people it can keep (20, 40 or 70 villagers) and how many buildings it works on at once (1, 2 or 3).
- **Rivals:** other peoples share the map (`Defs.FACTIONS`). A player's number is also the index of its colour: Rome 0 purple, Etruscans 1 red, Greeks 2 blue, Samnites 3 green, Sabines 4 amber, Volsci 5 teal, Aequi 6 yellow, Latins 7 white (Alba Longa means "the long white one"). Each starts with a town (Veii, Cures, Alba Longa, Cumae, Bovianum, Antium, Corbio), five villagers and the same stores as Rome, about 0.28 of the map's width from Rome (`GameMap.find_start`, with a flood fill where the land is connected). The Greeks stand to the south, where the Greek colonies of Magna Graecia were (Pyrrhus came in 280 BC; Tarentum was a Spartan colony, so a Spartan touch fits there). Each people is run by a `Rival` (`core/rival.gd`) that obeys the same rules as the player: its own stores, population cap and depots, villagers trained at its town and sent to gather (wood, food, stone, gold, split by shares), huts when it nears its cap, fields beside the town, a storehouse by the woods. It thinks about once every 1.2 seconds. Rival units show only while we can see them, and their buildings once their ground has been explored; they can't be selected and their fields can't be worked by us. **Not built yet:** combat, rival soldiers and attacks, and any difference between the peoples beyond name, colour and place (they use Rome's buildings and units for now). **M** toggles the whole map open (`Fog.set_show_all`, also `--reveal`) so you can look at them.
- **Loading:** the 320x320 world (4x4 blocks) takes a few seconds to build, so when you press Incipe (after the opening scroll and the title) it is generated on a worker thread while a loading screen with a progress bar shows what is happening in Latin and English (`ui/loading.gd`, `GameMap.progress`).
- **Opening scroll:** (over a dim animation of burning Troy, `troy_fire.gd`) on a normal start, before the title, the Trojans' story (the fall of Troy, the voyage with Anchises and Ascanius, Juno's storm, Dido, the voice at the Tiber's mouth, Romulus and Remus) rises slowly up the page in Latin, each verse with a smaller English line under it (`intro.gd`). Any key or click skips to the title; it also moves on by itself after the last verse. Debug runs skip it like the title; `--intro` forces it.
- **Title screen:** the Capitoline she-wolf (`Art` key `lupa`, a bronze statue with Romulus and Remus, on a warm glow) over IMPERIVM, with two buttons in the game's usual style: *Incipe* (play icon; Enter or Space) and *Exi* (door-and-arrow icon; Q or Esc). The game is paused behind it until you press Incipe (`splash.gd`). `--nosplash` skips it, and runs with `--shot`, `--report`, `--record`, `--demo` or `--showcase` skip it by themselves (`--splash` forces it, to look at it).
- **Glossary:** every Latin term in the game, with its English, is listed in [`LATIN.md`](LATIN.md). Update it when you add text.
- **Names:** Latin buildings have an accusative form for verbs ("Aedifica Domum").
- **Era data** lives in `Defs.ERAS`; `Main.era` is the current era.
