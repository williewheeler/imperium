# Art sheets

Everything the game draws (except the ground, which is a shader) lives in these PNG sheets and
is looked up through `manifest.json`. Edit them in any pixel-art tool (Aseprite, Pixelorama,
LibreSprite...) and the game picks the changes up on the next run, with no code changes.

| Sheet | Contents |
|---|---|
| `scenery.png` | oak 0-2, pine 0-1, cypress, mountain 0-3, hill 0-1, berries, stone 0-1, gold 0-1, carried packs |
| `buildings.png` | town_center (Forum), house (Domus), storehouse (Horreum) |
| `villagers.png` | grid, 22x24 cells. One row per animation and direction (idle, walk, chop, mine, forage, build; each front then back), one column per frame. Villagers always face right; the game mirrors them. |
| `ground_tiles.png` | 32x16 diamond tiles, one row per terrain (deep water, shallows, beach, grass, forest floor, hill slope, mountain rock), 4 variants each |
| `ground_tileset.tres` | a Godot isometric `TileSet` built from `ground_tiles.png`, for painting maps in the editor |

## Rules to keep when editing

- **Keep each sprite inside its box.** `manifest.json` records every sprite's rectangle.
  Changing a sprite's *size* means updating its entry too.
- **Anchors are fixed by size.** Trees and scenery stand on their bottom-centre pixel; buildings
  anchor at the front corner of their footprint (`Art.building_anchor`); villagers' feet are at
  `Art.VILLAGER_FEET`. Keep feet/bases at the same spot when redrawing.
- **Lighting comes from the top-left.** Left faces are lit, right faces shaded.
- Tiles are 2:1 isometric, 32x16 pixels. The Forum covers 3x3 tiles, the Domus and Horreum 2x2.

## The ground

The map's ground is drawn by `ground.gdshader`, which blends terrains with noise so coastlines
and forest edges look organic. `ground_tiles.png` / `ground_tileset.tres` use the same palettes
for hand-painting and editing; the shader doesn't read them.

## Regenerating

`tools/export_art.sh` redraws all sheets from the code in `art.gd`. **That overwrites hand edits.**
Use it only to start over, or after changing the generator. `tools/preview_art.gd` renders a
contact sheet of the generated art without opening a window.
