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
const TARGET_ITEM_COUNT := 180    # shelf capacity (the 4-player archive)
# The archive scales with the crew so solo isn't a slog and four players
# aren't done in minutes: 60 solo, +40 per extra player, capped at shelf
# capacity. Friends who join before the first pickup grow the archive.
const BASE_ITEMS := 60
const ITEMS_PER_EXTRA_PLAYER := 40
# One slot per item within a category (items are 60/category at the count
# above: 180 / 3 categories), since each item needs its own lockable slot.
# Every type gets the same number of slots (180 / 6 = 30).
var SLOTS_PER_CATEGORY: int = int(ceil(float(TARGET_ITEM_COUNT) / ItemCatalog.get_categories().size()))
# Each category gets one bookshelf unit: SLOTS_PER_ROW columns, stacked
# into as many shelves (levels) as needed — 60 slots = 12 x 5.
const SLOTS_PER_ROW := 10
const SLOT_SPACING := 0.45         # between columns, metres
const LEVEL_HEIGHT := 0.5          # between shelf boards
const FIRST_LEVEL_Y := 0.3         # top surface of the lowest board
const SHELF_FRONT_Z := -8.0        # front face of every unit
const SHELF_DEPTH := 0.42
const SHELF_CATEGORY_GAP := 2.2    # preferred walkway between units
const MIN_UNIT_GAP := 1.3          # squeeze to this before wrapping to side walls
const ROOM_HALF_WIDTH := 21.0      # inner wall faces at x = +/-21 (see World.tscn)
const WALL_MARGIN := 1.0
const SIDE_WALL_Z_START := -5.0    # first side-wall unit centre
const SCATTER_HALF_EXTENT := 18.0

const MAT_SHELF := preload("res://assets/materials/shelf_wood.tres")
const MAT_PARCHMENT := preload("res://assets/materials/parchment.tres")
const MAT_BRASS := preload("res://assets/materials/brass.tres")
const MAT_GLOW := preload("res://assets/materials/lantern_glow.tres")
const MAT_RUG := preload("res://assets/materials/rug.tres")
const SIGN_FONT := preload("res://assets/fonts/Alegreya.ttf")
const INK := Color(0.12, 0.065, 0.03)
const CoopPlayerScript := preload("res://scenes/player/Player.gd")

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
	_build_dust()
	game_state.state_changed.connect(_update_warmth)
	game_state.category_completed.connect(_on_category_completed)
	_update_warmth(true)

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
	var placements := _shelf_unit_transforms(categories.size(), unit_width + 0.12)
	for cat_index in categories.size():
		var cat := categories[cat_index]
		var unit_xform: Transform3D = placements[cat_index]
		_build_shelf_unit(cat, unit_xform, unit_width, levels)
		for col in SLOTS_PER_CATEGORY:
			var slot: Area3D = SLOT_SCENE.instantiate()
			slot.name = "Slot_%s_%d" % [cat.id, col]
			slot.slot_id = "slot_%s_%d" % [cat.id, col]
			slot.accepted_category = cat.id
			shelf_slots_node.add_child(slot)
			var level := col / SLOTS_PER_ROW
			var col_in_row := col % SLOTS_PER_ROW
			# Local to the unit: x across, y up, the unit faces its local +z.
			# Slot origin = top surface of its shelf board (see ShelfSlot.gd).
			var local := Vector3((col_in_row - (SLOTS_PER_ROW - 1) / 2.0) * SLOT_SPACING,
				FIRST_LEVEL_Y + level * LEVEL_HEIGHT, 0)
			slot.global_transform = unit_xform * Transform3D(Basis(), local)


## Where each shelf unit stands: its footprint centre on the floor, facing
## into the room (local +z). Units line the back wall first, centred; any
## that don't fit continue onto the side walls, alternating left/right.
## Pure maths on constants, so every peer computes identical transforms.
func _shelf_unit_transforms(count: int, unit_width: float) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var usable := 2.0 * (ROOM_HALF_WIDTH - WALL_MARGIN)
	var on_back := count
	var gap := SHELF_CATEGORY_GAP
	if count > 1:
		gap = minf(SHELF_CATEGORY_GAP, (usable - count * unit_width) / (count - 1))
	if gap < MIN_UNIT_GAP:
		on_back = maxi(1, int(floor((usable + MIN_UNIT_GAP) / (unit_width + MIN_UNIT_GAP))))
		gap = minf(SHELF_CATEGORY_GAP, (usable - on_back * unit_width) / maxf(on_back - 1, 1))
	var stride := unit_width + gap
	var z := SHELF_FRONT_Z - SHELF_DEPTH / 2.0
	for i in on_back:
		var x := (i - (on_back - 1) / 2.0) * stride
		result.append(Transform3D(Basis(), Vector3(x, 0, z)))
	var side_x := ROOM_HALF_WIDTH - 0.2 - SHELF_DEPTH / 2.0
	for i in count - on_back:
		var left := i % 2 == 0
		var zc := SIDE_WALL_Z_START + (i / 2) * (unit_width + SHELF_CATEGORY_GAP) + unit_width / 2.0
		var basis := Basis(Vector3.UP, PI / 2.0 if left else -PI / 2.0)  # face into the room
		result.append(Transform3D(basis, Vector3(-side_x if left else side_x, 0, zc)))
	return result


