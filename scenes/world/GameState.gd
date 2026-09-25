class_name GameState
extends Node
## res://scenes/world/GameState.gd — child of World.tscn at World/GameState
##
## Host-authoritative round state: how much is sorted, how many mistakes,
## who did what, and the round timer. Same pattern as Item/ShelfSlot —
## only the host mutates state (via the host_* methods, called from
## ShelfSlot/Item/World on the host), then pushes a full snapshot to every
## peer with _sync. The snapshot is small (a few ints + one entry per
## player), so a full push is simpler and safer than diffing.
##
## Timer: machines' clocks don't agree, so the host sends its `elapsed`
## value with every snapshot and each peer ticks it forward locally in
## between. A periodic resync keeps drift from ever becoming visible.

signal state_changed
signal round_finished
signal round_reset

const RESYNC_INTERVAL := 5.0

var total: int = 0
var sorted: int = 0
var mistakes: int = 0
var per_category: Dictionary = {}   # category_id -> {"sorted": int, "total": int}
var player_stats: Dictionary = {}   # peer_id -> {"name": String, "correct": int, "wrong": int}
var elapsed: float = 0.0
var running: bool = false           # timer ticking (starts on the round's first pickup)
var finished: bool = false

var _resync_timer := 0.0


func _ready() -> void:
	add_to_group("game_state")
	set_multiplayer_authority(1)
	if not multiplayer.is_server():
		# Late joiners (and everyone else) pull a snapshot once their own
		# World/GameState node exists to receive it.
		_request_state.rpc_id(1)


func _process(delta: float) -> void:
	if running:
		elapsed += delta
	if multiplayer.is_server() and running:
		_resync_timer += delta
		if _resync_timer >= RESYNC_INTERVAL:
			_resync_timer = 0.0
			_broadcast()


# ---------------------------------------------------------------------------
# Host-side mutations
# ---------------------------------------------------------------------------

## Starts a fresh round for the given item set (World._spawn_items output).
func host_setup(item_templates: Array) -> void:
	if not multiplayer.is_server():
		return
	total = item_templates.size()
	sorted = 0
	mistakes = 0
	player_stats = {}
	per_category = {}
	for data in item_templates:
		var cat_id: String = data["category"]
		if not per_category.has(cat_id):
			per_category[cat_id] = {"sorted": 0, "total": 0}
		per_category[cat_id]["total"] += 1
	elapsed = 0.0
	running = false
	finished = false
	_resync_timer = 0.0
	_broadcast()


## Called by Item.request_pickup on every successful pickup.
func host_note_pickup() -> void:
	if not multiplayer.is_server():
		return
	if running or finished:
		return
	running = true
	_broadcast()


## Called by ShelfSlot.request_place on every accepted placement.
func host_record_placement(peer_id: int, category: String, correct: bool) -> void:
	if not multiplayer.is_server() or finished:
		return
	var stats := _stats_for(peer_id)
	if correct:
		sorted += 1
		stats["correct"] += 1
		if per_category.has(category):
			per_category[category]["sorted"] += 1
	else:
		mistakes += 1
		stats["wrong"] += 1
	if total > 0 and sorted >= total:
		finished = true
		running = false
	_broadcast()


func _stats_for(peer_id: int) -> Dictionary:
	if not player_stats.has(peer_id):
		var pname := "Player %d" % peer_id
		if NetworkManager.players.has(peer_id):
			pname = NetworkManager.players[peer_id].get("name", pname)
		player_stats[peer_id] = {"name": pname, "correct": 0, "wrong": 0}
	return player_stats[peer_id]


# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {
		"total": total,
		"sorted": sorted,
		"mistakes": mistakes,
		"per_category": per_category,
		"player_stats": player_stats,
		"elapsed": elapsed,
		"running": running,
		"finished": finished,
	}


func _broadcast() -> void:
	_sync.rpc(_snapshot())


@rpc("any_peer", "reliable")
func _request_state() -> void:
	if not multiplayer.is_server():
		return
	_sync.rpc_id(multiplayer.get_remote_sender_id(), _snapshot())


@rpc("authority", "reliable", "call_local")
func _sync(snap: Dictionary) -> void:
	var was_finished := finished
	total = snap["total"]
	sorted = snap["sorted"]
	mistakes = snap["mistakes"]
	per_category = snap["per_category"]
	player_stats = snap["player_stats"]
	elapsed = snap["elapsed"]
	running = snap["running"]
	finished = snap["finished"]
	state_changed.emit()
	if finished and not was_finished:
		round_finished.emit()


## Broadcast by World.host_restart_round so every peer can clear local,
## non-replicated state (carried-item lists, win screen, mouse mode).
@rpc("authority", "reliable", "call_local")
func notify_round_reset() -> void:
	round_reset.emit()


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]
