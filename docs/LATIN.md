# IMPERIVM — Latin glossary

Every word the game shows is Latin, in Roman capitals with V for U (`Latin.t()`), and the English meaning
is on hover. This lists every term in use, so new text stays consistent. Where a name is the game's own
coinage rather than a period term, it says so. Keep this file up to date when you add text.

Where it lives in the code: building and unit names in `defs.gd`, one-off messages and their English in
`latin.gd` (`GLOSS`) and at the `hud.flash(...)` calls in `main.gd`, the panel text in `hud.gd`.

**Grammar conventions.** Names are in the nominative. Each building also has an accusative (`acc`) for
verbs ("Aedifica **Domum**"), and `done` / `ready` agree with its gender ("Forum **perfectum est**",
"Domus **perfecta est**"). Commands are imperatives, as in "Elige colonos" and "Explora".

## Resources

| Latin | English | Notes |
|---|---|---|
| Lignum | Wood | |
| Cibus | Food | |
| Lapis | Stone | |
| Aurum | Gold | |
| Silva | Trees | a stand of woods you can fell |
| Palus | Marsh | low wet ground (not a resource; slow to cross, nothing can be built on it) |
| Baccae | Berry bushes | |

## Buildings

Some buildings change name and picture between eras (`"early"` entry in `Defs.BUILDINGS`).

| Latin (Era I → Era II) | English | Notes |
|---|---|---|
| Regia → Forum | King's House → Town Center | the Regia is the royal hall of early Rome; the marble Forum replaces it in Era II. Trains villagers, takes every resource |
| Casa | Hut | the Era I house. `Casae` is the plural |
| Ager | Wheat field | a renewable crop |
| Horreum | Storehouse | a granary; takes wood, stone and gold |
| Arx → Castra | Citadel → Barracks | a stockaded hilltop fortress, then the palisaded legionary camp. Trains Miles Gravis. *Arx* is a real term for Rome's citadel; using it for the Kingdom-era barracks is the game's choice |
| Stabulum | Stable | trains Eques. *Stabulum* is the ordinary Latin word; as a military building it is a gameplay invention |
| Aedes (Vestae) → Templum | Shrine of Vesta → Temple | Vesta's shrine was a round thatched hut with an eternal fire. Prestige only for now |
| Circus Maximus | The Great Circus | the chariot racecourse, a landmark that stands from the start (not built by the player). *Circus* is a ring or circle; *maximus* is "greatest" |
| Domus | House | stone house, Era II |
| Vinea | Vineyard | Era II; wine is sold for gold |
| Curia | Senate house | Era II; prestige only for now |
| Aquaeductus | Aqueduct | Era II; raises the population limit |
| Via | Road | a paved road, Era II (`Viae` is the plural); dirt roads wear into the ground in Era I |

## Units

Early Roman citizens armed themselves and wore no uniform, so the richest fought mounted and the poorest
with slings. Each fighting kind has three looks (tunic colour, how much armour). See `docs/DESIGN.md`.

| Latin | English | Notes |
|---|---|---|
| Colonus (pl. *coloni*) | Villager | men and women alike. A *colonus* is a settler or farmer |
| Eques (pl. *equites*) | Horseman | the wealthy, who could afford a horse. Trained at the Stabulum. The kings' cavalry were traditionally the *celeres* |
| Miles Gravis (pl. *milites graves*) | Heavy infantry | helmet, breastplate, round shield, spear. *Miles* is the ordinary word for a soldier; "gravis" (heavy-armed) is the game's label, not an attested unit name |
| Pedes | Spearman | a foot soldier with a shield and spear but no armour. *Pedes* is singular and plural alike |
| Funditor (pl. *funditores*) | Slinger | the poorest citizens, with a sling and stones. A real Latin word |

The HUD says "milites" for any group of fighting men, whatever their kind.

## Orders and actions

| Latin | English | Key |
|---|---|---|
| Explora | Explore: walk toward unseen land until none reachable is left | X |
| Siste | Stop: drop the current order and stand still | S |
| Progredere | Advance to the next era (at the Forum) | |
| Pone *(building)* | Place *(building)* | |
| Elige | Select | left click |
| Iube | Order | right click |
| Abroga | Cancel | right click, Esc |
| Trahe | Drag (to lay a road) | left click and drag |
| Circumspice | Look around (pan the camera) | screen edge, arrow keys |
| Auge | Enlarge (zoom) | mouse wheel |
| Exi | Exit | Q (Esc on the title screen) |

## Unit states (shown when a unit is selected)

| Latin | English |
|---|---|
| Otiosus | Idle |
| Ambulat | Walking |
| Ad opus properat | Hurrying to work |
| Colligit | Gathering |
| Onustus redit | Returning with a load |
| Ad aedificium properat | Hurrying to the build site |
| Aedificat | Building |
| Ad viam properat | Hurrying to the road |
| Viam munit | Building the road |
| Explorat | Exploring |
| Onus | Load (as in "carrying") |

## Messages

| Latin | English |
|---|---|
| Elige colonos et iube eos laborare. | Select villagers and order them to work |
| Elige colonos tuos. | Select your villagers |
| Nihil electum | Nothing selected |
| Iter nullum est. | There is no route there |
| Nihil ultra explorandum. | Nothing reachable is left to explore |
| Milites laborare non possunt. | Fighting men can't work: only villagers gather and build |
| Nondum licet. | Not yet allowed: it unlocks in a later era |
| Copiae non sufficiunt. | Not enough resources |
| Pluit. | It begins to rain |
| Tonat. | A storm breaks: thunder and heavy rain |
| Nebula oritur. | Fog is rolling in |
| Sol lucet. | The sun shines |
| Caelum nubilum est. | The sky clouds over |
| Palus siccatur. | The marsh around the city is drained (the Cloaca Maxima) |
| Domus plures requiruntur. | Population limit reached: build more houses |
| Aedifica forum vel horreum. | Build a Town Center or Storehouse to drop off resources |
| Locus occupatus. | That spot is already taken |
| Locus liber et planus requiritur. | A clear, level site is required |
| Terra incognita. | Unknown land |
| Coloni impediunt. | Villagers are in the way |
| Progredimur. | Advancing to the next era... |
| Progreditur *n*% | Advancing: *n*% done |
| Aedificatur *n*% | Under construction |
| In ordine: *n* | Units in training |
| Reliquum: *n* / *m* | Remaining |
| Paratum / Parata / Paratus | Ready (agrees with the building's gender) |
| *Building* perfectum est | *Building* is complete |

## Title screen

| Latin | English |
|---|---|
| Imperivm | The Empire (the game's title) |
| Incipe | Begin: start the game (Enter or Space; the button has a play icon) |
| Exi | Leave: quit the game (Q or Esc; the button has a door-and-arrow icon) |
| Ab urbe condita | From the founding of the city: the Romans' own way of dating years, counted from the traditional founding of Rome in 753 BC |

## The eras

| Numeral | Latin | English | Dates |
|---|---|---|---|
| I | Regnum | The Kingdom | 753–509 BC |
| II | Res Publica | The Early Republic | 509–264 BC |
| III | Imperium Populi Romani | The Republic Expands | 264–27 BC |
| IV | Principatus | The Empire at its Height | 27 BC–284 AD |
| V | Dominatus | The Late Empire | 284–476 AD |

The banner reads *Aetas I* (Age I), and the map's seed reads *sors* (lot, chance). The title is *Imperivm*.
