# Co-op Arcane Sorting Sim — Milestone 1 scaffold

> Design direction (cozy, score-only, match-by-type, parallel co-op) lives
> in [DESIGN.md](DESIGN.md); the visual style guide and asset specs in
> [ART_DIRECTION.md](ART_DIRECTION.md).

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
assets/textures/              # Tileable albedo + normal PNGs (regenerate: python3 tools/gen_textures.py)
assets/materials/             # StandardMaterial3D resources (world-triplanar for floor/walls/wood)
assets/models/                # Low-poly item models, 8 shapes across 6 types (pivot at base; "Tint*" meshes get the item's tint)
assets/fonts/                 # Alegreya (signs/labels) + Nunito (UI), OFL
assets/ui/cozy_theme.tres     # Project-wide UI theme
tools/gen_textures.py         # Procedural texture generator
tests/TestAim.gd              # Headless test: aim + interact for every type/shape (see file header)
scenes/main_menu/            # Host/Join screen
scenes/world/                # The room: floor, spawn points, shelf slot grid, item spawner,
							  # GameState (host-authoritative round state + timer)
scenes/game_hud/              # Progress bar, per-category counts, timer, win screen
scenes/player/                # First-person body, camera, interact ray, hold point, capacity HUD
scenes/item/                  # Pickup/place-able object, host-authoritative state, clue display
scenes/shelf_slot/            # Trigger volume that validates category + locks on correct place
```

## Setup steps (do these in the Godot editor before running)

1. Open the folder as a Godot 4.3+ project.
2. **Input Map** is already defined in `project.godot`: WASD to move,
   Space to jump, E to interact (pick up / place), Q to drop the last
   item you picked up, Esc to toggle mouse capture.
3. Open each `.tscn` once in the editor and let Godot re-save it — these
   were hand-written as text, so node references (`@onready` paths, unique
   names like `%HostButton`) should resolve, but double-check the Inspector
   matches what the scripts expect, especially the `MultiplayerSynchronizer`
   replication configs on `Player.tscn` and `Item.tscn`.
4. Art is a first procedural pass: swap textures, item models or the UI
   theme any time — see ART_DIRECTION.md → "Replacing placeholder art".
   Shelf units, signs, lights, ceiling and wainscot are built in code by
   `World.gd` (deterministic, so every peer builds the same room).

## How the networking is structured

- **Host-authoritative everything.** Clients never set item or slot state
  directly — they call `request_pickup` / `request_place` RPCs on the host
  (`@rpc("any_peer")` methods with an `if not multiplayer.is_server(): return`
  guard), and the host is the only one that mutates `held_by_peer`,
  `placed`, and `locked`. The host identifies the requester with
  `multiplayer.get_remote_sender_id()` rather than trusting a peer id
  passed as an argument, and enforces the carry limit itself.
- **Late joiners** get a one-shot snapshot of every filled/locked slot:
  a joining client's `World._ready()` calls `_request_slot_states` on the
  host, which replies with a single `_receive_slot_states` RPC.
- **Disconnects** release everything the departing peer was holding
  (`CoopItem.host_force_release`), so items drop to the floor instead of
  staying frozen and unpickable.
- **Filled slots** reject further placements until the wrong item in
  them is picked back up.
- **Join handshake / "ready" peers.** A joining client loads `World.tscn`
  first, then (from `NetworkManager.register_world`) tells the host it's
  ready with `_client_world_ready(name)`. Only then does the host register
  it in `players`, spawn players for it, and let items reach it. `players`
  is synced to everyone and only ever holds ready peers, so it doubles as
  the ready-list: item and player `MultiplayerSynchronizer`s use
  `NetworkManager.is_peer_ready` as a visibility filter. Without this, a
  synchronizer's first message (a node-path handshake) can reach a peer
  before the node exists there, fail, and never be retried — that peer
  then never sees the node move.
- **Bandwidth.** Item state syncs on change (`replication_mode = 2`), not
  every frame, and clients never simulate item physics (items are frozen
  on clients; only the host runs physics). Idle upload per client dropped
  from ~1 MB/s to ~10 KB/s (just player transforms).
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

## The round (game loop)

- **Goal:** sort every item. The round ends when every shelf slot is
  locked (all 180 items placed correctly).
- **Clock** starts on the round's first pickup, so waiting for friends in
  the room doesn't count. The host owns `elapsed`; clients tick it
  locally between snapshots and get resynced every 5 s.
- **HUD** (top center): `Sorted n / 180`, mistake count, a progress bar,
  per-category counts in each category's own color, and the timer.
- **Mistakes** are counted per wrong placement; picking the wrong item
  back out doesn't undo the mistake.
- **Win screen:** time, mistakes, accuracy, and each player's sorted /
  mistake counts (★ for the top sorter). The host sees **Play again**;
  clients see a waiting message. Everyone can **Leave game**.
- **Play again** resets in place (`World.host_restart_round`): items are
  despawned and respawned through the MultiplayerSpawner, slots are
  cleared with one RPC, every peer clears its carried list, and each
  player is teleported back to a spawn point. Nobody reconnects.
- **Late joiners** pull a GameState snapshot on join, the same way they
  pull slot state, so they see the correct progress, timer, and (if the
  round is already over) the win screen.

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
   - A wrong-category placement is flagged (indicator turns red) and
	 occupies the slot until someone picks the wrong item back out; a
	 filled slot rejects further placements.
   - Trying to pick up a 4th item while already holding 3 does nothing,
	 even when spamming E (the host enforces the limit).
   - Q drops the most recently picked-up item.
   - A client that joins after items were sorted sees the correct
	 green/red slot colors.
   - If a client quits while carrying items, those items fall to the
	 floor and anyone can pick them up.
   - The timer stays at 00:00 (dimmed) until the first pickup, then runs
	 on both screens and matches to within a second.
   - Sorting the last item shows the win screen on every client; the
	 host's Play again respawns everything and puts everyone back at spawn.

## Deliberately not built yet (next after this loop feels good)

- Zone split / per-zone progress tracking
- Shared progression perks (extra carry slots, sprint, sort-hint pulse)
- Ping system
- Reconnect support / session persistence across drops
- Held-item visual offset per item; hand-made art to replace the
  procedural first pass (see ART_DIRECTION.md → "Next art steps")
- Playtesting `TARGET_ITEM_COUNT` (180) and `SLOTS_PER_CATEGORY` (60) at
  the top of the 150-300 spec range, and tuning `SLOTS_PER_ROW`/spacing
  once real low-poly shelf art replaces the placeholder pads
