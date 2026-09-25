extends Node3D
## res://scenes/world/World.tscn
##
## Milestone-1 room: one shared space, a handful of shelf slots (placed in
## the editor), and a small set of items the host spawns at runtime through
## the MultiplayerSpawner so every client sees the same set without hand-
## authoring per-item replication.

const ITEM_SCENE := preload("res://scenes/item/Item.tscn")

# id, category, display name — swap this for a resource/JSON file once the
# real 150-300 item set exists; this is just enough to test sync with two players.
const DEMO_ITEMS := [
	{"id": "potion_01", "category": "potion", "name": "Shimmering Elixir"},
	{"id": "potion_02", "category": "potion", "name": "Murky Draught"},
	{"id": "tome_01", "category": "tome", "name": "Tome of Embers"},
	{"id": "tome_02", "category": "tome", "name": "Waterlogged Journal"},
	{"id": "artifact_01", "category": "artifact", "name": "Cracked Orb"},
	{"id": "artifact_02", "category": "artifact", "name": "Tarnished Compass"},
]

@onready var spawn_points_node: Node3D = $SpawnPoints
@onready var items_container: Node3D = $Items
@onready var players_container: Node3D = $Players


func _ready() -> void:
	players_container.add_to_group("players_container")

	var spawn_points: Array[Node3D] = []
	for child in spawn_points_node.get_children():
		spawn_points.append(child as Node3D)

	NetworkManager.register_world(self, spawn_points)

	if multiplayer.is_server():
		_spawn_demo_items()


func _spawn_demo_items() -> void:
	for i in DEMO_ITEMS.size():
		var data: Dictionary = DEMO_ITEMS[i]
		var item: CoopItem = ITEM_SCENE.instantiate() as CoopItem
		item.name = data["id"]
		item.item_id = data["id"]
		item.category = data["category"]
		item.display_name = data["name"]
		items_container.add_child(item, true)
		# scatter items roughly around the room center; replace with real
		# scatter points once the level art exists
		item.global_position = Vector3(randf_range(-4.0, 4.0), 1.0, randf_range(-4.0, 4.0))
