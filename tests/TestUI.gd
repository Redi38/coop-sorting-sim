## tests/TestUI.gd — headless solo check of step 7: settings save/reload/apply,
## lobby says "press R", countdown, beginner tips advance by doing, Esc pause
## menu blocks input, settings from the pause menu, taking a misplaced item
## back off the shelf by aiming at it, main menu Settings/Quit.
## Run from a *copy*: add  TestHarness="*res://tests/TestUI.gd"  under [autoload],
## then  godot --headless -- host
extends Node
var role := ""
func check(name: String, ok: bool, detail := "") -> void:
	print("%s [%s] %s %s" % [role.to_upper(), "PASS" if ok else "FAIL", name, detail])
func wait(t: float) -> void: await get_tree().create_timer(t).timeout
func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame
func aim(p: Node3D, stand: Vector3, target: Vector3) -> void:
	p.global_position = stand
	await get_tree().physics_frame
	p.get_node("Camera3D").look_at(target)
	p.interact_ray.force_raycast_update()
	await get_tree().physics_frame
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
	if role != "host": get_tree().quit(); return
	await wait(0.3)
	# --- settings persist + apply
	var old_sens: float = Settings.mouse_sensitivity
	var old_music: float = Settings.music_volume
	Settings.set_value("mouse_sensitivity", 0.004)
	Settings.set_value("music_volume", 0.3)
	var cfg := ConfigFile.new()
	var loaded := cfg.load(Settings.PATH) == OK
	check("settings saved to disk", loaded and is_equal_approx(cfg.get_value("controls", "mouse_sensitivity"), 0.004) and is_equal_approx(cfg.get_value("audio", "music"), 0.3))
	var music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	check("music volume applied to the Music bus", absf(music_db - linear_to_db(0.3)) < 0.01, "(%.1f dB)" % music_db)
	Settings.mouse_sensitivity = 0.0
	Settings.load_settings()
	check("settings reload from disk", is_equal_approx(Settings.mouse_sensitivity, 0.004))
	Settings.reset_tutorial()
	NetworkManager.host_game()
	await wait(2.0)
	var w := get_tree().root.get_node("World")
	var gs = w.get_node("GameState")
	var hud = w.get_node("GameHUD")
	var me: CharacterBody3D = w.get_node("Players/1")
	check("solo lobby says press R", hud.lobby_panel.visible and hud.lobby_info.text.begins_with("Press R"), "('%s')" % hud.lobby_info.text)
	check("no tips during the lobby", hud.tutorial.current_hint() == "")
	await press("ready")
	await poll(func(): return gs.phase == "playing", 6)
	check("solo: R -> countdown -> playing", gs.phase == "playing")
	# --- tips advance by doing
	await wait(0.2)
	check("first tip: look at an item", hud.tutorial.current_hint() == "look", "('%s')" % hud.tutorial.current_hint())
	var it: Node3D = null
	for i in get_tree().get_nodes_in_group("item"):
		if i.category == "tome": it = i; break
	await aim(me, it.global_position + Vector3(0.9, 0, 0), it.global_position + Vector3(0, 0.03, 0))
	var ok := await poll(func(): return hud.tutorial.current_hint() == "pickup", 3)
	check("looking at an item -> next tip: pick up", ok, "('%s')" % hud.tutorial.current_hint())
	# --- pause menu blocks input
	await press("ui_cancel")
	check("Esc opens the pause menu", hud.pause_menu.is_open() and Settings.menu_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	check("tips hide while paused", hud.tutorial.current_hint() == "")
	await press("interact")
	await wait(0.2)
	check("gameplay input ignored while paused", it.held_by_peer == 0)
	var settings_btn: Button = hud.pause_menu.find_child("Settings", true, false)
	settings_btn.pressed.emit()
	var slider: HSlider = hud.pause_menu.find_child("Music", true, false)
	slider.value = 0.55
	check("settings from the pause menu work", is_equal_approx(Settings.music_volume, 0.55))
	await press("ui_cancel")   # back from settings
	await press("ui_cancel")   # close menu
	check("Esc closes it again", not hud.pause_menu.is_open() and not Settings.menu_open)
	await press("interact")
	await wait(0.2)
	check("input works again after closing", it.held_by_peer == 1)
	ok = await poll(func(): return hud.tutorial.current_hint() == "place", 3)
	check("picked up -> next tip: find the shelf", ok, "('%s')" % hud.tutorial.current_hint())
	# wrong first: tip about mistakes
	var wrong_slot: Node3D = w.get_node("ShelfSlots/Slot_key_20")
	await aim(me, wrong_slot.global_position + wrong_slot.global_transform.basis.z * 1.0 - Vector3(0, wrong_slot.global_position.y, 0), wrong_slot.global_position + Vector3(0, 0.17, 0))
	var c = me.interact_ray.get_collider()
	print("HOST [INFO] aiming at wrong slot: ray hits %s, holding %d, slot at %s, me at %s" % [c.get_path() if c else "nothing", me.held_items.size(), wrong_slot.global_position, me.global_position])
	await press("interact")
	await wait(0.3)
	print("HOST [INFO] after E press: placed=%s held_by=%d mistakes=%d phase=%s menu_open=%s" % [it.placed, it.held_by_peer, gs.mistakes, gs.phase, Settings.menu_open])
	if not it.placed:
		me._try_interact()
		await wait(0.3)
		print("HOST [INFO] after direct _try_interact: placed=%s mistakes=%d" % [it.placed, gs.mistakes])
	ok = await poll(func(): return hud.tutorial.current_hint() == "wrong", 3)
	check("a mistake shows the 'take it back' tip", ok)
	# take the misplaced item back out, by aiming at it on the shelf
	await aim(me, it.global_position + wrong_slot.global_transform.basis.z * 0.9 - Vector3(0, it.global_position.y, 0), it.global_position + Vector3(0, 0.04, 0))
	check("hovering a misplaced item shows its label", me._hovered_item == it)
	await press("interact")
	await wait(0.3)
	check("aim + E takes a misplaced item back off the shelf", it.held_by_peer == 1 and not wrong_slot.filled)
	var slot: Node3D = w.get_node("ShelfSlots/Slot_tome_3")
	await aim(me, slot.global_position + slot.global_transform.basis.z * 1.0 - Vector3(0, slot.global_position.y, 0), slot.global_position + Vector3(0, 0.17, 0))
	await press("interact")
	await wait(0.3)
	check("correct placement recorded", gs.player_stats.get(1, {}).get("correct", 0) == 1)
	await wait(7.5)   # let the wrong tip finish
	check("solo: all tips done, none left (ping/toss need a crew)",
		hud.tutorial.current_hint() == "" and Settings.is_hint_done("look") and Settings.is_hint_done("pickup") and Settings.is_hint_done("place") and not Settings.is_hint_done("ping"),
		"(current '%s')" % hud.tutorial.current_hint())
	# --- main menu extras
	NetworkManager.leave_game()
	await wait(1.0)
	var menu := get_tree().current_scene
	check("main menu has Settings and Quit", menu.find_child("SettingsButton", true, false) != null and menu.find_child("QuitButton", true, false) != null)
	# restore
	Settings.set_value("mouse_sensitivity", old_sens)
	Settings.set_value("music_volume", old_music)
	get_tree().quit()
