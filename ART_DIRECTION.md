# Art Direction

How the game should look, so every new asset fits. Follows the pillars in
[DESIGN.md](DESIGN.md): cozy, readable, order-from-chaos.

## Style in one line

**Stylized low-poly with soft, painterly textures, lit like a candle-lit
library at night.** Charming, not realistic. Readable at a glance.

## Rules

1. **Readable first.** A player should tell item types apart from ~5 m by
   silhouette alone. Shape is a clue (DESIGN.md pillar 2), so every type
   needs its own shape family.
2. **Warm, low, pooled light.** Warm key light, lantern pools, gentle glow.
   No cold white light, no harsh contrast.
3. **Soft, not noisy.** Textures have gentle variation, never gritty
   detail. Low-poly shapes with bevelled or rounded feel.
4. **Magic is the accent.** Most of the scene is warm neutral (wood,
   plaster, parchment). Saturated jewel tones are reserved for magical
   things: potion glass, orbs, gems, the sign gems.
5. **Feedback glows softly.** Correct = gentle sage green, wrong = warm
   terracotta. Never neon.

## Palette

| Role | Colour | Hex |
|---|---|---|
| Night / background | Deep umber | `#171210` |
| Floor oak (mid) | Honey oak | `#74503A` |
| Furniture walnut (mid) | Walnut | `#684428` |
| Plaster (mid) | Dusty cream | `#CEB69C` |
| Parchment | Cream | `#EADAB8` |
| Ink (sign text) | Dark sepia | `#331F12` |
| Lantern light | Candle gold | `#FFC785` |
| UI panel | Walnut, 86% | `#21170F` |
| UI accent / border | Brass | `#C79E61` |
| UI text | Warm white | `#FAEDD4` |
| Correct | Sage | `#85BD75` |
| Wrong | Terracotta | `#D16B52` |
| Robes (players) | Plum / Teal / Rust / Moss | `#734785` `#33757A` `#AD5C38` `#618042` |

## Typography

- **Alegreya** (serif, OFL): shelf signs, item labels, titles. Bookish.
- **Nunito** (rounded sans, OFL): all UI text. Friendly and legible.
- Licences are in `assets/fonts/`.

## Assets: specs and where they live

| Kind | Location | Spec |
|---|---|---|
| Textures | `assets/textures/` | 512×512 PNG, **tileable**, `name_albedo.png` + `name_normal.png` (OpenGL-style normals, Godot's default) |
| Materials | `assets/materials/` | `StandardMaterial3D`. Floor, walls and wood use world-space triplanar mapping, so textures stay the right scale on any geometry with no UV work |
| Item models | `assets/models/<type>.tscn` | Pivot at the **base centre** (y = 0 is the resting surface). Roughly 0.2–0.3 m across. Keep low-poly (< 1k tris). Meshes named `Tint…` get the item's colour at runtime; everything else keeps its own material |
| UI theme | `assets/ui/cozy_theme.tres` | Applied project-wide (Project Settings → GUI → Theme) |
| Fonts | `assets/fonts/` | OFL-licensed only |

## Replacing placeholder art

Everything here is designed to be swapped without code changes:

- **Textures**: overwrite a PNG with a hand-painted one of the same name.
  `tools/gen_textures.py` regenerates the procedural versions.
- **Item models**: replace `assets/models/potion.tscn` (etc.) with your own
  model scene. Keep the pivot at the base, name tintable meshes `Tint…`,
  and update the collision `size` for that type in `data/item_catalog.gd`.
- **New item type**: add a `Category` in `data/item_catalog.gd` with its
  shape variants (model path + collision size), its one-line shelf rule,
  and a name pool. The shelf unit, its sign and statuettes are built
  automatically, and units wrap onto the side walls when the back wall is
  full.
- **Colour**: item tints come from `ItemCatalog.TINT_PALETTE`, shared by
  every type. Never give a type its own colour: colour must not be a clue.

## Next art steps

- More shape variants per type (currently 8 shapes across 6 types) so the
  floor looks varied; hand-made models to replace the primitive ones.
- Windows with moonlight, bookstacks and props so the room feels lived-in.
- The room reacting to progress (DESIGN.md "Feel"): clutter fading and
  light warming as shelves fill.
- Sound: pickup, place, correct chime, gentle "hmm" for wrong.
