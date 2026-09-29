extends CanvasLayer
## res://scenes/ui/PauseMenu.gd — Esc menu during a game. The game doesn't
## actually pause (it's multiplayer); this just frees the mouse and stops
## your own input while it's open.

const SettingsPanelScript := preload("res://scenes/ui/SettingsPanel.gd")
const TITLE_FONT := preload("res://assets/fonts/Alegreya.ttf")

var _root: Control
var _main: PanelContainer
var _settings: PanelContainer


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.035, 0.025, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_main = PanelContainer.new()
	_main.name = "PausePanel"
	_main.custom_minimum_size = Vector2(340, 0)
	center.add_child(_main)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	_main.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "The archive keeps going for your crew."
	sub.modulate = Color(1, 1, 1, 0.7)
	sub.add_theme_font_size_override("font_size", 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	for spec in [["Resume", close], ["Settings", _show_settings],
			["Leave game", _leave], ["Quit to desktop", func(): Sfx.quit_cleanly()]]:
		var b := Button.new()
		b.name = spec[0].replace(" ", "")
		b.text = spec[0]
		b.pressed.connect(spec[1])
		box.add_child(b)
	Sfx.wire_buttons(_main)

	_settings = SettingsPanelScript.new()
	_settings.visible = false
	_settings.closed.connect(_hide_settings)
	center.add_child(_settings)


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _settings.visible:
			_hide_settings()
		elif is_open():
			close()
		else:
			open()


func open() -> void:
	_root.visible = true
	_main.visible = true
	_settings.visible = false
	Settings.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var resume := _main.find_child("Resume", true, false) as Button
	if resume:
		resume.grab_focus()


func close() -> void:
	_root.visible = false
	Settings.menu_open = false
	# keep the mouse free if the win screen is showing
	var hud := get_parent()
	var win_showing: bool = hud != null and "win_panel" in hud and hud.win_panel.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if win_showing else Input.MOUSE_MODE_CAPTURED


func _show_settings() -> void:
	_main.visible = false
	_settings.visible = true


func _hide_settings() -> void:
	_settings.visible = false
	_main.visible = true


func _leave() -> void:
	Settings.menu_open = false
	NetworkManager.leave_game()


func _exit_tree() -> void:
	Settings.menu_open = false
