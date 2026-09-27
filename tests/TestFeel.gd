## tests/TestFeel.gd — headless check of step 6: sounds load, music loops,
## wrong placement flashes, room warms with progress, all types complete,
## sounds/sparkles clean up, M toggles music, Play again resets the room.
## Run from a *copy* of the project: add  TestHarness="*res://tests/TestFeel.gd"
## under [autoload], then  godot --headless -- host
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
	var all_loaded := true
	for k in Sfx.SOUNDS:
		if Sfx.SOUNDS[k] == null: all_loaded = false
	check("all %d sounds load" % Sfx.SOUNDS.size(), all_loaded)
	check("music loop playing, set to loop", Sfx.music_player.playing and (Sfx.music_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD)
	NetworkManager.host_game()
	await wait(2.0)
	var w := get_tree().root.get_node("World")
	var gs = w.get_node("GameState")
	var env: Environment = w.get_node("WorldEnvironment").environment
	var e0 := env.ambient_light_energy
	var f0 := env.fog_density
	var d0: float = w.get_node("Dust").amount_ratio
	check("starts dim and dusty", is_equal_approx(e0, 0.34) and is_equal_approx(d0, 1.0), "(ambient %.2f fog %.3f dust %.2f)" % [e0, f0, d0])
	var completed: Array = []
	gs.category_completed.connect(func(c): completed.append(c))
	# one wrong placement first: slot should flash
	var slots := w.get_node("ShelfSlots")
	var it0: Node = w.get_node("Items/potion_00")
	it0.request_pickup.rpc_id(1)
	var wrong_slot: Node = slots.get_node("Slot_key_29")
	wrong_slot.request_place.rpc_id(1, it0.get_path())
	await get_tree().process_frame
	check("wrong placement flashes the slot", wrong_slot._indicator_material.emission_energy_multiplier > 1.0, "(%.2f)" % wrong_slot._indicator_material.emission_energy_multiplier)
	it0.request_pickup.rpc_id(1)
	it0.request_drop.rpc_id(1)
	await wait(0.2)
	var half_done := false
	var e_half := 0.0
	var n := 0
	for it in get_tree().get_nodes_in_group("item"):
		if it.placed or it.held_by_peer != 0: continue
		it.request_pickup.rpc_id(1)
		for sl in slots.get_children():
			if sl.accepted_category == it.category and not sl.filled:
				sl.request_place.rpc_id(1, it.get_path()); break
		n += 1
		if n % 6 == 0: await get_tree().process_frame
		if not half_done and gs.sorted >= gs.total / 2:
			half_done = true
			await wait(2.0)
			e_half = env.ambient_light_energy
	await wait(2.2)
	check("half-way: room partly warmed", e_half > e0 + 0.08 and e_half < 0.7, "(%.2f)" % e_half)
	check("all 6 types reported complete", completed.size() == 6, "(%s)" % [completed])
	check("finished: warm and clear", env.ambient_light_energy > 0.68 and env.fog_density < 0.0045 and w.get_node("Dust").amount_ratio < 0.2,
		"(ambient %.2f fog %.4f dust %.2f)" % [env.ambient_light_energy, env.fog_density, w.get_node("Dust").amount_ratio])
	var lit: float = w._unit_lights["candle"].light_energy
	check("finished shelves are lit up", lit > 3.9, "(%.2f)" % lit)
	check("win screen shown", w.get_node("GameHUD").win_panel.visible)
	await wait(4.0)
	check("sound players clean up after themselves", Sfx.get_child_count() <= 2, "(%d children)" % Sfx.get_child_count())
	check("sparkle bursts clean up", w.find_children("Spark*", "GPUParticles3D", true, false).size() == 0)
	Sfx.toggle_music()
	await wait(0.8)
	var muted := Sfx.music_player.volume_db < -50
	Sfx.toggle_music()
	await wait(0.8)
	check("M toggles music off and back on", muted and Sfx.music_player.volume_db > -16)
	w.host_restart_round()
	await wait(2.2)
	check("play again: room back to dusty start", absf(env.ambient_light_energy - e0) < 0.02 and w.get_node("Dust").amount_ratio > 0.95,
		"(ambient %.2f)" % env.ambient_light_energy)
	get_tree().quit()
