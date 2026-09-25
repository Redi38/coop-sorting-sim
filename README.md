# Co-op Arcane Sorting Sim — Milestone 1 scaffold

Goal of this scaffold: two Godot clients can host/join, spawn into a shared
room, pick up items, and place them in shelf slots — with the host as the
single source of truth for item state. That's the whole milestone; no
categories UI polish, no unlocks, no zones yet.

## Structure

```
project.godot
autoload/NetworkManager.gd   # ENet host/join, player spawn/despawn (host-authoritative)
data/item_catalog.gd         # Categories (id/display name/color) + item name+description
                              # templates — the clue data. Not an autoload; referenced via
                              # its class_name (ItemCatalog) from World/Item/ShelfSlot.
scenes/main_menu/            # Host/Join screen
scenes/world/                # The room: floor, spawn points, shelf slot grid, item spawner
scenes/player/                # First-person body, camera, interact ray, hold point, capacity HUD
scenes/item/                  # Pickup/place-able object, host-authoritative state, clue display
scenes/shelf_slot/            # Trigger volume that validates category + locks on correct place
```

## Setup steps (do these in the Godot editor before running)

1. Open the folder as a Godot 4.3+ project.
2. **Input Map** (Project Settings → Input Map) — add these actions, since
   they're referenced by `Player.gd` but not safe to hand-write in this
   scaffold's `project.godot`:
   - `move_forward` → W
   - `move_back` → S
   - `move_left` → A
   - `move_right` → D
   - `jump` → Space
   - `interact` → E
   - `ui_cancel` already exists by default (Esc) — used to toggle mouse capture.
3. Open each `.tscn` once in the editor and let Godot re-save it — these
   were hand-written as text, so node references (`@onready` paths, unique
   names like `%HostButton`) should resolve, but double-check the Inspector
   matches what the scripts expect, especially the `MultiplayerSynchronizer`
   replication configs on `Player.tscn` and `Item.tscn`.
4. Swap the placeholder `BoxMesh`/`CapsuleMesh` for your low-poly art
   whenever it's ready — nothing else needs to change, since the scripts
   reference nodes by name, not by mesh.

## How the networking is structured

- **Host-authoritative everything.** Clients never set item or slot state
  directly — they call `request_pickup` / `request_place` RPCs on the host
  (`@rpc("any_peer")` methods with an `if not multiplayer.is_server(): return`
  guard), and the host is the only one that mutates `held_by_peer`,
  `placed`, and `locked`.
- **Player transforms** are the one thing each client is authoritative over
  for itself (`set_multiplayer_authority(id)` in `NetworkManager._spawn_player_on_all`),
  synced to everyone else via each `Player.tscn`'s `MultiplayerSynchronizer`.
- **Items spawn dynamically** through a `MultiplayerSpawner` on
  `World/Items`, so the host can call `add_child()` on new `Item` instances
  at runtime and every client automatically gets them — no manual spawn RPC
  needed for that part.
- **Lock-on-complete** lives entirely in `ShelfSlot.request_place`: once a
  correct placement sets `locked = true`, every later `request_place` call
  on that slot is rejected before it touches anything.
- **Shelf slots are generated, not hand-placed.** `World._spawn_shelf_slots()`
  builds a grid (`SLOTS_PER_CATEGORY` per category) from `ItemCatalog`'s
  fixed category list. It's pure deterministic math with no randomness, so
  every peer builds an identical node tree at `_ready()` — that's what lets
  `ShelfSlot`'s host-authoritative RPCs resolve to the same NodePath on
  host and clients without needing a MultiplayerSpawner for slots (only
  items need one, since their scatter position is randomized on the host).
- **Clue data is centralized in `ItemCatalog`** (`data/item_catalog.gd`):
  each category has a color (the visual clue, shown on both the item mesh
  and the shelf slot indicator) and a display name; each item template has
  a name + one-line description (the textual clue). `World._spawn_items()`
  calls `ItemCatalog.get_item_templates(TARGET_ITEM_COUNT)`, which cycles
  the hand-authored pool with numbered repeats ("Shimmering Elixir (Batch
  2)") to reach whatever count is asked for — so raising `TARGET_ITEM_COUNT`
  toward the design doc's 150–300 doesn't require writing 300 items by hand.
  `TARGET_ITEM_COUNT` is now 180 (mid-range of the 150-300 spec), the
  floor was enlarged to 50x50 (from 20x20), and `_spawn_shelf_slots()`
  wraps each category's slots into a grid (`SLOTS_PER_ROW`) with
  categories laid out side-by-side along X, instead of one 60-wide row
  per category.

## Testing the milestone locally

1. Export or just run the project from the editor twice (Debug → Run
   Multiple Instances is the easiest: Editor → Run → set "Instances" to 2 in
   the debug run panel, or launch the exported binary twice).
2. Instance A: click **Host Game**.
3. Instance B: leave IP blank (defaults to `127.0.0.1`) and click **Join
   Game**.
4. Both should spawn into `World.tscn` at different spawn points, facing a
   field of 180 color-coded boxes (item name + one-line clue on a floating
   label) and, behind them, three side-by-side blocks of 60 colored/labeled
   pads each (wrapped into rows of `SLOTS_PER_ROW`) — one block per
   category, color matching the items of that category. Walk up to a
   box, press E to pick it up (a top-left HUD label tracks `Carrying: n/3`),
   walk to a pad whose color/label matches the item's category, press E to
   place it. Confirm:
   - The other client sees the pickup/placement happen in real time.
   - A correct placement locks that slot (further place attempts on it are
	 silently rejected) and the rest of that category's slots stay open
	 for the rest of that category's items.
   - A wrong-category placement is flagged (indicator turns red) but still
	 occupies the slot — per the design doc, misplacements are flagged,
	 not silently accepted; an "unplace on wrong" / return-to-shelf flow
	 isn't built yet (see below).
   - Trying to pick up a 4th item while already holding 3 does nothing.

## Deliberately not built yet (next after this loop feels good)

- Zone split / per-zone progress tracking
- Shared progression perks (extra carry slots, sprint, sort-hint pulse)
- Ping system
- Reconnect support / session persistence across drops
- Held-item visual offset per item, non-boilerplate low-poly art (still
  placeholder `BoxMesh`/`CapsuleMesh`, color-coded by category)
- An "unplace on wrong" / return-to-shelf flow — right now a wrong-category
  placement flags red and occupies the slot, but nothing clears it, so a
  slot with a wrong item in it just sits wrong until a correct item takes
  its place (still allowed, since `locked` only becomes true on a *correct*
  placement)
- Playtesting `TARGET_ITEM_COUNT` (180) and `SLOTS_PER_CATEGORY` (60) at
  the top of the 150-300 spec range, and tuning `SLOTS_PER_ROW`/spacing
  once real low-poly shelf art replaces the placeholder pads
