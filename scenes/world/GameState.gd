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
signal category_completed(category_id: String)
signal phase_changed(new_phase: String)

const RESYNC_INTERVAL := 5.0

var total: int = 0
var sorted: int = 0
var mistakes: int = 0
var per_category: Dictionary = {}   # category_id -> {"sorted": int, "total": int}
var player_stats: Dictionary = {}   # peer_id -> {"name": String, "correct": int, "wrong": int}
var elapsed: float = 0.0
var running: bool = false           # timer ticking (phase == "playing")
# Round phases. "lobby": the crew gathers, presses R when ready; items
# can't be picked up yet and the archive still resizes for joiners.
# "countdown": everyone's ready, 3-2-1. "playing": sorting. "finished".
const COUNTDOWN_SECONDS := 3.0
var phase: String = "lobby"
var ready_peers: Array = []         # peer ids who pressed R this lobby
var countdown_left: float = 0.0
var finished: bool = false

var _resync_timer := 0.0
# Per-type progress as of the previous _sync, deep-copied: on the host the
# live dict is mutated before it's broadcast (and call_local passes it by
# reference), so it can't serve as its own "before".
var _prev_per_category: Dictionary = {}


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
	if phase == "countdown":
		countdown_left = maxf(countdown_left - delta, 0.0)
		if multiplayer.is_server() and countdown_left <= 0.0:
			_host_begin_playing()
	if multiplayer.is_server() and running:
		_resync_timer += delta
		if _resync_timer >= RESYNC_INTERVAL:
			_resync_timer = 0.0
			_broadcast()


# ---------------------------------------------------------------------------
# Host-side mutations
# ---------------------------------------------------------------------------

## Starts a fresh round for the given item set (World._spawn_items output).
## keep_ready: a resize for a new crew member keeps everyone's ready flags;
## "Play again" starts a fresh lobby.
func host_setup(item_templates: Array, keep_ready := false) -> void:
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
	phase = "lobby"
	countdown_left = 0.0
	if not keep_ready:
		ready_peers = []
	_prune_ready()
	_resync_timer = 0.0
	_broadcast()


## True until the countdown has finished: nothing has been sorted yet, so
## the archive can still be resized for the crew.
func round_not_started() -> bool:
	return phase == "lobby" or phase == "countdown"


## Only while playing can items be picked up (Item.request_pickup asks).
func host_pickups_allowed() -> bool:
	return phase == "playing"


# --- lobby / ready-up ---------------------------------------------------------

## Any player: press R. Toggles your ready flag in the lobby. The host
## pressing R *again* while others aren't ready starts the countdown anyway,
## so one away-from-keyboard friend can't hold the round hostage.
@rpc("any_peer", "reliable", "call_local")
func request_toggle_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if phase == "countdown":
		# anyone un-readying during the countdown stops it
		ready_peers.erase(peer)
		phase = "lobby"
		countdown_left = 0.0
		_broadcast()
		return
	if phase != "lobby":
		return
	if ready_peers.has(peer):
		if peer == 1 and not _all_ready():
			_host_start_countdown()  # host override
			return
		ready_peers.erase(peer)
	else:
		ready_peers.append(peer)
	if _all_ready():
		_host_start_countdown()
	else:
		_broadcast()


## Host: start right away (tests, tools). With countdown=false, skips 3-2-1.
func host_force_start(countdown := false) -> void:
	if not multiplayer.is_server() or not round_not_started():
		return
	if countdown:
		_host_start_countdown()
	else:
		_host_begin_playing()


## Host: the crew changed (join/leave). Drop departed players' ready flags;
## a newcomer isn't ready, so a running countdown goes back to the lobby.
func host_crew_changed() -> void:
	if not multiplayer.is_server() or not round_not_started():
		return
	_prune_ready()
	if phase == "countdown" and not _all_ready():
		phase = "lobby"
		countdown_left = 0.0
	elif phase == "lobby" and _all_ready():
		_host_start_countdown()
		return
	_broadcast()


func _all_ready() -> bool:
	var crew: Array = NetworkManager.players.keys()
	if crew.is_empty():
		crew = [1]
	for peer_id in crew:
		if not ready_peers.has(peer_id):
			return false
	return true


func _prune_ready() -> void:
	var present: Array = NetworkManager.players.keys()
	ready_peers = ready_peers.filter(func(p): return present.has(p) or (present.is_empty() and p == 1))


func _host_start_countdown() -> void:
	phase = "countdown"
	countdown_left = COUNTDOWN_SECONDS
	_broadcast()


func _host_begin_playing() -> void:
	phase = "playing"
	countdown_left = 0.0
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
		phase = "finished"
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
		"phase": phase,
		"ready_peers": ready_peers,
		"countdown_left": countdown_left,
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
	var old_per_category := _prev_per_category
	total = snap["total"]
	sorted = snap["sorted"]
	mistakes = snap["mistakes"]
	per_category = snap["per_category"]
	player_stats = snap["player_stats"]
	elapsed = snap["elapsed"]
	running = snap["running"]
	var was_phase := phase
	phase = snap.get("phase", "lobby")
	ready_peers = snap.get("ready_peers", [])
	countdown_left = snap.get("countdown_left", 0.0)
	if phase != was_phase:
		phase_changed.emit(phase)
	finished = snap["finished"]
	state_changed.emit()
	# A type just got its last item (only live transitions: a first
	# snapshot or a reset has no "before" to compare against).
	for cat_id in per_category:
		var now_c: Dictionary = per_category[cat_id]
		if old_per_category.has(cat_id) and now_c["total"] > 0 \
				and now_c["sorted"] >= now_c["total"] \
				and old_per_category[cat_id]["sorted"] < now_c["total"]:
			category_completed.emit(cat_id)
	_prev_per_category = per_category.duplicate(true)
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
