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
@export var correct_slot_id: String = ""

var held_by_peer: int = 0                   # 0 = not held
var placed: bool = false
var _held_player_node: CoopPlayer = null

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var label: Label3D = $Label3D


func _ready() -> void:
	add_to_group("item")
	_refresh_clue_display()
	set_multiplayer_authority(1)  # host always owns item logic


func _refresh_clue_display() -> void:
	# The color clue: matches the ShelfSlot indicator for the same category,
	# so a player can sort by color alone before reading anything. The text
	# clue (name + short description) is the fallback / tie-breaker for
	# categories that end up sharing a similar color at a glance.
	var cat := ItemCatalog.get_category(category)
	if mesh and cat:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cat.color
		mesh.set_surface_override_material(0, mat)
	if label:
		var name_line := display_name if display_name != "" else item_id
		label.text = name_line + ("\n" + description if description != "" else "")


# category/display_name/description arrive on clients via the
# MultiplayerSynchronizer at spawn time, after _ready() has already run
# with empty defaults — re-apply the clue display once they land.
func _set(property: StringName, value) -> bool:
	if property in ["category", "display_name", "description"] and is_inside_tree():
		call_deferred("_refresh_clue_display")
	return false


func _physics_process(_delta: float) -> void:
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
func request_pickup(requesting_peer: int) -> void:
	if not multiplayer.is_server():
		return
	if placed or held_by_peer != 0:
		return  # already held or locked in a slot

	held_by_peer = requesting_peer
	freeze = true
	collision.disabled = true
	_held_player_node = _find_player(requesting_peer)
	_notify_player.rpc_id(requesting_peer, true)


@rpc("any_peer", "reliable", "call_local")
func request_drop() -> void:
	if not multiplayer.is_server():
		return
	var releasing_peer := multiplayer.get_remote_sender_id()
	if held_by_peer != releasing_peer:
		return
	_notify_player.rpc_id(releasing_peer, false)
	held_by_peer = 0
	_held_player_node = null
	freeze = false
	collision.disabled = false


# request_place is called on the ShelfSlot, not here — see ShelfSlot.gd,
# which calls these once it has validated category + lock state:

func host_attach_to_slot(slot_global_transform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	if held_by_peer != 0:
		_notify_player.rpc_id(held_by_peer, false)
	held_by_peer = 0
	_held_player_node = null
	placed = true
	freeze = true
	collision.disabled = false
	global_transform = slot_global_transform


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
