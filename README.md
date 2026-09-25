# Co-op Arcane Sorting Sim — Milestone 1 scaffold

Goal of this scaffold: two Godot clients can host/join, spawn into a shared
room, pick up items, and place them in shelf slots — with the host as the
single source of truth for item state. That's the whole milestone; no
categories UI polish, no unlocks, no zones yet.

## Structure

```
project.godot
autoload/NetworkManager.gd   # ENet host/join, player spawn/despawn (host-authoritative)
scenes/main_menu/            # Host/Join screen
scenes/world/                # The room: floor, spawn points, shelf slots, item spawner
scenes/player/                # First-person body, camera, interact ray, hold point
scenes/item/                  # Pickup/place-able object, host-authoritative state
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

## Testing the milestone locally

1. Export or just run the project from the editor twice (Debug → Run
   Multiple Instances is the easiest: Editor → Run → set "Instances" to 2 in
   the debug run panel, or launch the exported binary twice).
2. Instance A: click **Host Game**.
3. Instance B: leave IP blank (defaults to `127.0.0.1`) and click **Join
   Game**.
4. Both should spawn into `World.tscn` at different spawn points. Walk up
   to a box (item), press E to pick it up, walk to a colored pad (shelf
   slot) with matching category, press E to place it. Confirm:
   - The other client sees the pickup/placement happen in real time.
   - A correct placement locks the slot (further place attempts on it are
     silently rejected).
   - A wrong-category placement is flagged (indicator turns red) but still
     occupies the slot — per the design doc, misplacements are flagged,
     not silently accepted; you'll likely want an "unplace on wrong" or
     "return to shelf" flow next, which isn't built yet.

## Deliberately not built yet (next after this loop feels good)

- Zone split / per-zone progress tracking
- Shared progression perks (extra carry slots, sprint, sort-hint pulse)
- Ping system
- Reconnect support / session persistence across drops
- Real item/clue data (currently 6 hardcoded demo items, 3 categories)
- Carry-capacity UI, held-item visual offset per item, non-boilerplate art
