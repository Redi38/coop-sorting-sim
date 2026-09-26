## tests/TestCoop.gd — headless 2-player check of the co-op features:
## archive resizes on join, crew list + notices, item/shelf pings both
## ways, toss lands identically on both peers, leave-after-start keeps size.
## Run from a *copy* of the project:
##   1. add  TestHarness="*res://tests/TestCoop.gd"  under [autoload]
##   2. godot --headless -- host   (terminal 1)
##   3. godot --headless -- client (terminal 2, within ~5 s)
## Each prints PASS/FAIL lines.
extends Node
var role := ""
func check(name: String, ok: bool, detail := "") -> void:
	print("%s [%s] %s %s" % [role.to_upper(), "PASS" if ok else "FAIL", name, detail])
func wait(t: float) -> void: await get_tree().create_timer(t).timeout
func world() -> Node: return get_tree().root.get_node_or_null("World")
func gs() -> Node: return world().get_node("GameState")
func hud() -> Node: return world().get_node("GameHUD")
func poll(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call(): return true
		await wait(0.1); t += 0.1
	return false
func ping_of(peer: int) -> Node:
	var c := world().get_node_or_null("Pings")
	return c.get_node_or_null("Ping_%d" % peer) if c else null
func aim_ping(target: Vector3, stand: Vector3) -> void:
	var me: Node3D = world().get_node("Players/%d" % multiplayer.get_unique_id())
	me.global_position = stand
	await get_tree().physics_frame
	me.get_node("Camera3D").look_at(target)
	await get_tree().physics_frame
	me.try_ping()

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	role = args[0]
	await wait(0.3)
	if role == "host": await _host()
	else: await _client()
	get_tree().quit()

func _host() -> void:
	NetworkManager.host_game()
	await wait(1.5)
	check("solo archive = 60 items", gs().total == 60 and get_tree().get_nodes_in_group("item").size() == 60)
	var ok := await poll(func(): return gs().total == 100, 15)
	await wait(0.3)
	check("friend joins before start -> archive grows to 100", ok and get_tree().get_nodes_in_group("item").size() == 100)
	check("host crew list shows 2", hud().crew_list.get_child_count() == 2, "(%d)" % hud().crew_list.get_child_count())
	check("host got a notice", hud().toast.visible, "('%s')" % hud().toast_label.text)
	var cid: int = multiplayer.get_peers()[0]
	# client pings an item -> host sees it
	ok = await poll(func(): return ping_of(cid) != null, 8)
	var p := ping_of(cid)
	check("host sees client's item ping", ok and p.get_meta("kind") == "item" and p.text.begins_with("?"), "(%s)" % (p.text.replace("\n", " | ") if p else "none"))
	var want: String = world().get_node("Items/scroll_00").display_name
	check("item ping names the item", p != null and p.get_meta("caption") == want, "(want '%s')" % want)
	check("ping uses client's robe colour", p != null and p.modulate.is_equal_approx(CoopPlayer.ROBE_COLORS[cid % 4].lightened(0.3)))
	# host pings the Keys shelf -> client checks
	var key_slot: Node3D = world().get_node("ShelfSlots/Slot_key_4")
	await aim_ping(key_slot.global_position + Vector3(0, 0.15, 0), key_slot.global_position + key_slot.global_transform.basis.z * 3.0 - Vector3(0, key_slot.global_position.y, 0))
	check("host's own shelf ping shows locally", ping_of(1) != null and ping_of(1).get_meta("kind") == "shelf" and ping_of(1).get_meta("caption") == "Keys")
	await wait(1.0)
	# host picks up + tosses an item
	var it: RigidBody3D = world().get_node("Items/candle_01")
	var me: CharacterBody3D = world().get_node("Players/1")
	me.global_position = it.global_position + Vector3(0, 0, 1.0)
	await get_tree().physics_frame
	me.get_node("Camera3D").look_at(me.global_position + Vector3(0, 1.8, -5))  # face -z, slightly up
	it.request_pickup.rpc_id(1)
	await wait(0.4)
	check("round started by pickup", gs().running)
	var start: Vector3 = it.global_position
	me._try_toss()
	await wait(0.25)
	var mid_air: bool = it.global_position.y > 1.2 and not it.freeze and it.held_by_peer == 0
	await poll(func(): return it.sleeping, 8)
	var flat := Vector2(it.global_position.x - start.x, it.global_position.z - start.z).length()
	check("toss flies, lands and settles", mid_air and it.sleeping and flat > 2.5 and it.global_position.y < 0.3, "(mid_air=%s travelled=%.1fm y=%.2f)" % [mid_air, flat, it.global_position.y])
	print("TOSSED_AT %.3f %.3f %.3f" % [it.global_position.x, it.global_position.y, it.global_position.z])
	check("carry list empty after toss", me.held_items.is_empty())
	# client leaves after start -> no shrink
	ok = await poll(func(): return multiplayer.get_peers().is_empty(), 15)
	await wait(0.5)
	check("friend leaves after start -> archive stays 100", ok and gs().total == 100)
	check("host crew list back to 1, with a notice", hud().crew_list.get_child_count() == 1 and hud().toast_label.text.contains("left"), "('%s')" % hud().toast_label.text)

func _client() -> void:
	NetworkManager.join_game("127.0.0.1")
	var ok := await poll(func(): return world() != null and gs().total == 100 and get_tree().get_nodes_in_group("item").size() == 100, 15)
	check("client sees 100-item archive", ok)
	await wait(0.5)
	check("client crew list shows 2", hud().crew_list.get_child_count() == 2)
	# ping scroll_00 (a thin item) from 4 m away
	var it: Node3D = world().get_node("Items/scroll_00")
	await aim_ping(it.global_position + Vector3(0, 0.04, 0), it.global_position + Vector3(4.0, 0, 0))
	var me := multiplayer.get_unique_id()
	check("client's own ping shows locally", ping_of(me) != null and ping_of(me).get_meta("kind") == "item")
	# host's shelf ping arrives
	ok = await poll(func(): return ping_of(1) != null, 8)
	check("client sees host's shelf ping", ok and ping_of(1).get_meta("kind") == "shelf" and ping_of(1).text.begins_with("!") and ping_of(1).get_meta("caption") == "Keys", "(%s)" % (ping_of(1).text.replace("\n", " | ") if ping_of(1) else "none"))
	# watch the toss: wait for candle_01 to move then settle
	var c: Node3D = world().get_node("Items/candle_01")
	var p0: Vector3 = c.global_position
	ok = await poll(func(): return c.global_position.distance_to(p0) > 2.0, 10)
	await wait(4.0)
	print("CLIENT_SAW_TOSS_AT %.3f %.3f %.3f" % [c.global_position.x, c.global_position.y, c.global_position.z])
	check("client saw the toss", ok)
	NetworkManager.leave_game()
	await wait(0.5)
