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
@onready var clue_label: Label3D = $ClueLabel

const COLOR_CORRECT := Color(0.3, 0.9, 0.4)
const COLOR_WRONG := Color(0.9, 0.3, 0.3)

var _empty_color := Color(0.6, 0.6, 0.6)
var _indicator_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("shelf_slot")
	set_multiplayer_authority(1)
	# World.gd instances many ShelfSlots from one PackedScene, and Godot
	# shares a .tscn's sub-resources across instances unless given their
	# own copy — without this, painting one slot would repaint every slot.
	_indicator_material = StandardMaterial3D.new()
	if indicator:
		indicator.set_surface_override_material(0, _indicator_material)
	var cat := ItemCatalog.get_category(accepted_category)
	if cat:
		_empty_color = cat.color
		if clue_label:
			clue_label.text = cat.display_name
	_update_indicator(_empty_color)


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
	_update_indicator(COLOR_CORRECT if (is_filled and was_correct) else (COLOR_WRONG if is_filled else _empty_color))


func _update_indicator(color: Color) -> void:
	if _indicator_material:
		_indicator_material.albedo_color = color
