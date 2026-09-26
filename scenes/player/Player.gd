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
const PING_RANGE := 40.0
const PING_COOLDOWN := 0.4
var _last_ping_time := -10.0
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

	if event.is_action_pressed("toss"):
		_try_toss()

	if event.is_action_pressed("ping"):
		try_ping()


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
		target = _item_from_collider(interact_ray.get_collider())
	if target == _hovered_item:
		return
	if is_instance_valid(_hovered_item):
		_hovered_item.set_label_visible(false)
	_hovered_item = target
	if _hovered_item:
		_hovered_item.set_label_visible(true)


## The crosshair usually hits an item's padded aim box (an Area3D child of
## the item), not the item body itself; either way, return the item.
func _item_from_collider(c: Object) -> Node:
	if c == null:
		return null
	if c.is_in_group("item"):
		return c
	var parent: Node = (c as Node).get_parent() if c is Node else null
	if parent and parent.is_in_group("item"):
		return parent
	return null


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

	var item := _item_from_collider(target)
	if item:
		_try_pickup(item)
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


func _try_toss() -> void:
	_prune_freed_items()
	if held_items.is_empty():
		return
	held_items[-1].request_toss.rpc_id(1)


## Pings whatever is under the crosshair, out to PING_RANGE (much further
## than you can reach). Shown to everyone — see World.show_ping.
func try_ping() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_ping_time < PING_COOLDOWN:
		return
	_last_ping_time = now
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * PING_RANGE
	# layer 1 = world + items (+ their aim boxes), layer 2 = shelf furniture
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var kind := "spot"
	var caption := ""
	var item := _item_from_collider(collider)
	if item:
		kind = "item"
		caption = item.display_name
		pos = item.global_position + Vector3(0, 0.5, 0)
	else:
		var cat_id := ""
		if collider.is_in_group("shelf_slot"):
			cat_id = collider.accepted_category
		elif collider is Node and (collider as Node).get_parent() and str((collider as Node).get_parent().name).begins_with("Shelf_"):
			cat_id = str((collider as Node).get_parent().name).trim_prefix("Shelf_")
		if cat_id != "":
			kind = "shelf"
			var cat := ItemCatalog.get_category(cat_id)
			caption = cat.display_name if cat else cat_id
			pos += Vector3(0, 0.35, 0)
		else:
			pos += Vector3(0, 0.25, 0)
	# Only to peers whose World has loaded (NetworkManager.players is the
	# ready-list), so nobody gets an RPC for a node they don't have yet.
	var me := multiplayer.get_unique_id()
	for peer_id in NetworkManager.players:
		if peer_id != me:
			_show_ping.rpc_id(peer_id, kind, pos, caption)
	_show_ping(kind, pos, caption)


@rpc("authority", "reliable")
func _show_ping(kind: String, pos: Vector3, caption: String) -> void:
	var world := NetworkManager.world
	if world and world.has_method("show_ping"):
		world.show_ping(get_multiplayer_authority(), kind, pos, caption)


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
