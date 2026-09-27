## tests/TestHeld.gd — measures held-item jitter: how far the drawn item is
## from the holder's hand while walking (host and client views).
## Run from a *copy* of the project: add  TestHarness="*res://tests/TestHeld.gd"
## under [autoload], then  godot --headless -- host  and  ... -- client.
## Prints mean / p95 / max offset. Steady (p95 ≈ mean) = no jitter.
extends Node
# Measures how far a held item's *rendered* position is from the holder's
# hand while the holder walks. Run: host + client.
var role := ""
func wait(t: float) -> void: await get_tree().create_timer(t).timeout
func world() -> Node: return get_tree().root.get_node_or_null("World")
func poll(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call(): return true
		await wait(0.1); t += 0.1
	return false
func rendered(n: Node3D) -> Vector3:
	return n.get_global_transform_interpolated().origin
func item_render_pos(it: Node3D) -> Vector3:
	var v: Node3D = it.get_node("Visual")
	return rendered(v)

# walk `p` along +x for `secs` at 3 m/s (owner only), sampling every
# rendered frame: distance between hand and the item as drawn.
var _sampling := false
var _samples: Array = []
var _hand: Node3D
var _item: Node3D

func _process(_d: float) -> void:
	# process_priority is set very high in _ready, so this runs after every
	# other node's _process — i.e. it sees exactly what will be drawn.
	if _sampling:
		_samples.append(rendered(_hand).distance_to(item_render_pos(_item)))

func walk_and_sample(p: Node3D, it: Node3D, secs: float, move: bool) -> Array:
	_hand = p.get_node("Camera3D/HoldPoint")
	_item = it
	var mover := func():
		if move:
			p.global_position += Vector3(3.0 * get_physics_process_delta_time(), 0, 0)
	get_tree().physics_frame.connect(mover)   # move in physics ticks, like real input
	_samples = []
	_sampling = true
	await wait(secs)
	_sampling = false
	get_tree().physics_frame.disconnect(mover)
	return _samples.duplicate()

func report(label: String, s: Array) -> void:
	s.sort()
	var mean: float = s.reduce(func(a, b): return a + b, 0.0) / max(s.size(), 1)
	var p95: float = s[int(s.size() * 0.95)] if s.size() > 0 else -1.0
	print("%s [INFO] %s: mean %.3f m, p95 %.3f m, max %.3f m over %d frames" % [role.to_upper(), label, mean, p95, s[-1], s.size()])

func _ready() -> void:
	process_priority = 100000
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	role = args[0]
	await wait(0.3)
	if role == "host":
		NetworkManager.host_game()
		await poll(func(): return multiplayer.get_peers().size() > 0, 15)
		await wait(2.0)
		var me: Node3D = world().get_node("Players/1")
		var it: Node3D = world().get_node("Items/potion_00")
		it.request_pickup.rpc_id(1)
		await wait(0.3)
		report("host, own item, walking", await walk_and_sample(me, it, 2.0, true))
		it.request_drop.rpc_id(1)
		# watch the client's item while it walks
		await wait(1.0)
		var cid: int = multiplayer.get_peers()[0]
		var cp: Node3D = world().get_node("Players/%d" % cid)
		var cit: Node3D = world().get_node("Items/tome_00")
		await poll(func(): return cit.held_by_peer == cid, 10)
		await wait(0.3)
		report("host watching client's item", await walk_and_sample(cp, cit, 2.0, false))
		await wait(3.0)
	else:
		NetworkManager.join_game("127.0.0.1")
		await poll(func(): return world() != null and world().has_node("Items/tome_00"), 15)
		await wait(4.5)
		var me: Node3D = world().get_node("Players/%d" % multiplayer.get_unique_id())
		var it: Node3D = world().get_node("Items/tome_00")
		it.request_pickup.rpc_id(1)
		await poll(func(): return it.held_by_peer == multiplayer.get_unique_id(), 5)
		await wait(0.3)
		report("client, own item, standing", await walk_and_sample(me, it, 1.0, false))
		report("client, own item, walking", await walk_and_sample(me, it, 2.5, true))
		await wait(1.0)
	get_tree().quit()
