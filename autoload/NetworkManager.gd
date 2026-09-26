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
# `players` only ever contains peers whose World has finished loading (the
# host adds them in _client_world_ready), and it's synced to everyone. So it
# doubles as the "ready" list: nothing world-related is sent to a peer until
# it's in here, because anything sent earlier targets nodes that don't exist
# on that peer yet and is silently lost. See is_peer_ready().
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

func _on_peer_connected(_id: int) -> void:
	# Deliberately nothing here. The new peer is still loading World.tscn,
	# so any spawn sent now would be lost. The host waits for that peer's
	# _client_world_ready (sent from register_world once its World exists)
	# and does all the per-peer setup there.
	pass


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Drop anything they were carrying before their player node goes away,
	# otherwise those items stay frozen mid-air with a held_by_peer that
	# points at a peer who no longer exists — unpickable forever.
	for item in get_tree().get_nodes_in_group("item"):
		if item.held_by_peer == id:
			item.host_force_release()
	if not players.has(id):
		return
	players.erase(id)
	_register_players_on_all.rpc(players)
	_despawn_player_on_all.rpc(id)
	if world:
		world.host_on_crew_changed()  # shrink back if the round hadn't started


func _on_connected_to_server() -> void:
	# Client successfully reached the host: load the shared world first —
	# the host's spawn RPCs can arrive as soon as this handshake completes,
	# so World must already exist and be registered before that happens.
	# Client reached the host: load the shared world. The host is told
	# we're ready (with our name) from register_world, once it exists.
	get_tree().change_scene_to_file(WORLD_SCENE)


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
func _client_world_ready(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if players.has(sender_id):
		return  # duplicate/late message
	players[sender_id] = {"name": display_name}
	# Name registry first: Player.gd reads NetworkManager.players once, at
	# spawn time, so it must land before any spawn RPC. (Same channel,
	# reliable, so ordering is guaranteed.)
	_register_players_on_all.rpc(players)
	# Existing players, at their current positions, for the new peer only.
	for existing_player in world.get_node("Players").get_children():
		_spawn_player_on_all.rpc_id(sender_id, int(existing_player.name), existing_player.global_position)
	# The new player, for everyone (peers still loading skip it and get it
	# from the loop above once they're ready themselves).
	_spawn_player_on_all.rpc(sender_id, _next_spawn_position())
	# Resize the archive for the bigger crew if the round hasn't started —
	# before the visibility pass below, so the new peer only ever receives
	# the resized item set.
	world.host_on_crew_changed()
	# Items: their synchronizers filter on is_peer_ready, so flip them now.
	for item in get_tree().get_nodes_in_group("item"):
		var sync := item.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if sync:
			sync.update_visibility(sender_id)


@rpc("authority", "reliable", "call_local")
func _register_players_on_all(current_players: Dictionary) -> void:
	players = current_players
	# The ready-list just changed, so re-run every player synchronizer's
	# visibility filter — otherwise a peer that wasn't ready when the sync
	# first checked is never added, and never sees that player move.
	if world:
		for player in world.get_node("Players").get_children():
			var sync := player.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
			if sync:
				sync.update_visibility()
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
	if multiplayer.is_server():
		# Host: spawn itself (peer id 1) once the world exists.
		_spawn_player_on_all.rpc(1, _next_spawn_position())
	else:
		# Client: our World exists now, so it's safe for the host to start
		# sending us players and items.
		_client_world_ready.rpc_id(1, local_player_name)


func _next_spawn_position() -> Vector3:
	if _spawn_points.is_empty():
		return Vector3.ZERO
	var point := _spawn_points[_next_spawn_index % _spawn_points.size()]
	_next_spawn_index += 1
	return point.global_position


## Visibility filter for item and player synchronizers: a peer only
## receives spawns/updates once its World has loaded. Without this, a
## synchronizer's first message (a node-path handshake) reaches a peer that
## doesn't have the node yet, fails, and is never retried — so that peer
## never sees the node move. Works on clients too (they sync their own
## player to each other via the host), since `players` is synced to all.
func is_peer_ready(peer_id: int) -> bool:
	return players.has(peer_id)


func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()
