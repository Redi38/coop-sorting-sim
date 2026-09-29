extends CanvasLayer
## res://scenes/game_hud/GameHUD.tscn — instanced in World.tscn as a sibling
## of World/GameState. Pure view: reads GameState, never changes it. The one
## action it can trigger (Play again) is only shown to the host.

## Referenced by path, not by class_name, so it works even when
## Godot's global class cache hasn't been refreshed yet.
const GameStateScript := preload("res://scenes/world/GameState.gd")

@onready var progress_label: Label = %ProgressLabel
@onready var timer_label: Label = %TimerLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var category_label: RichTextLabel = %CategoryLabel
@onready var win_panel: PanelContainer = %WinPanel
@onready var stats_label: Label = %StatsLabel
@onready var player_stats_label: Label = %PlayerStatsLabel
@onready var play_again_button: Button = %PlayAgainButton
@onready var waiting_label: Label = %WaitingLabel
@onready var leave_button: Button = %LeaveButton
@onready var crew_list: VBoxContainer = %CrewList
@onready var toast: PanelContainer = %Toast
@onready var toast_label: Label = %ToastLabel

const CoopPlayerScript := preload("res://scenes/player/Player.gd")
const TOAST_TIME := 3.5
var _known_players: Dictionary = {}   # peer_id -> name, for join/leave notices
var _last_total := 0
var _toast_tween: Tween

var _game_state: Node  # GameState.gd


const PauseMenuScript := preload("res://scenes/ui/PauseMenu.gd")
const TutorialHintsScript := preload("res://scenes/ui/TutorialHints.gd")
const TITLE_FONT := preload("res://assets/fonts/Alegreya.ttf")

var lobby_panel: PanelContainer
var lobby_title: Label
var lobby_info: Label
var lobby_host_note: Label
var countdown_label: Label
var pause_menu: CanvasLayer
var tutorial: PanelContainer
var _sort_flash := 0.0


func _ready() -> void:
	_game_state = get_node("../GameState")
	_build_lobby_ui()
	tutorial = TutorialHintsScript.new()
	add_child(tutorial)
	pause_menu = PauseMenuScript.new()
	add_child(pause_menu)
	_game_state.phase_changed.connect(_on_phase_changed)
	_game_state.state_changed.connect(_refresh)
	_game_state.round_finished.connect(_show_win_panel)
	_game_state.round_reset.connect(_hide_win_panel)
	play_again_button.pressed.connect(_on_play_again_pressed)
	leave_button.pressed.connect(NetworkManager.leave_game)
	win_panel.visible = false
	NetworkManager.player_list_changed.connect(_refresh_crew)
	_game_state.category_completed.connect(_on_category_completed)
	Sfx.wire_buttons(self)
	_refresh_crew()
	_refresh()


func _process(_delta: float) -> void:
	# The timer ticks locally between snapshots, so redraw it every frame.
	timer_label.text = GameStateScript.format_time(_game_state.elapsed)
	timer_label.modulate.a = 1.0 if _game_state.running or _game_state.finished else 0.5
	_update_countdown(_delta)


func _refresh() -> void:
	var gs := _game_state
	progress_label.text = "Sorted %d / %d    Mistakes %d" % [gs.sorted, gs.total, gs.mistakes]
	progress_bar.value = (float(gs.sorted) / gs.total) if gs.total > 0 else 0.0

	# Per-type counts. Neutral text on purpose: colour is never a type
	# clue (DESIGN.md). A finished type is shown in gold with a tick.
	var parts: PackedStringArray = []
	for cat in ItemCatalog.get_categories():
		if not gs.per_category.has(cat.id):
			continue
		var c: Dictionary = gs.per_category[cat.id]
		if c["total"] > 0 and c["sorted"] >= c["total"]:
			parts.append("[color=#e9c46a]%s ✓[/color]" % cat.display_name)
		else:
			parts.append("%s %d/%d" % [cat.display_name, c["sorted"], c["total"]])
	category_label.text = "[center]%s[/center]" % "    ".join(parts)
	_refresh_lobby()

	# The archive resized for the crew (only happens before the first pickup).
	if _last_total > 0 and gs.total != _last_total and not gs.running and not gs.finished:
		show_toast("The archive now holds %d items" % gs.total)
	_last_total = gs.total

	if gs.finished and not win_panel.visible:
		_show_win_panel()  # late joiner arriving after the round ended


func _show_win_panel() -> void:
	var gs := _game_state
	var accuracy := 100.0
	if gs.sorted + gs.mistakes > 0:
		accuracy = 100.0 * gs.sorted / (gs.sorted + gs.mistakes)
	stats_label.text = "Time: %s\nMistakes: %d\nAccuracy: %d%%" % [
		GameStateScript.format_time(gs.elapsed), gs.mistakes, int(round(accuracy))]

	var rows: Array = gs.player_stats.values()
	rows.sort_custom(func(a, b): return a["correct"] > b["correct"])
	var lines: PackedStringArray = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var crown := "★ " if i == 0 and rows.size() > 1 else ""
		lines.append("%s%s — %d sorted, %d mistake%s" % [
			crown, r["name"], r["correct"], r["wrong"], "" if r["wrong"] == 1 else "s"])
	player_stats_label.text = "\n".join(lines)

	var is_host := multiplayer.is_server()
	play_again_button.visible = is_host
	waiting_label.visible = not is_host
	if not win_panel.visible:
		Sfx.play("round_complete")
	win_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_host:
		play_again_button.grab_focus()


