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
		# Plain felt: slots never hint at their type by colour (DESIGN.md —
		# the sign above the unit says what belongs here).
		_empty_color = FELT
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
	# Don't set filled/locked here: _sync_state (call_local) applies them on
	# every peer *including this one*, and needs to see the old state to
	# know this is a new placement (that's what plays the effects).
	# locked = correct: lock-on-complete, correct placements can't be undone.
	_sync_state.rpc(true, is_correct, is_correct, item.get_path())
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
func _sync_state(is_filled: bool, is_locked: bool, was_correct: bool, item_path := NodePath("")) -> void:
	# Effects only for live changes: apply_state (late-join snapshot, round
	# reset) stays silent.
	var newly_locked := is_locked and not locked
	var newly_wrong := is_filled and not was_correct and not filled
	apply_state(is_filled, is_locked, was_correct)
	var item := get_node_or_null(item_path) if item_path != NodePath("") else null
	if newly_locked:
		_flash(3.2)
		Sfx.play("place_correct", attach_point.global_position)
		var world := NetworkManager.world
		if world and world.has_method("spawn_sparkles"):
			world.spawn_sparkles(attach_point.global_position + Vector3(0, 0.12, 0), 14)
		if item and item.has_method("pop"):
			item.pop(1.3)
	elif newly_wrong:
		_flash(2.2)
		Sfx.play("place_wrong", attach_point.global_position)
		if item and item.has_method("wobble"):
			item.wobble()


## Brief bright glow on the felt pad that eases back to its resting level.
func _flash(energy: float) -> void:
	if _indicator_material == null:
		return
	var rest := _indicator_material.emission_energy_multiplier
	_indicator_material.emission_energy_multiplier = energy
	var tw := create_tween()
	tw.tween_property(_indicator_material, "emission_energy_multiplier", rest, 0.8).set_ease(Tween.EASE_OUT)


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
