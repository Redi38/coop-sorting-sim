## tests/TestAim.gd — headless check of the real interaction path.
## For every type and shape: aim the local player's camera at an item,
## call _try_interact() (pick up), aim at a correct shelf slot, interact
## again (place), and verify it locked. Run from a *copy* of the project:
##   1. add  TestHarness="*res://tests/TestAim.gd"  under [autoload]
##   2. godot --headless -- host
## Prints one PASS/FAIL line per shape.
extends Node
# Real interaction path: aim the local player's camera, call _try_interact.
func _ready() -> void:
	if OS.get_cmdline_user_args().is_empty(): return
	if OS.get_cmdline_user_args()[0] != "host": get_tree().quit(); return
	await get_tree().create_timer(0.3).timeout
	NetworkManager.host_game()
	await get_tree().create_timer(2.5).timeout
	var w := get_tree().root.get_node("World")
	var p: CharacterBody3D = w.get_node("Players/1")
	var cam: Camera3D = p.get_node("Camera3D")
	var ray: RayCast3D = p.interact_ray
	var gs = w.get_node("GameState")
	var ok_all := true
	for cat in ItemCatalog.get_categories():
		for variant in cat.variants.size():
			var it: Node3D = null
			for i in get_tree().get_nodes_in_group("item"):
				if i.category == cat.id and i.variant == variant and not i.placed and i.held_by_peer == 0:
					it = i; break
			if it == null:
				print("HOST [FAIL] no free %s variant %d" % [cat.id, variant]); ok_all = false; continue
			# stand 0.9 m away and look at the item's middle
			var aim_at: Vector3 = it.global_position + Vector3(0, 0.03, 0)
			p.global_position = it.global_position + Vector3(0.9, 0.0, 0.0)
			await get_tree().physics_frame
			cam.look_at(aim_at)
			ray.force_raycast_update()
			var hover_item = p._item_from_collider(ray.get_collider())
			p._try_interact()
			await get_tree().create_timer(0.15).timeout
			var picked: bool = it.held_by_peer == 1
			# walk to a free correct slot and aim at it
			var slot: Node3D = null
			for s in w.get_node("ShelfSlots").get_children():
				if s.accepted_category == cat.id and not s.filled:
					slot = s; break
			var fwd: Vector3 = slot.global_transform.basis.z
			p.global_position = slot.global_position + fwd * 1.0 - Vector3(0, slot.global_position.y, 0)
			await get_tree().physics_frame
			await get_tree().physics_frame
			cam.look_at(slot.global_position + Vector3(0, 0.17, 0))
			ray.force_raycast_update()
			var aimed_slot: bool = ray.get_collider() == slot
			p._try_interact()
			await get_tree().create_timer(0.15).timeout
			var placed_ok: bool = it.placed and slot.locked
			var ok: bool = hover_item == it and picked and aimed_slot and placed_ok
			ok_all = ok_all and ok
			print("HOST [%s] aim-pickup-place %s/%s (hover=%s picked=%s slot_aimed=%s locked=%s)" % [
				"PASS" if ok else "FAIL", cat.id, cat.variants[variant].model_path.get_file(),
				hover_item == it, picked, aimed_slot, placed_ok])
	print("HOST [INFO] sorted=%d mistakes=%d" % [gs.sorted, gs.mistakes])
	get_tree().quit()
