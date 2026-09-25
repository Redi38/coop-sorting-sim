extends Node3D
## res://scenes/world/World.tscn
##
## Milestone-1 room: one shared space, a grid of shelf slots, and a set of
## items the host spawns at runtime through the MultiplayerSpawner so every
## client sees the same set without hand-authoring per-item replication.
## Item/category data lives in ItemCatalog (res://data/item_catalog.gd), not
## here — this script just decides how many items/slots to place and where.

const ITEM_SCENE := preload("res://scenes/item/Item.tscn")
const SLOT_SCENE := preload("res://scenes/shelf_slot/ShelfSlot.tscn")

# Raised toward the design doc's 150-300 target now that the room is sized
# to fit it (50x50 floor, see World.tscn). ItemCatalog's get_item_templates()
# cycles its hand-authored pool with numbered repeats to reach this count.
const TARGET_ITEM_COUNT := 180
# One slot per item within a category (items are 60/category at the count
# above: 180 / 3 categories), since each item needs its own lockable slot.
const SLOTS_PER_CATEGORY := 60
# Each category gets one bookshelf unit: SLOTS_PER_ROW columns, stacked
# into as many shelves (levels) as needed — 60 slots = 12 x 5.
const SLOTS_PER_ROW := 12
const SLOT_SPACING := 0.5          # between columns, metres
const LEVEL_HEIGHT := 0.5          # between shelf boards
const FIRST_LEVEL_Y := 0.3         # top surface of the lowest board
const SHELF_FRONT_Z := -8.0        # front face of every unit
const SHELF_DEPTH := 0.42
const SHELF_CATEGORY_GAP := 2.2    # walkway between units
const SCATTER_HALF_EXTENT := 18.0

const MAT_SHELF := preload("res://assets/materials/shelf_wood.tres")
const MAT_PARCHMENT := preload("res://assets/materials/parchment.tres")
const MAT_BRASS := preload("res://assets/materials/brass.tres")
const MAT_GLOW := preload("res://assets/materials/lantern_glow.tres")
const MAT_RUG := preload("res://assets/materials/rug.tres")
const SIGN_FONT := preload("res://assets/fonts/Alegreya.ttf")
const INK := Color(0.2, 0.12, 0.07)

@onready var spawn_points_node: Node3D = $SpawnPoints
@onready var items_container: Node3D = $Items
@onready var shelf_slots_node: Node3D = $ShelfSlots
@onready var players_container: Node3D = $Players
@onready var game_state: Node = $GameState  # GameState.gd


func _ready() -> void:
	players_container.add_to_group("players_container")

	var spawn_points: Array[Node3D] = []
	for child in spawn_points_node.get_children():
		spawn_points.append(child as Node3D)

	NetworkManager.register_world(self, spawn_points)

	# Slot layout is pure, deterministic math over ItemCatalog's fixed
	# category list — every peer runs this and gets an identical node tree,
	# so ShelfSlot's host-authoritative RPCs resolve to matching NodePaths
	# on host and clients alike without needing a MultiplayerSpawner.
	_spawn_shelf_slots()
	_build_room_trim()

	if multiplayer.is_server():
		game_state.host_setup(_spawn_items())
	else:
		# Slot state only broadcasts on change, so a client joining mid-game
		# would see every slot as empty. Ask the host for a snapshot now
		# that our own slot nodes exist to receive it.
		_request_slot_states.rpc_id(1)