## Builds one bookshelf unit's furniture around `center` (its footprint
## centre on the floor). Pure visuals + one player-blocking collider; the
## ShelfSlots themselves are added separately. Deterministic, so every
## peer builds the same thing without any networking.
func _build_shelf_unit(cat, xform: Transform3D, inner_width: float, levels: int) -> void:
	var unit := Node3D.new()
	unit.name = "Shelf_%s" % cat.id
	$Furniture.add_child(unit)
	unit.transform = xform
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
	var title := _sign_label(cat.display_name, 170)
	title.position = Vector3(0, sign_y + 0.07, d / 2.0 - 0.012)
	unit.add_child(title)
	var rule := _sign_label(cat.sign_text, 64)
	rule.position = Vector3(0, sign_y - 0.16, d / 2.0 - 0.012)
	unit.add_child(rule)
	# Brass statuettes of every shape this type comes in, standing on the
	# sign — a shape clue that doesn't use colour. (Crystals show both an
	# orb and a cluster: same type, different shapes.)
	var n: int = cat.variants.size()
	for vi in n:
		var statue: Node3D = load(cat.variants[vi].model_path).instantiate()
		for mi in statue.find_children("*", "MeshInstance3D"):
			(mi as MeshInstance3D).material_override = MAT_BRASS
		statue.scale = Vector3.ONE * 1.9
		var sx := (vi - (n - 1) / 2.0) * 0.6
		statue.position = Vector3(sx, sign_y + 0.33, d / 2.0 - 0.06)
		# Flat things (keys, tomes, scrolls) would lie invisibly on top of
		# the sign, so stand them up, tipped toward the viewer.
		var vsize: Vector3 = cat.variants[vi].size
		if vsize.y < 0.12:
			statue.rotation.x = deg_to_rad(75)
			statue.position.y += vsize.z / 2.0 * statue.scale.y
		unit.add_child(statue)

	# Sconces: brass cap + glowing bulb either side of the sign, with one
	# warm light in front of the unit so the shelves are pools of light.
	# Each unit gets its own glow material so it can light up on its own
	# when its type is complete.
	var unit_glow := MAT_GLOW.duplicate() as StandardMaterial3D
	_unit_glow[cat.id] = unit_glow
	for side in [-1, 1]:
		var sx: float = side * 1.45
		_box(unit, Vector3(0.1, 0.05, 0.12), Vector3(sx, sign_y + 0.14, d / 2.0), MAT_BRASS)
		var bulb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		bulb.mesh = sphere
		bulb.material_override = unit_glow
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
	# Low and forward: lights the shelves without blowing out the sign.
	light.position = Vector3(0, top_y - 0.2, d / 2.0 + 1.5)
	unit.add_child(light)
	_unit_lights[cat.id] = light
	_unit_centres[cat.id] = unit.to_global(Vector3(0, top_y * 0.6, d / 2.0))

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
	# A thin outline in the ink colour gives the letters weight, so the
	# glow from the lit parchment doesn't wash them out.
	l.outline_size = 3
	l.outline_modulate = INK
	l.shaded = false
	return l


## Spawns the round's items and returns their templates (GameState uses
## them to know totals per category).
func _spawn_items() -> Array[Dictionary]:
	var templates := ItemCatalog.get_item_templates(item_count_for(maxi(1, NetworkManager.players.size())))
	var used_points: Array[Vector3] = []
	for data in templates:
		var item: CoopItem = ITEM_SCENE.instantiate() as CoopItem
		item.name = data["id"]
		item.item_id = data["id"]
		item.category = data["category"]
		item.display_name = data["name"]
		item.description = data["description"]
		# Before add_child: _ready builds the visual from these.
		item.variant = data.get("variant", 0)
		item.look_seed = randi()
		items_container.add_child(item, true)
		# Scatter across the open half of the room, straight on the floor
		# (pivots are at the base), never overlapping another item:
		# overlapping bodies push each other forever, never sleep, and cost
		# network traffic every frame.
		item.global_position = _free_scatter_point(used_points)
		used_points.append(item.global_position)
		# Item._ready() already reset interpolation once, before this line
		# moved it from the origin to its scatter point — reset again now
		# that it's actually placed, or it renders as a slide-in on spawn.
		item.reset_physics_interpolation()
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

