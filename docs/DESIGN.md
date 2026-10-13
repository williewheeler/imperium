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
| I Regnum | A hut village finding its feet | Villagers; Casa (hut); Ager (wheat field); Horreum; Regia; **Arx** (stockaded citadel, trains soldiers); **Aedes Vestae** (round thatched shrine with a sacred fire); **Stabulum** (stable, trains **Eques** cavalry); dirt roads that wear into the ground |
| II Res Publica | Citizens, civic life, first conquests | Stone Domus; **paved roads (Via)**; **Vinea** (vineyards); **Curia** (Senate house); **Aquaeductus**; **Castra** and citizen soldiers (**Milites**); **Templum**. All built (see below) |
| III Imperium Populi Romani | Legions and expansion | Legions, barracks, ships and harbours, provinces, bigger aqueducts |
| IV Principatus | Peak: monuments, baths, amphitheatres | Baths, amphitheatre, triumphal arches, roads and aqueducts at scale |
| V Dominatus | Holding on | Walls and fortifications, barbarian pressure, economic strain; the "fall" gameplay |

---

### Era I town centre: the Regia

Early Rome was a cluster of thatched wattle-and-daub huts, and the Forum was a drained marsh (paved c. 600 BC),
not a marble building. So in Era I the town centre is the **Regia** (the king's house): a great round hall
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
- **Art pipeline:** sprites are drawn in code (`art.gd`) and baked into editable PNG sheets and a Godot
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
- **Glossary:** every Latin term in the game, with its English, is listed in [`LATIN.md`](LATIN.md). Update it when you add text.
- **Names:** Latin buildings have an accusative form for verbs ("Aedifica Domum").
- **Era data** lives in `Defs.ERAS`; `Main.era` is the current era.