func _spawn_shelf_slots() -> void:
	var categories := ItemCatalog.get_categories()
	var levels := int(ceil(float(SLOTS_PER_CATEGORY) / SLOTS_PER_ROW))
	var unit_width := SLOTS_PER_ROW * SLOT_SPACING
	var cat_x_stride := unit_width + SHELF_CATEGORY_GAP
	var cat_x_start := -(categories.size() - 1) / 2.0 * cat_x_stride
	var slot_z := SHELF_FRONT_Z - SHELF_DEPTH / 2.0
	for cat_index in categories.size():
		var cat := categories[cat_index]
		var cat_center_x := cat_x_start + cat_index * cat_x_stride
		_build_shelf_unit(cat, Vector3(cat_center_x, 0, slot_z), unit_width, levels)
		for col in SLOTS_PER_CATEGORY:
			var slot: Area3D = SLOT_SCENE.instantiate()
			slot.name = "Slot_%s_%d" % [cat.id, col]
			slot.slot_id = "slot_%s_%d" % [cat.id, col]
			slot.accepted_category = cat.id
			shelf_slots_node.add_child(slot)
			var level := col / SLOTS_PER_ROW
			var col_in_row := col % SLOTS_PER_ROW
			var x := cat_center_x + (col_in_row - (SLOTS_PER_ROW - 1) / 2.0) * SLOT_SPACING
			# Slot origin = top surface of its shelf board (see ShelfSlot.gd).
			slot.position = Vector3(x, FIRST_LEVEL_Y + level * LEVEL_HEIGHT, slot_z)


## Builds one bookshelf unit's furniture around `center` (its footprint
## centre on the floor). Pure visuals + one player-blocking collider; the
## ShelfSlots themselves are added separately. Deterministic, so every
## peer builds the same thing without any networking.
func _build_shelf_unit(cat, center: Vector3, inner_width: float, levels: int) -> void:
	var unit := Node3D.new()
	unit.name = "Shelf_%s" % cat.id
	$Furniture.add_child(unit)
	unit.position = center
	var d := SHELF_DEPTH
	var w := inner_width + 0.12
	var top_y := FIRST_LEVEL_Y + levels * LEVEL_HEIGHT
	# plinth, boards, sides, back, crown
	_box(unit, Vector3(w, FIRST_LEVEL_Y - 0.02, d), Vector3(0, (FIRST_LEVEL_Y - 0.02) / 2.0, 0), MAT_SHELF)
	for level in levels:
		var y := FIRST_LEVEL_Y + level * LEVEL_HEIGHT
		_box(unit, Vector3(inner_width, 0.04, d), Vector3(0, y - 0.02, 0), MAT_SHELF)
	for side in [-1, 1]:
		_box(unit, Vector3(0.06, top_y, d), Vector3(side * (w - 0.06) / 2.0, top_y / 2.0, 0), MAT_SHELF)
	_box(unit, Vector3(w, top_y, 0.03), Vector3(0, top_y / 2.0, -d / 2.0 + 0.015), MAT_SHELF)
	_box(unit, Vector3(w + 0.12, 0.07, d + 0.08), Vector3(0, top_y + 0.035, 0.02), MAT_SHELF)

	# Sign: wooden frame + parchment face + name and a one-line rule, so
	# players can reason about what belongs here (DESIGN.md: "Figure out
	# what it is").
	var sign_y := top_y + 0.42
	_box(unit, Vector3(2.5, 0.66, 0.05), Vector3(0, sign_y, d / 2.0 - 0.06), MAT_SHELF)
	_box(unit, Vector3(2.36, 0.54, 0.02), Vector3(0, sign_y, d / 2.0 - 0.025), MAT_PARCHMENT)
	var title := _sign_label(cat.display_name, 150)
	title.position = Vector3(0, sign_y + 0.07, d / 2.0 - 0.012)
	unit.add_child(title)
	var rule := _sign_label(cat.sign_text, 64)
	rule.position = Vector3(0, sign_y - 0.16, d / 2.0 - 0.012)
	unit.add_child(rule)
	# a small glowing gem of the category colour on each side of the title
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = cat.color
	gem_mat.emission_enabled = true
	gem_mat.emission = cat.color
	gem_mat.emission_energy_multiplier = 0.8
	for side in [-1, 1]:
		var gem := MeshInstance3D.new()
		var gem_mesh := SphereMesh.new()
		gem_mesh.radius = 0.05
		gem_mesh.height = 0.1
		gem.mesh = gem_mesh
		gem.material_override = gem_mat
		gem.position = Vector3(side * 0.98, sign_y + 0.07, d / 2.0)
		unit.add_child(gem)

	# Sconces: brass cap + glowing bulb either side of the sign, with one
	# warm light in front of the unit so the shelves are pools of light.
	for side in [-1, 1]:
		var sx: float = side * 1.45
		_box(unit, Vector3(0.1, 0.05, 0.12), Vector3(sx, sign_y + 0.14, d / 2.0), MAT_BRASS)
		var bulb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		bulb.mesh = sphere
		bulb.material_override = MAT_GLOW
		bulb.position = Vector3(sx, sign_y + 0.07, d / 2.0 + 0.02)
		unit.add_child(bulb)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.52)
	light.light_energy = 2.4
	light.omni_range = 6.5
	light.omni_attenuation = 1.2
	# No shadows: the unit's own top board would shade its upper shelves.
	# SSAO in the environment gives the shelves their depth instead.
	light.shadow_enabled = false
	light.position = Vector3(0, top_y + 0.2, d / 2.0 + 1.1)
	unit.add_child(light)

	# Rug runner in front of the unit.
	_box(unit, Vector3(w, 0.012, 1.7), Vector3(0, 0.006, d / 2.0 + 1.0), MAT_RUG)

	# One collider for the whole unit on physics layer 2: blocks players
	# (Player.tscn's mask includes layer 2) but not the interact ray or
	# items (layer 1 only), so slots stay targetable.
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, top_y + 0.1, d)
	shape.shape = box
	shape.position = Vector3(0, (top_y + 0.1) / 2.0, 0)
	body.add_child(shape)
	unit.add_child(body)


