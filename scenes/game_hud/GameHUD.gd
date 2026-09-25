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

var _game_state: Node  # GameState.gd


func _ready() -> void:
	_game_state = get_node("../GameState")
	_game_state.state_changed.connect(_refresh)
	_game_state.round_finished.connect(_show_win_panel)
	_game_state.round_reset.connect(_hide_win_panel)
	play_again_button.pressed.connect(_on_play_again_pressed)
	leave_button.pressed.connect(NetworkManager.leave_game)
	win_panel.visible = false
	_refresh()


func _process(_delta: float) -> void:
	# The timer ticks locally between snapshots, so redraw it every frame.
	timer_label.text = GameStateScript.format_time(_game_state.elapsed)
	timer_label.modulate.a = 1.0 if _game_state.running or _game_state.finished else 0.5


func _refresh() -> void:
	var gs := _game_state
	progress_label.text = "Sorted %d / %d    Mistakes %d" % [gs.sorted, gs.total, gs.mistakes]
	progress_bar.value = (float(gs.sorted) / gs.total) if gs.total > 0 else 0.0

	# Per-category counts, each in its category's own color — the same
	# visual clue the items and shelf pads use.
	var parts: PackedStringArray = []
	for cat in ItemCatalog.get_categories():
		if not gs.per_category.has(cat.id):
			continue
		var c: Dictionary = gs.per_category[cat.id]
		parts.append("[color=#%s]%s %d/%d[/color]" % [
			cat.color.to_html(false), cat.display_name, c["sorted"], c["total"]])
	var hint := "" if gs.running or gs.finished or gs.sorted > 0 else "    [i]Pick up an item to start the clock[/i]"
	category_label.text = "[center]%s%s[/center]" % ["    ".join(parts), hint]

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
	win_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_host:
		play_again_button.grab_focus()


func _hide_win_panel() -> void:
	win_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_play_again_pressed() -> void:
	if multiplayer.is_server():
		get_parent().host_restart_round()
