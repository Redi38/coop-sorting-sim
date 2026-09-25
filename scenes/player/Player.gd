class_name CoopPlayer
extends CharacterBody3D
## res://scenes/player/Player.tscn
##
## Only the peer that owns this node (get_multiplayer_authority()) reads
## input and moves the body; everyone else just sees the synced transform
## via the MultiplayerSynchronizer on this scene.

const SPEED := 4.5
const JUMP_VELOCITY := 4.0
const MOUSE_SENSITIVITY := 0.0025
const INTERACT_RANGE := 2.5
const CARRY_CAPACITY := 3
# Robe/hat colours, picked per player so friends can tell each other apart.
const ROBE_COLORS := [
	Color(0.45, 0.28, 0.52),  # plum
	Color(0.2, 0.46, 0.48),   # teal
	Color(0.68, 0.36, 0.22),  # rust
	Color(0.38, 0.5, 0.26),   # moss
]

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var hold_point: Marker3D = $Camera3D/HoldPoint
@onready var nameplate: Label3D = $Nameplate
@onready var capacity_label: Label = $HUD/CapacityLabel

var held_items: Array[Node] = []
var _hovered_item: Node = null
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	# Only sync our transform to peers whose World (and therefore our node)
	# exists — see NetworkManager.is_peer_ready.
	$MultiplayerSynchronizer.add_visibility_filter(NetworkManager.is_peer_ready)
	var is_local := is_multiplayer_authority()
	_apply_cosmetics(is_local)
	camera.current = is_local
	set_process_unhandled_input(is_local)
	set_physics_process(is_local)
	capacity_label.get_parent().visible = is_local  # only the local player needs their own HUD
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_update_capacity_label()
		var game_state := get_tree().get_first_node_in_group("game_state")
		if game_state:
			game_state.round_reset.connect(_on_round_reset)
	var id := get_multiplayer_authority()
	if NetworkManager.players.has(id):
		nameplate.text = NetworkManager.players[id].get("name", "Player")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("drop"):
		_try_drop()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	_update_hover()


## Shows the label of the item under the crosshair (and only that one).
func _update_hover() -> void:
	var target: Node = null
	if interact_ray.is_colliding():
		var c := interact_ray.get_collider()
		if c and c.is_in_group("item"):
			target = c
	if target == _hovered_item:
		return
	if is_instance_valid(_hovered_item):
		_hovered_item.set_label_visible(false)
	_hovered_item = target
	if _hovered_item:
		_hovered_item.set_label_visible(true)


func _apply_cosmetics(is_local: bool) -> void:
	var robe: Color = ROBE_COLORS[get_multiplayer_authority() % ROBE_COLORS.size()]
	var robe_mat := StandardMaterial3D.new()
	robe_mat.albedo_color = robe
	robe_mat.roughness = 0.9
	var hat_mat := StandardMaterial3D.new()
	hat_mat.albedo_color = robe.darkened(0.35)
	hat_mat.roughness = 0.85
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.1, 0.07, 0.06)
	eye_mat.roughness = 0.2
	$BodyMesh.material_override = robe_mat
	$HatCone.material_override = hat_mat
	$HatBrim.material_override = hat_mat
	$EyeL.material_override = eye_mat
	$EyeR.material_override = eye_mat
	# First person: your own body would block the camera.
	for part in [$BodyMesh, $EyeL, $EyeR, $HatCone, $HatBrim, nameplate]:
		part.visible = not is_local


func _try_interact() -> void:
	if not interact_ray.is_colliding():
		return
	var target := interact_ray.get_collider()
	if target == null:
		return

	if target.is_in_group("item"):
		_try_pickup(target)
	elif target.is_in_group("shelf_slot"):
		_try_place(target)


func _try_pickup(item: Node) -> void:
	_prune_freed_items()
	if held_items.size() >= CARRY_CAPACITY:
		return
	# Ask the host to validate + perform the pickup; host owns item state
	# and identifies us by our peer id, so no id is passed.
	item.request_pickup.rpc_id(1)


func _try_place(slot: Node) -> void:
	_prune_freed_items()
	if held_items.is_empty():
		return
	var item := held_items[-1]
	slot.request_place.rpc_id(1, item.get_path())


func _try_drop() -> void:
	_prune_freed_items()
	if held_items.is_empty():
		return
	held_items[-1].request_drop.rpc_id(1)


# Called locally by Item.gd (same peer) once the host confirms this player
# now holds / no longer holds a given item, so carry-capacity checks work
# without every peer needing authority over the item.
func note_item_held(item: Node) -> void:
	if item not in held_items:
		held_items.append(item)
	_update_capacity_label()


func note_item_released(item: Node) -> void:
	held_items.erase(item)
	_update_capacity_label()


func _update_capacity_label() -> void:
	if capacity_label:
		capacity_label.text = "Carrying: %d / %d" % [held_items.size(), CARRY_CAPACITY]


func get_hold_point() -> Marker3D:
	return hold_point


func _prune_freed_items() -> void:
	held_items.assign(held_items.filter(func(i): return is_instance_valid(i)))


func _on_round_reset() -> void:
	# The host despawned every item; our local carried list pointed at them.
	held_items.clear()
	_update_capacity_label()


## Host asks the owning peer to move its own body (we're authoritative over
## our transform, so the host can't just set it). "any_peer" because this
## node's authority is its owner, not the host — so check the sender here.
@rpc("any_peer", "reliable", "call_local")
func teleport(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	global_position = pos
	velocity = Vector3.ZERO
