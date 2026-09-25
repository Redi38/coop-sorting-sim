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
# How many slots sit in one shelf row before wrapping to the next row —
# a single 60-wide row wouldn't fit the room or be walkable.
const SLOTS_PER_ROW := 12
const SLOT_SPACING := 1.1
const SHELF_ROW_SPACING := 1.4
const SHELF_CATEGORY_GAP := 2.5
const SCATTER_HALF_EXTENT := 18.0

@onready var spawn_points_node: Node3D = $SpawnPoints
@onready var items_container: Node3D = $Items
@onready var shelf_slots_node: Node3D = $ShelfSlots
@onready var players_container: Node3D = $Players


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

	if multiplayer.is_server():
		_spawn_items()


func _spawn_shelf_slots() -> void:
	var categories := ItemCatalog.get_categories()
	# Rows needed to fit SLOTS_PER_CATEGORY slots at SLOTS_PER_ROW per row,
	# so a category's block is a wrapped grid instead of one very long row.
	var rows_per_category := int(ceil(float(SLOTS_PER_CATEGORY) / SLOTS_PER_ROW))
	# Categories sit side-by-side along X (each its own wrapped grid, shallow
	# in Z) rather than stacked deeper and deeper in Z — keeps the whole
	# shelf wall within the floor bounds instead of running off the edge.
	var block_width := (SLOTS_PER_ROW - 1) * SLOT_SPACING
	var cat_x_stride := block_width + SHELF_CATEGORY_GAP
	var cat_x_start := -(categories.size() - 1) / 2.0 * cat_x_stride
	for cat_index in categories.size():
		var cat := categories[cat_index]
		var cat_center_x := cat_x_start + cat_index * cat_x_stride
		for col in SLOTS_PER_CATEGORY:
			var slot: Area3D = SLOT_SCENE.instantiate()
			slot.name = "Slot_%s_%d" % [cat.id, col]
			slot.slot_id = "slot_%s_%d" % [cat.id, col]
			slot.accepted_category = cat.id
			shelf_slots_node.add_child(slot)
			var row_in_cat := col / SLOTS_PER_ROW
			var col_in_row := col % SLOTS_PER_ROW
			var x := cat_center_x + (col_in_row - (SLOTS_PER_ROW - 1) / 2.0) * SLOT_SPACING
			var z := -6.0 - row_in_cat * SHELF_ROW_SPACING
			slot.position = Vector3(x, 1.0, z)


func _spawn_items() -> void:
	var templates := ItemCatalog.get_item_templates(TARGET_ITEM_COUNT)
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
		item.global_position = Vector3(
			randf_range(-SCATTER_HALF_EXTENT, SCATTER_HALF_EXTENT),
			1.0,
			randf_range(2.0, SCATTER_HALF_EXTENT)
		)