const MIN_ITEM_SPACING := 0.5

## A random floor point in the scatter area at least MIN_ITEM_SPACING from
## every point in `used` (rejection sampling; the area is ~36 x 16 m, so
## this finds a spot almost immediately even for hundreds of items).
func _free_scatter_point(used: Array[Vector3]) -> Vector3:
	var p := Vector3.ZERO
	for attempt in 60:
		p = Vector3(randf_range(-SCATTER_HALF_EXTENT, SCATTER_HALF_EXTENT), 0.002,
			randf_range(2.0, SCATTER_HALF_EXTENT))
		var ok := true
		for q in used:
			if p.distance_squared_to(q) < MIN_ITEM_SPACING * MIN_ITEM_SPACING:
				ok = false
				break
		if ok:
			return p
	return p  # area is saturated; accept an overlap rather than loop forever


## Ceiling, beams and wainscoting. Visual only. None of it casts shadows,
## so the (fake) window light still reaches the floor through the ceiling.
func _build_room_trim() -> void:
	var trim := Node3D.new()
	trim.name = "RoomTrim"
	$Furniture.add_child(trim)
	var room_min := Vector2(-21.0, -8.8)   # inner wall faces (x, z)
	var room_max := Vector2(21.0, 20.8)
	var size := room_max - room_min
	var mid := (room_min + room_max) / 2.0
	var ceiling := _box(trim, Vector3(size.x, 0.2, size.y), Vector3(mid.x, 4.6, mid.y), preload("res://assets/materials/wall.tres"))
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bx := room_min.x + 1.5
	while bx < room_max.x:
		var beam := _box(trim, Vector3(0.28, 0.32, size.y), Vector3(bx, 4.34, mid.y), MAT_SHELF)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bx += 3.0
	# wainscot: wood panel + rail around the lower walls
	var walls := [
		[Vector3(size.x, 1.0, 0.04), Vector3(mid.x, 0.5, room_min.y + 0.02)],
		[Vector3(size.x, 1.0, 0.04), Vector3(mid.x, 0.5, room_max.y - 0.02)],
		[Vector3(0.04, 1.0, size.y), Vector3(room_min.x + 0.02, 0.5, mid.y)],
		[Vector3(0.04, 1.0, size.y), Vector3(room_max.x - 0.02, 0.5, mid.y)],
	]
	for w in walls:
		_box(trim, w[0], w[1], MAT_SHELF)
		var rail_size: Vector3 = w[0]
		rail_size.y = 0.07
		rail_size.x = maxf(rail_size.x, 0.09) if rail_size.x < 1.0 else rail_size.x
		rail_size.z = maxf(rail_size.z, 0.09) if rail_size.z < 1.0 else rail_size.z
		var rail_pos: Vector3 = w[1]
		rail_pos.y = 1.02
		_box(trim, rail_size, rail_pos, MAT_SHELF)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _sign_label(text: String, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = SIGN_FONT
	l.font_size = size
	l.pixel_size = 0.002
	l.modulate = INK
	l.outline_size = 0
	l.shaded = false
	return l


## Spawns the round's items and returns their templates (GameState uses
## them to know totals per category).
func _spawn_items() -> Array[Dictionary]:
	var templates := ItemCatalog.get_item_templates(TARGET_ITEM_COUNT)
	var used_points: Array[Vector3] = []
	for data in templates:
		var item: CoopItem = ITEM_SCENE.instantiate() as CoopItem
		item.name = data["id"]
		item.item_id = data["id"]
		item.category = data["category"]
		item.display_name = data["name"]
		item.description = data["description"]
		items_container.add_child(item, true)
		# scatter across the open half of the room (positive Z), away from
		# the shelf wall which now sits around z ≈ -6 to -13; replace with
		# real scatter points once the level art exists
		# Set straight on the floor (pivots are at the base), never
		# overlapping another item: overlapping bodies push each other
		# forever, never sleep, and cost network traffic every frame.
		item.global_position = _free_scatter_point(used_points)
		used_points.append(item.global_position)
		# random facing so the floor looks like a real mess, not a grid
		item.rotation.y = randf() * TAU
	return templates


# ---------------------------------------------------------------------------
# Late-join sync — host sends every slot's state to one peer in a single RPC
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_slot_states() -> void:
	if not multiplayer.is_server():
		return
	var states: Array = []
	for slot in shelf_slots_node.get_children():
		if slot.filled or slot.locked:
			states.append([slot.name, slot.filled, slot.locked, slot.correct])
	_receive_slot_states.rpc_id(multiplayer.get_remote_sender_id(), states)


@rpc("authority", "reliable")
func _receive_slot_states(states: Array) -> void:
	for entry in states:
		var slot := shelf_slots_node.get_node_or_null(NodePath(entry[0]))
		if slot:
			slot.apply_state(entry[1], entry[2], entry[3])


# ---------------------------------------------------------------------------
# Round restart — host only, in place (nobody reconnects or reloads scenes)
# ---------------------------------------------------------------------------

func host_restart_round() -> void:
	if not multiplayer.is_server():
		return
	# Despawn every item. remove_child (not just queue_free) takes the node
	# out of the tree immediately, so the MultiplayerSpawner despawns it on
	# clients now and the fresh items can reuse the same names this frame.
	for item in get_tree().get_nodes_in_group("item"):
		items_container.remove_child(item)
		item.queue_free()
	_reset_slots.rpc()
	# Clear carried-item lists and the win screen everywhere *before* the
	# new round's state lands, so nobody's HUD briefly says "Carrying 3/3".
	game_state.notify_round_reset.rpc()
	game_state.host_setup(_spawn_items())
	# Players own their own transform, so ask each one to move itself.
	var i := 0
	for player in players_container.get_children():
		var point: Node3D = spawn_points_node.get_child(i % spawn_points_node.get_child_count())
		player.teleport.rpc_id(int(player.name), point.global_position)
		i += 1


@rpc("authority", "reliable", "call_local")
func _reset_slots() -> void:
	for slot in shelf_slots_node.get_children():
		slot.apply_state(false, false, false)
