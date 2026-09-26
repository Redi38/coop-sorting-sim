class_name CoopItem
extends RigidBody3D
## res://scenes/item/Item.tscn
##
## The HOST is always authoritative over an item's state, regardless of who
## is holding it — clients only ever *request* pickup/place, never set
## state directly. This keeps "who placed what" unambiguous and makes
## lock-on-complete trivial later (host just refuses requests on a locked
## slot).

@export var item_id: String = ""
@export var category: String = ""          # e.g. "potion", "tome", "artifact"
@export var display_name: String = ""
@export var description: String = ""       # the textual clue players read
var variant: int = 0      # which of the category's shapes (ItemCatalog.Variant)
var look_seed: int = 0    # tint + size, derived identically on every peer
@export var correct_slot_id: String = ""

var held_by_peer: int = 0                   # 0 = not held
var placed: bool = false
var current_slot: Node = null               # the ShelfSlot this item is sitting in, if placed
var _held_player_node: CoopPlayer = null

@onready var visual: Node3D = $Visual
@onready var hitbox_shape: CollisionShape3D = $Hitbox/CollisionShape3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var label: Label3D = $Label3D


@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer


func _ready() -> void:
	add_to_group("item")
	_refresh_clue_display()
	set_multiplayer_authority(1)  # host always owns item logic
	if multiplayer.is_server():
		# Don't send this item to a peer until its World has loaded —
		# otherwise the spawn arrives before the Items node exists and is
		# lost (NetworkManager flips visibility on _client_world_ready).
		synchronizer.add_visibility_filter(NetworkManager.is_peer_ready)
	else:
		# Clients never simulate item physics: the host is the only one
		# that does, and clients just show the synced transform. Otherwise
		# each client's local simulation drifts from the host's, and with
		# on-change sync, nothing corrects it once the host's copy rests.
		freeze = true


