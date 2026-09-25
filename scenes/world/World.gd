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

# Kept modest for local network testing on a single room. ItemCatalog's
# get_item_templates() cycles its hand-authored pool with numbered repeats,
# so this can be raised toward the design doc's 150-300 target once the
# sync loop at this scale feels good over an actual connection, without
# touching anything else here.
const TARGET_ITEM_COUNT := 60
const SLOTS_PER_CATEGORY := 6
const SCATTER_HALF_EXTENT := 6.0

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
	for row in categories.size():
		var cat := categories[row]
		for col in SLOTS_PER_CATEGORY:
			var slot: Area3D = SLOT_SCENE.instantiate()
			slot.name = "Slot_%s_%d" % [cat.id, col]
			slot.slot_id = "slot_%s_%d" % [cat.id, col]
			slot.accepted_category = cat.id
			shelf_slots_node.add_child(slot)
			var x := (col - (SLOTS_PER_CATEGORY - 1) / 2.0) * 1.0
			var z := -6.0 - row * 1.2
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
		# scatter roughly around the room center, away from the shelf wall;
		# replace with real scatter points once the level art exists
		item.global_position = Vector3(
			randf_range(-SCATTER_HALF_EXTENT, SCATTER_HALF_EXTENT),
			1.0,
			randf_range(-2.0, SCATTER_HALF_EXTENT)
		)