func _on_category_completed(cat_id: String) -> void:
	var cat := ItemCatalog.get_category(cat_id)
	show_toast("%s complete!" % (cat.display_name if cat else cat_id))
	if not _game_state.finished:
		Sfx.play("category_complete")


func _hide_win_panel() -> void:
	win_panel.visible = false
	if not Settings.menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_play_again_pressed() -> void:
	if multiplayer.is_server():
		get_parent().host_restart_round()


# ---------------------------------------------------------------------------
# Crew list + notices
# ---------------------------------------------------------------------------

func _refresh_crew() -> void:
	var me := multiplayer.get_unique_id()
	var current: Dictionary = {}
	for peer_id in NetworkManager.players:
		current[peer_id] = NetworkManager.players[peer_id].get("name", "Player")
	# join/leave notices (skip the very first fill, and ourselves)
	if not _known_players.is_empty():
		for peer_id in current:
			if not _known_players.has(peer_id) and peer_id != me:
				show_toast("%s joined the archive" % current[peer_id])
		for peer_id in _known_players:
			if not current.has(peer_id):
				show_toast("%s left the archive" % _known_players[peer_id])
	_known_players = current

	for child in crew_list.get_children():
		child.queue_free()
	var ids := current.keys()
	ids.sort()
	for peer_id in ids:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = CoopPlayerScript.ROBE_COLORS[peer_id % CoopPlayerScript.ROBE_COLORS.size()]
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := Label.new()
		name_label.text = current[peer_id] + ("  (you)" if peer_id == me else "")
		if _game_state.round_not_started() and _game_state.ready_peers.has(peer_id):
			name_label.text += "  · ready"
			name_label.add_theme_color_override("font_color", Color(0.72, 0.9, 0.6))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		row.add_child(name_label)
		crew_list.add_child(row)


func show_toast(text: String) -> void:
	toast_label.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_TIME)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(func(): toast.visible = false)


# ---------------------------------------------------------------------------
# Lobby: ready-up panel + 3-2-1 countdown
# ---------------------------------------------------------------------------

func _build_lobby_ui() -> void:
	lobby_panel = PanelContainer.new()
	lobby_panel.name = "LobbyPanel"
	lobby_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby_panel.anchor_left = 0.5
	lobby_panel.anchor_right = 0.5
	lobby_panel.offset_left = -230
	lobby_panel.offset_right = 230
	lobby_panel.offset_top = 128
	lobby_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	lobby_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	lobby_title = Label.new()
	lobby_title.text = "The archive awaits"
	lobby_title.add_theme_font_override("font", TITLE_FONT)
	lobby_title.add_theme_font_size_override("font_size", 28)
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lobby_title)
	lobby_info = Label.new()
	lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lobby_info)
	lobby_host_note = Label.new()
	lobby_host_note.text = "You're the host: press R again to start without waiting."
	lobby_host_note.add_theme_font_size_override("font_size", 13)
	lobby_host_note.modulate = Color(1, 1, 1, 0.65)
	lobby_host_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lobby_host_note)
	add_child(lobby_panel)

	countdown_label = Label.new()
	countdown_label.name = "Countdown"
	countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	countdown_label.offset_left = -200
	countdown_label.offset_right = 200
	countdown_label.offset_top = -90
	countdown_label.offset_bottom = 30
	countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_override("font", TITLE_FONT)
	countdown_label.add_theme_font_size_override("font_size", 110)
	countdown_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	countdown_label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.05))
	countdown_label.add_theme_constant_override("outline_size", 14)
	countdown_label.visible = false
	add_child(countdown_label)


func _refresh_lobby() -> void:
	if lobby_panel == null:
		return
	var gs := _game_state
	var show: bool = gs.phase == "lobby"
	lobby_panel.visible = show
	if gs.round_not_started():
		_refresh_crew()   # ready markers (also during the countdown)
	if not show:
		return
	var crew: int = maxi(1, NetworkManager.players.size())
	var me := multiplayer.get_unique_id()
	var i_am_ready: bool = gs.ready_peers.has(me)
	if crew == 1:
		lobby_info.text = "Press R to begin." if not i_am_ready else "Starting..."
	else:
		lobby_info.text = "%s    %d / %d ready" % [
			"Press R when you're ready." if not i_am_ready else "You're ready. Press R to un-ready.",
			gs.ready_peers.size(), crew]
	lobby_host_note.visible = multiplayer.is_server() and i_am_ready and crew > 1 \
		and gs.ready_peers.size() < crew


func _on_phase_changed(new_phase: String) -> void:
	if new_phase == "playing":
		_sort_flash = 0.9
		Sfx.play("category_complete", null, -6.0)
	_refresh_lobby()
	_refresh_crew()


func _update_countdown(delta: float) -> void:
	if countdown_label == null:
		return
	var gs := _game_state
	if gs.phase == "countdown":
		countdown_label.visible = true
		countdown_label.text = str(int(ceil(maxf(gs.countdown_left, 0.01))))
	elif _sort_flash > 0.0:
		_sort_flash -= delta
		countdown_label.visible = true
		countdown_label.text = "Sort!"
		countdown_label.modulate.a = clampf(_sort_flash / 0.4, 0.0, 1.0)
		return
	else:
		countdown_label.visible = false
	countdown_label.modulate.a = 1.0
