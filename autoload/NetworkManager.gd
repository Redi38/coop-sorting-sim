extends Node
## Autoload singleton: res://autoload/NetworkManager.gd
##
## Owns the ENetMultiplayerPeer connection and host-authoritative player
## spawning. Everything else (World, Item, ShelfSlot) talks to this node
## instead of touching `multiplayer` directly, so the connection logic
## lives in exactly one place.

const PORT := 7777
const MAX_PLAYERS := 4
const WORLD_SCENE := "res://scenes/world/World.tscn"
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")

signal player_list_changed
signal connection_failed
signal server_disconnected

var players: Dictionary = {}      # peer_id (int) -> { "name": String }
var local_player_name: String = "Player"

var world: Node3D = null           # set by World.gd on _ready()
var _spawn_points: Array[Node3D] = []
var _next_spawn_index := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# Hosting / joining
# ---------------------------------------------------------------------------

func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to host: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	players[1] = {"name": local_player_name}
	get_tree().change_scene_to_file(WORLD_SCENE)
	return OK


func join_game(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		push_error("Failed to join: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# Only the host reacts here; clients learn about new players via the
	# synced `players` state and spawn RPCs below. We deliberately do NOT
	# register or spawn the new peer's own player here — we don't know
	# their chosen name yet, and spawning with a placeholder name would
	# leave every nameplate stuck on that placeholder (Player.gd reads the
	# name once, at spawn time). Their actual spawn happens in
	# _submit_player_name, once we've heard from them.
	if not multiplayer.is_server():
		return

	# The new peer missed every earlier spawn broadcast (including the
	# host's own self-spawn on world load), so it needs those specific
	# players spawned for it individually, using their current position.
	# Send the name registry FIRST — Player.gd reads NetworkManager.players
	# once, at spawn time, so if the spawn RPC below arrives before this
	# one does, every nameplate falls back to the scene's default text.
	_register_players_on_all.rpc_id(id, players)
	if world:
		var players_node := world.get_node("Players")
		for existing_player in players_node.get_children():
			var existing_id := int(existing_player.name)
			_spawn_player_on_all.rpc_id(id, existing_id, existing_player.global_position)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(id):
		return
	players.erase(id)
	_register_players_on_all.rpc(players)
	_despawn_player_on_all.rpc(id)


func _on_connected_to_server() -> void:
	# Client successfully reached the host: load the shared world first —
	# the host's spawn RPCs can arrive as soon as this handshake completes,
	# so World must already exist and be registered before that happens.
	get_tree().change_scene_to_file(WORLD_SCENE)
	_submit_player_name.rpc_id(1, local_player_name)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")


# ---------------------------------------------------------------------------
# RPCs — host is authoritative for who exists and where they spawn
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _submit_player_name(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if players.has(sender_id):
		return  # already registered — ignore a duplicate/late submission
	players[sender_id] = {"name": display_name}
	_register_players_on_all.rpc(players)
	_spawn_player_on_all.rpc(sender_id, _next_spawn_position())


@rpc("authority", "reliable", "call_local")
func _register_players_on_all(current_players: Dictionary) -> void:
	players = current_players
	player_list_changed.emit()


@rpc("authority", "reliable", "call_local")
func _spawn_player_on_all(id: int, spawn_position: Vector3) -> void:
	if world == null:
		push_warning("NetworkManager: world not registered yet, cannot spawn player %d" % id)
		return
	if world.has_node("Players/%d" % id):
		return
	var player: CoopPlayer = PLAYER_SCENE.instantiate() as CoopPlayer
	player.name = str(id)
	player.set_multiplayer_authority(id)
	world.get_node("Players").add_child(player)
	player.global_position = spawn_position


@rpc("authority", "reliable", "call_local")
func _despawn_player_on_all(id: int) -> void:
	if world == null:
		return
	var node := world.get_node_or_null("Players/%d" % id)
	if node:
		node.queue_free()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func register_world(world_node: Node3D, spawn_points: Array[Node3D]) -> void:
	world = world_node
	_spawn_points = spawn_points
	_next_spawn_index = 0
	# Host: spawn itself (peer id 1) once the world exists.
	if multiplayer.is_server():
		_spawn_player_on_all.rpc(1, _next_spawn_position())


func _next_spawn_position() -> Vector3:
	if _spawn_points.is_empty():
		return Vector3.ZERO
	var point := _spawn_points[_next_spawn_index % _spawn_points.size()]
	_next_spawn_index += 1
	return point.global_position


func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()