static func item_count_for(player_count: int) -> int:
	return mini(TARGET_ITEM_COUNT, BASE_ITEMS + ITEMS_PER_EXTRA_PLAYER * maxi(player_count - 1, 0))


## True until the round's first pickup (or placement) — while it's true the
## archive can still be resized for the crew without anyone losing work.
func round_not_started() -> bool:
	return game_state.round_not_started()


## Host: called by NetworkManager whenever someone finishes joining or
## leaves. Resizes the archive for the new crew size if the round hasn't
## started yet; once anyone has picked something up, the size is locked in.
func host_on_crew_changed() -> void:
	if not multiplayer.is_server() or not round_not_started():
		return
	# Resize first (it resets the round to the lobby), then re-check who's
	# ready: a newcomer cancels a countdown; if the last not-ready player
	# left, the countdown starts.
	if item_count_for(maxi(1, NetworkManager.players.size())) != game_state.total:
		host_restart_round(false, true)  # nobody has done anything yet: no teleport, keep ready flags
	game_state.host_crew_changed()


func host_restart_round(teleport_players := true, keep_ready := false) -> void:
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
	game_state.host_setup(_spawn_items(), keep_ready)
	if not teleport_players:
		return
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


# ---------------------------------------------------------------------------
# Pings — shown locally on every peer; Player.gd does the networking
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Feel: the room comes back to life as the archive is restored (DESIGN.md
# "Feel"). Dim and dusty at 0%, warm and clear at 100%. Local visuals on
# every peer, driven by the synced GameState.
# ---------------------------------------------------------------------------

const DUSTY := {"ambient": 0.34, "ambient_color": Color(0.8, 0.78, 0.76), "fog": 0.016,
	"field": 0.8, "sun": 0.55, "shelf": 1.6, "dust": 1.0, "saturation": 0.72}
const RESTORED := {"ambient": 0.7, "ambient_color": Color(1.0, 0.84, 0.64), "fog": 0.004,
	"field": 1.8, "sun": 1.0, "shelf": 3.0, "dust": 0.15, "saturation": 1.12}
const COMPLETE_SHELF_BONUS := 1.0

var _unit_lights: Dictionary = {}    # category_id -> OmniLight3D
var _unit_glow: Dictionary = {}      # category_id -> StandardMaterial3D (sconce bulbs)
var _unit_centres: Dictionary = {}   # category_id -> Vector3 (for celebration sparkles)
var _dust: GPUParticles3D
var _warmth_tween: Tween


func _update_warmth(instant := false) -> void:
	var p := 0.0
	if game_state.total > 0:
		p = clampf(float(game_state.sorted) / game_state.total, 0.0, 1.0)
	var env: Environment = $WorldEnvironment.environment
	if _warmth_tween:
		_warmth_tween.kill()
	var targets := [
		[env, "ambient_light_energy", lerpf(DUSTY.ambient, RESTORED.ambient, p)],
		[env, "ambient_light_color", DUSTY.ambient_color.lerp(RESTORED.ambient_color, p)],
		[env, "fog_density", lerpf(DUSTY.fog, RESTORED.fog, p)],
		[$FieldLightA, "light_energy", lerpf(DUSTY.field, RESTORED.field, p)],
		[$FieldLightB, "light_energy", lerpf(DUSTY.field, RESTORED.field, p)],
		[$DirectionalLight3D, "light_energy", lerpf(DUSTY.sun, RESTORED.sun, p)],
		[_dust, "amount_ratio", lerpf(DUSTY.dust, RESTORED.dust, p)],
		# colour returns to the room as it's restored
		[env, "adjustment_saturation", lerpf(DUSTY.saturation, RESTORED.saturation, p)],
	]
	for cat_id in _unit_lights:
		var c: Dictionary = game_state.per_category.get(cat_id, {"sorted": 0, "total": 0})
		var cp: float = float(c["sorted"]) / c["total"] if c["total"] > 0 else 0.0
		var bonus := COMPLETE_SHELF_BONUS if c["total"] > 0 and c["sorted"] >= c["total"] else 0.0
		targets.append([_unit_lights[cat_id], "light_energy", lerpf(DUSTY.shelf, RESTORED.shelf, cp) + bonus])
		targets.append([_unit_glow[cat_id], "emission_energy_multiplier", 3.0 + bonus * 3.0])
	if instant:
		for t in targets:
			t[0].set(t[1], t[2])
		return
	_warmth_tween = create_tween().set_parallel(true)
	for t in targets:
		_warmth_tween.tween_property(t[0], t[1], t[2], 1.6).set_trans(Tween.TRANS_SINE)


func _on_category_completed(cat_id: String) -> void:
	if _unit_centres.has(cat_id):
		var c: Vector3 = _unit_centres[cat_id]
		for i in 5:
			spawn_sparkles(c + Vector3(randf_range(-2.0, 2.0), randf_range(-0.5, 0.6), 0.2), 18)


## Slow floating dust in the air. Thins out as the archive is restored.
func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 260
	_dust.lifetime = 16.0
	_dust.preprocess = 16.0
	_dust.visibility_aabb = AABB(Vector3(-22, -1, -12), Vector3(44, 7, 36))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20, 1.8, 14)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.06
	pm.gravity = Vector3(0, -0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_speed_random = 0.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_dust.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.86, 0.62, 0.55)
	quad.material = mat
	_dust.draw_pass_1 = quad
	add_child(_dust)
	_dust.position = Vector3(0, 2.0, 6.0)


