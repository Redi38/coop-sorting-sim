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

@onready var camera: Camera3D = $Camera3D
@onready var interact_ray: RayCast3D = $Camera3D/InteractRay
@onready var hold_point: Marker3D = $Camera3D/HoldPoint
@onready var nameplate: Label3D = $Nameplate
@onready var capacity_label: Label = $HUD/CapacityLabel

var held_items: Array[Node] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	var is_local := is_multiplayer_authority()
	camera.current = is_local
	set_process_unhandled_input(is_local)
	set_physics_process(is_local)
	capacity_label.get_parent().visible = is_local  # only the local player needs their own HUD
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_update_capacity_label()
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
	if held_items.size() >= CARRY_CAPACITY:
		return
	# Ask the host to validate + perform the pickup; host owns item state.
	item.rpc_id(1, "request_pickup", get_multiplayer_authority())


func _try_place(slot: Node) -> void:
	if held_items.is_empty():
		return
	var item := held_items[-1]
	slot.rpc_id(1, "request_place", item.get_path(), get_multiplayer_authority())


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
