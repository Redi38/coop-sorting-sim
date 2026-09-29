## tests/TestLobby.gd — headless 2-player ready-up check: ready alone waits,
## all ready -> countdown, un-ready cancels it, host R-again override.
## Run from a *copy*: add  TestHarness="*res://tests/TestLobby.gd"  under [autoload],
## then  godot --headless -- host  and  godot --headless -- client
extends Node
var role := ""
func check(name: String, ok: bool, detail := "") -> void:
	print("%s [%s] %s %s" % [role.to_upper(), "PASS" if ok else "FAIL", name, detail])
func wait(t: float) -> void: await get_tree().create_timer(t).timeout
func world() -> Node: return get_tree().root.get_node_or_null("World")
func gs() -> Node: return world().get_node("GameState")
func poll(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call(): return true
		await wait(0.05); t += 0.05
	return false
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
	await poll(func(): return world() != null and NetworkManager.players.size() == 2, 15)
	var cid: int = multiplayer.get_peers()[0]
	var ok := await poll(func(): return gs().ready_peers.has(cid), 8)
	check("client's R marks it ready, round waits for host", ok and gs().phase == "lobby")
	gs().request_toggle_ready.rpc_id(1)
	await wait(0.1)
	check("both ready -> countdown", gs().phase == "countdown")
	ok = await poll(func(): return gs().phase == "lobby", 5)
	check("client un-readies mid-countdown -> back to lobby", ok and not gs().ready_peers.has(cid) and gs().ready_peers.has(1))
	await wait(0.5)
	gs().request_toggle_ready.rpc_id(1)   # host already ready: override
	await wait(0.1)
	check("host presses R again -> starts without waiting", gs().phase == "countdown" and not gs().ready_peers.has(cid))
	ok = await poll(func(): return gs().phase == "playing", 5)
	check("countdown ends -> playing", ok and gs().running)
	await wait(2.0)

func _client() -> void:
	NetworkManager.join_game("127.0.0.1")
	await poll(func(): return world() != null and gs().total == 100, 15)
	await wait(0.5)
	var hud := world().get_node("GameHUD")
	check("client sees the lobby panel", hud.lobby_panel.visible and gs().phase == "lobby", "('%s')" % hud.lobby_info.text)
	gs().request_toggle_ready.rpc_id(1)
	await poll(func(): return gs().phase == "countdown", 8)
	check("client sees countdown number", hud.countdown_label.visible and hud.countdown_label.text in ["3", "2"], "('%s')" % hud.countdown_label.text)
	await wait(0.6)
	gs().request_toggle_ready.rpc_id(1)   # un-ready mid-countdown
	var ok := await poll(func(): return gs().phase == "playing", 10)
	await wait(0.2)
	check("client sees round start after host override", ok and not hud.lobby_panel.visible)
	await wait(1.0)
