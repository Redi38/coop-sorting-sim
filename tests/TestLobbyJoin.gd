## tests/TestLobbyJoin.gd — headless solo check of crew changes around the
## countdown (join cancels + resizes, leave resumes, join while playing = no-op).
## Run from a *copy*: add  TestHarness="*res://tests/TestLobbyJoin.gd"  under [autoload],
## then  godot --headless -- host
extends Node
var role := ""
func check(name: String, ok: bool, detail := "") -> void:
	print("%s [%s] %s %s" % [role.to_upper(), "PASS" if ok else "FAIL", name, detail])
func wait(t: float) -> void: await get_tree().create_timer(t).timeout
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): return
	role = args[0]
	if role != "host": get_tree().quit(); return
	await wait(0.3)
	NetworkManager.host_game()
	await wait(2.0)
	var w := get_tree().root.get_node("World")
	var gs = w.get_node("GameState")
	gs.request_toggle_ready.rpc_id(1)
	await wait(0.1)
	check("solo ready -> countdown", gs.phase == "countdown" and gs.total == 60)
	# a friend finishes joining mid-countdown (simulated on the host)
	NetworkManager.players[4242] = {"name": "Mira"}
	w.host_on_crew_changed()
	await wait(0.3)
	check("join mid-countdown -> back to lobby", gs.phase == "lobby")
	check("...archive grew for the new crew", gs.total == 100 and get_tree().get_nodes_in_group("item").size() == 100, "(total=%d)" % gs.total)
	check("...host's ready flag kept, newcomer not ready", gs.ready_peers == [1], "(%s)" % [gs.ready_peers])
	# newcomer leaves again before readying -> host is the whole crew and is ready
	NetworkManager.players.erase(4242)
	w.host_on_crew_changed()
	await wait(0.3)
	check("newcomer leaves -> archive shrinks, countdown resumes (host was ready)", gs.total == 60 and gs.phase == "countdown", "(total=%d phase=%s)" % [gs.total, gs.phase])
	await wait(3.5)
	check("...and the round starts", gs.phase == "playing")
	# after start, a join changes nothing
	NetworkManager.players[4243] = {"name": "Tobias"}
	w.host_on_crew_changed()
	await wait(0.3)
	check("join while playing -> no resize, still playing", gs.total == 60 and gs.phase == "playing")
	get_tree().quit()
