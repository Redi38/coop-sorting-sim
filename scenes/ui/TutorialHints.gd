extends PanelContainer
## res://scenes/ui/TutorialHints.gd — onboarding by doing. One small tip at a
## time, bottom-centre, during your first rounds. Each tip disappears once
## you've done the thing it describes and never comes back (saved in
## Settings). Settings → "Show the beginner tips again" resets them.

# id, text, only-with-a-crew
const STEPS := [
	["look", "Look at an item to read its name and description.", false],
	["pickup", "Press E to pick it up. You can carry three at once.", false],
	["place", "Take it to the shelf whose sign fits: read the rule and match the shape. Colour is only decoration!", false],
	["ping", "Not sure where something goes? Press G on it to ask your crew. On a shelf, G says \"over here\".", true],
	["toss", "Right-click tosses what you're holding, handy for passing things to a friend.", true],
]
const WRONG_TEXT := "Not quite! Press E on it to take it back out, then try another shelf."
const WRONG_SHOW_TIME := 7.0
const GAP := 1.0   # pause between tips

var _label: Label
var _current := ""     # the step being taught
var _showing := ""     # what's on screen right now (a step, or "wrong")
var _gap_left := 0.0
var _wrong_left := 0.0
var _ping_baseline := -1.0
var _toss_baseline := -1


func _ready() -> void:
	name = "TutorialHints"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -300
	offset_right = 300
	offset_top = -178
	offset_bottom = -126
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.66))
	margin.add_child(_label)
	visible = false


func current_hint() -> String:
	return _showing if visible else ""


func _process(delta: float) -> void:
	var gs = _game_state()
	var me := _local_player()
	if gs == null or me == null or gs.phase != "playing" or Settings.menu_open:
		visible = false
		return
	var my_id := multiplayer.get_unique_id()
	var stats: Dictionary = gs.player_stats.get(my_id, {})

	# a first mistake interrupts with its own tip, once
	if not Settings.is_hint_done("wrong") and stats.get("wrong", 0) >= 1 and _wrong_left <= 0.0:
		_wrong_left = WRONG_SHOW_TIME
		Settings.mark_hint_done("wrong")
	if _wrong_left > 0.0:
		_wrong_left -= delta
		_show("wrong", WRONG_TEXT)
		return

	if _current != "" and _is_step_done(_current, me, stats):
		Settings.mark_hint_done(_current)
		_current = ""
		_gap_left = GAP
	if _gap_left > 0.0:
		_gap_left -= delta
		visible = false
		return
	if _current == "":
		var crew := NetworkManager.players.size()
		for step in STEPS:
			if Settings.is_hint_done(step[0]) or (step[2] and crew < 2):
				continue
			_current = step[0]
			_ping_baseline = me._last_ping_time
			_toss_baseline = me.tossed_count
			break
	if _current == "":
		visible = false
		return
	for step in STEPS:
		if step[0] == _current:
			_show(_current, step[1])


func _show(id: String, text: String) -> void:
	_showing = id
	_label.text = text
	visible = true
	if id == "wrong":
		_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.66))
	else:
		_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.66))


func _is_step_done(id: String, me: Node, stats: Dictionary) -> bool:
	match id:
		"look":
			return is_instance_valid(me._hovered_item) and me._hovered_item != null
		"pickup":
			return not me.held_items.is_empty()
		"place":
			return stats.get("correct", 0) >= 1
		"ping":
			return me._last_ping_time > _ping_baseline
		"toss":
			return me.tossed_count > _toss_baseline
	return true


func _game_state():
	return get_tree().get_first_node_in_group("game_state")


func _local_player() -> Node:
	var world := NetworkManager.world
	if world == null:
		return null
	return world.get_node_or_null("Players/%d" % multiplayer.get_unique_id())
