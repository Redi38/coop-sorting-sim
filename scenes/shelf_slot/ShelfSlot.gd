extends Area3D
## res://scenes/shelf_slot/ShelfSlot.tscn
##
## Host-authoritative, same pattern as Item.gd. Once `locked` is true the
## slot refuses every further place/empty request — this is the
## "lock-on-complete" rule from the design doc.

@export var slot_id: String = ""
@export var accepted_category: String = ""

var filled: bool = false
var locked: bool = false

@onready var indicator: MeshInstance3D = $Indicator
@onready var attach_point: Marker3D = $AttachPoint

const COLOR_EMPTY := Color(0.6, 0.6, 0.6)
const COLOR_CORRECT := Color(0.3, 0.9, 0.4)
const COLOR_WRONG := Color(0.9, 0.3, 0.3)


func _ready() -> void:
	add_to_group("shelf_slot")
	set_multiplayer_authority(1)
	_update_indicator(COLOR_EMPTY)


@rpc("any_peer", "reliable", "call_local")
func request_place(item_path: NodePath, requesting_peer: int) -> void:
	if not multiplayer.is_server():
		return
	if locked:
		return
	var item: CoopItem = get_node_or_null(item_path) as CoopItem
	if item == null or item.held_by_peer != requesting_peer:
		return  # stale request or the player isn't actually holding it

	var correct := item.category == accepted_category
	item.host_attach_to_slot(attach_point.global_transform)
	filled = true
	if correct:
		locked = true  # lock-on-complete: correct placements can't be undone
	_sync_state.rpc(filled, locked, correct)


@rpc("authority", "reliable", "call_local")
func _sync_state(is_filled: bool, is_locked: bool, was_correct: bool) -> void:
	filled = is_filled
	locked = is_locked
	_update_indicator(COLOR_CORRECT if (is_filled and was_correct) else (COLOR_WRONG if is_filled else COLOR_EMPTY))


func _update_indicator(color: Color) -> void:
	if indicator and indicator.get_surface_override_material_count() > 0:
		var mat := indicator.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat.albedo_color = color