func _refresh_clue_display() -> void:
	# Shape comes from the item's variant; tint and size from its look_seed.
	# Colour is decoration only (DESIGN.md): the tint is drawn from one
	# palette shared by every type. Meshes named "Tint..." take the tint.
	var v: ItemCatalog.Variant = ItemCatalog.get_variant(category, variant)
	if v and visual and visual.get_child_count() == 0:
		var look := ItemCatalog.look_for_seed(look_seed)
		var tint: Color = look["tint"]
		var s: float = look["scale"]
		var model: Node3D = load(v.model_path).instantiate()
		visual.add_child(model)
		visual.scale = Vector3.ONE * s
		for node in model.find_children("Tint*", "MeshInstance3D"):
			var mi := node as MeshInstance3D
			var mat := (mi.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.albedo_color = tint
			if mat.emission_enabled:
				mat.emission = tint
			mi.set_surface_override_material(0, mat)
		# Physics box: sized to this model, resting on its base. Each item
		# gets its own shape (the scene's BoxShape3D is shared by all).
		var size: Vector3 = v.size * s
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = Vector3(0, size.y / 2.0, 0)
		# Aim box: a little bigger than the model, so thin things (keys,
		# scrolls) are easy to target — but never wider than a shelf slot.
		var aim := Vector3(
			clampf(size.x + 0.1, 0.16, 0.4),
			maxf(size.y + 0.06, 0.14),
			clampf(size.z + 0.1, 0.16, 0.4))
		var aim_shape := BoxShape3D.new()
		aim_shape.size = aim
		hitbox_shape.shape = aim_shape
		hitbox_shape.position = Vector3(0, aim.y / 2.0, 0)
		if label:
			label.position = Vector3(0, size.y + 0.14, 0)
	if label:
		var name_line := display_name if display_name != "" else item_id
		label.text = name_line + ("\n" + description if description != "" else "")


## Labels only show for the item the local player is looking at — 180
## floating labels at once is unreadable. Called by Player.gd each frame.
func set_label_visible(on: bool) -> void:
	if label:
		label.visible = on


# category/display_name/description arrive on clients via the
# MultiplayerSynchronizer at spawn time, after _ready() has already run
# with empty defaults — re-apply the clue display once they land.
func _set(property: StringName, value) -> bool:
	if property in ["category", "display_name", "description"] and is_inside_tree():
		call_deferred("_refresh_clue_display")
	return false


func _physics_process(_delta: float) -> void:
	# The aim box follows the physics box: off while carried, so your own
	# held item never blocks the crosshair.
	if hitbox_shape.disabled != collision.disabled:
		hitbox_shape.disabled = collision.disabled
	# Host drags a held item to its holder's hand each frame; the
	# MultiplayerSynchronizer below pushes the resulting position to
	# everyone else. Clients never move a held item themselves.
	if not multiplayer.is_server():
		return
	if held_by_peer != 0 and _held_player_node:
		var hold_point := _held_player_node.get_hold_point()
		if hold_point:
			global_position = hold_point.global_position
			global_rotation = hold_point.global_rotation


# ---------------------------------------------------------------------------
# Requests from any client (validated + executed on host only)
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable", "call_local")
func request_pickup() -> void:
	if not multiplayer.is_server():
		return
	# Trust the transport, not a parameter: the sender id can't be spoofed,
	# so one client can't make another player "pick up" items.
	var requesting_peer := multiplayer.get_remote_sender_id()
	if held_by_peer != 0:
		return  # someone's already holding it
	# Host-side carry limit. The client checks this too, but only against
	# pickups the host has already confirmed — spamming E before the
	# replies land would otherwise let a player exceed CARRY_CAPACITY.
	if _count_held_by(requesting_peer) >= CoopPlayer.CARRY_CAPACITY:
		return
	if placed:
		# Sitting in a slot: only a *wrong* placement can be picked back up —
		# ShelfSlot.locked is only ever true after a correct placement, so
		# this is the "unplace on wrong" / return-to-shelf flow. Reaching
		# in and taking a correctly-placed item is exactly what lock-on-
		# complete exists to prevent.
		if current_slot == null or current_slot.locked:
			return
		current_slot.host_free_slot()
		current_slot = null
		placed = false

	held_by_peer = requesting_peer
	freeze = true
	collision.disabled = true
	_held_player_node = _find_player(requesting_peer)
	_notify_player.rpc_id(requesting_peer, true)
	var game_state := get_tree().get_first_node_in_group("game_state")
	if game_state:
		game_state.host_note_pickup()  # first pickup of the round starts the clock


@rpc("any_peer", "reliable", "call_local")
func request_drop() -> void:
	if not multiplayer.is_server():
		return
	var releasing_peer := multiplayer.get_remote_sender_id()
	if held_by_peer != releasing_peer:
		return
	_notify_player.rpc_id(releasing_peer, false)
	_host_release_to_world()


const TOSS_SPEED := 6.5
const TOSS_LIFT := 2.2

## Toss the item forward from the holder's view. The host runs the throw's
## physics like any other item; clients just see the synced flight.
@rpc("any_peer", "reliable", "call_local")
func request_toss() -> void:
	if not multiplayer.is_server():
		return
	var tosser := multiplayer.get_remote_sender_id()
	if held_by_peer != tosser:
		return
	var player := _find_player(tosser)
	var forward := -global_transform.basis.z
	if player:
		forward = -player.camera.global_transform.basis.z
	_notify_player.rpc_id(tosser, false)
	_host_release_to_world()
	linear_velocity = forward * TOSS_SPEED + Vector3.UP * TOSS_LIFT
	angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


## Host-only. Called by NetworkManager when the holder disconnects, so their
## items fall to the floor instead of floating frozen with a dead
## held_by_peer that nobody can ever clear. No _notify_player here: the
## holder is gone, so there's no one to notify.
func host_force_release() -> void:
	if not multiplayer.is_server():
		return
	if held_by_peer == 0:
		return
	_host_release_to_world()


func _host_release_to_world() -> void:
	held_by_peer = 0
	_held_player_node = null
	freeze = false
	collision.disabled = false


# request_place is called on the ShelfSlot, not here — see ShelfSlot.gd,
# which calls these once it has validated category + lock state:

func host_attach_to_slot(slot_global_transform: Transform3D, slot: Node) -> void:
	if not multiplayer.is_server():
		return
	if held_by_peer != 0:
		_notify_player.rpc_id(held_by_peer, false)
	held_by_peer = 0
	_held_player_node = null
	placed = true
	current_slot = slot
	freeze = true
	collision.disabled = false
	global_transform = slot_global_transform


func _count_held_by(peer_id: int) -> int:
	var count := 0
	for other in get_tree().get_nodes_in_group("item"):
		if other.held_by_peer == peer_id:
			count += 1
	return count


func _find_player(peer_id: int) -> CoopPlayer:
	var players_container := get_tree().get_first_node_in_group("players_container")
	if players_container:
		return players_container.get_node_or_null(str(peer_id)) as CoopPlayer
	return null


@rpc("authority", "reliable", "call_local")
func _notify_player(now_held: bool) -> void:
	# Runs on the specific client that owns this pickup/drop, so their
	# local Player.gd can enforce carry capacity.
	var local_player: CoopPlayer = null
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			local_player = p as CoopPlayer
			break
	if local_player == null:
		return
	if now_held:
		local_player.note_item_held(self)
	else:
		local_player.note_item_released(self)
