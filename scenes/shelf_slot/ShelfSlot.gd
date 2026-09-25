extends Area3D
## res://scenes/shelf_slot/ShelfSlot.tscn
##
## Host-authoritative, same pattern as Item.gd. Once `locked` is true the
## slot refuses every further place/empty request — this is the
## "lock-on-complete" rule from the design doc.
##
## The slot's origin is the shelf board's top surface: the Indicator is a
## thin felt pad lying on it, and items (whose pivots are at their base)
## attach right at AttachPoint. One sign per shelf unit names the category
## (built by World.gd), so the per-slot ClueLabel stays hidden.

@export var slot_id: String = ""
@export var accepted_category: String = ""

var filled: bool = false
var locked: bool = false
var correct: bool = false   # true when the item currently in the slot matches accepted_category

@onready var indicator: MeshInstance3D = $Indicator
@onready var attach_point: Marker3D = $AttachPoint
@onready var clue_label: Label3D = $ClueLabel

const COLOR_CORRECT := Color(0.52, 0.74, 0.46)
const COLOR_WRONG := Color(0.82, 0.42, 0.32)
const FELT := Color(0.24, 0.17, 0.13)

var _empty_color := FELT
var _indicator_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("shelf_slot")
	set_multiplayer_authority(1)
	# World.gd instances many ShelfSlots from one PackedScene, and Godot
	# shares a .tscn's sub-resources across instances unless given their
	# own copy — without this, painting one slot would repaint every slot.
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.roughness = 1.0
	_indicator_material.emission_enabled = true
	_indicator_material.emission_energy_multiplier = 0.0
	if indicator:
		indicator.set_surface_override_material(0, _indicator_material)
	var cat := ItemCatalog.get_category(accepted_category)
	if cat:
		# Muted felt with a hint of the category color, so empty slots
		# read as "part of the furniture" rather than bright UI squares.
		_empty_color = FELT.lerp(cat.color, 0.35)
		if clue_label:
			clue_label.text = cat.display_name
	_update_indicator(_empty_color)


@rpc("any_peer", "reliable", "call_local")
func request_place(item_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if locked:
		return
	if filled:
		return  # a wrong item is already sitting here — pick it up first
	var requesting_peer := multiplayer.get_remote_sender_id()
	var item: CoopItem = get_node_or_null(item_path) as CoopItem
	if item == null or item.held_by_peer != requesting_peer:
		return  # stale request or the player isn't actually holding it

	var is_correct := item.category == accepted_category
	item.host_attach_to_slot(attach_point.global_transform, self)
	filled = true
	if is_correct:
		locked = true  # lock-on-complete: correct placements can't be undone
	_sync_state.rpc(filled, locked, is_correct)
	var game_state := get_tree().get_first_node_in_group("game_state")
	if game_state:
		game_state.host_record_placement(requesting_peer, item.category, is_correct)


# Called directly (host-side, not an RPC) by CoopItem.request_pickup when a
# *wrong* item sitting in this slot gets picked back up — the "unplace on
# wrong" flow. Never fires on a locked slot: request_pickup checks `locked`
# before calling this, and a correct placement is the only way `locked`
# becomes true.
func host_free_slot() -> void:
	if not multiplayer.is_server():
		return
	filled = false
	_sync_state.rpc(false, locked, false)


@rpc("authority", "reliable", "call_local")
func _sync_state(is_filled: bool, is_locked: bool, was_correct: bool) -> void:
	apply_state(is_filled, is_locked, was_correct)


## Applies slot state locally without an RPC. Used by _sync_state and by
## World's late-join snapshot, which sends every slot's state in one RPC
## instead of 180 individual ones.
func apply_state(is_filled: bool, is_locked: bool, was_correct: bool) -> void:
	filled = is_filled
	locked = is_locked
	correct = is_filled and was_correct
	_update_indicator(COLOR_CORRECT if (is_filled and was_correct) else (COLOR_WRONG if is_filled else _empty_color))


func _update_indicator(color: Color) -> void:
	if _indicator_material:
		_indicator_material.albedo_color = color
		# Soft glow for feedback (correct = gentle green, wrong = warm red);
		# empty slots don't glow.
		var glowing := color != _empty_color
		_indicator_material.emission = color
		_indicator_material.emission_energy_multiplier = 0.45 if glowing else 0.0