## A little burst of golden motes (correct placement, finished type).
## Local visual only; frees itself.
func spawn_sparkles(pos: Vector3, count := 14) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = count
	p.lifetime = 1.2
	p.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	p.process_material = _sparkle_material()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.albedo_color = Color(1.0, 0.8, 0.42)   # warm gold (the ramp fades it out)
	quad.material = mat
	p.draw_pass_1 = quad
	p.name = "Sparkles"
	add_child(p, true)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.9).timeout.connect(p.queue_free)


var _sparkle_pm: ParticleProcessMaterial
func _sparkle_material() -> ParticleProcessMaterial:
	if _sparkle_pm:
		return _sparkle_pm
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 110.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.9
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.gravity = Vector3(0, -0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 0.93, 0.7, 1))
	fade.set_color(1, Color(1, 0.75, 0.35, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_sparkle_pm = pm
	return pm


var _dot_tex: ImageTexture
## A small round, soft-edged dot (so sparkles aren't little squares).
func _soft_dot() -> ImageTexture:
	if _dot_tex:
		return _dot_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


const PING_LIFETIME := 5.0
const PING_FONT := preload("res://assets/fonts/Nunito.ttf")
var _pings: Dictionary = {}  # peer_id -> Label3D (one live ping per player)


## kind: "item" ("?" — where does this go?), "shelf" ("!" — over here) or
## "spot" (just "look here"). Drawn through walls and at a constant screen
## size, in the pinging player's robe colour.
func show_ping(peer_id: int, kind: String, pos: Vector3, caption: String) -> void:
	if _pings.has(peer_id) and is_instance_valid(_pings[peer_id]):
		_pings[peer_id].queue_free()
	var who: String = NetworkManager.players.get(peer_id, {}).get("name", "Player")
	var symbol: String = {"item": "?", "shelf": "!"}.get(kind, "•")
	var color: Color = CoopPlayerScript.ROBE_COLORS[peer_id % CoopPlayerScript.ROBE_COLORS.size()]
	# Big symbol (what kind of ping) + smaller caption (who / what) just
	# under it. Both are fixed-size, and the caption is placed with a
	# *pixel* offset, so the pair stays together at any distance.
	var l := _ping_label(symbol, 110, color)
	l.name = "Ping_%d" % peer_id
	var cap := _ping_label(who + ": " + caption if caption != "" else who, 40, color)
	cap.name = "Caption"
	cap.offset = Vector2(0, -62)
	l.add_child(cap)
	l.set_meta("kind", kind)
	l.set_meta("caption", caption)
	var container := get_node_or_null("Pings")
	if container == null:
		container = Node3D.new()
		container.name = "Pings"
		add_child(container)
	container.add_child(l)
	l.global_position = pos
	_pings[peer_id] = l
	Sfx.play("ping", null, -4.0)
	# gentle bob, then fade out
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", pos.y + 0.12, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(l, "position:y", pos.y, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(PING_LIFETIME - 1.7)
	# first fade runs after the interval; the rest run alongside it
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(cap, "modulate:a", 0.0, 1.0)
	tw.parallel().tween_property(cap, "outline_modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func _ping_label(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = PING_FONT
	l.font_size = size
	l.outline_size = 14 if size < 80 else 22
	l.pixel_size = 0.0009
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.modulate = color.lightened(0.3)
	l.outline_modulate = color.darkened(0.65)
	return l
