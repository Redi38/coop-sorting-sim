extends PanelContainer
## res://scenes/ui/SettingsPanel.gd — settings UI, used by the main menu and
## the pause menu. Every change applies and saves immediately (Settings.gd).

signal closed

const TITLE_FONT := preload("res://assets/fonts/Alegreya.ttf")

var _tips_note: Label


func _ready() -> void:
	custom_minimum_size = Vector2(420, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var s_range := Settings.SENS_MAX - Settings.SENS_MIN
	_slider_row(box, "Mouse sensitivity", (Settings.mouse_sensitivity - Settings.SENS_MIN) / s_range,
		func(v): Settings.set_value("mouse_sensitivity", Settings.SENS_MIN + v * s_range))
	_slider_row(box, "Master volume", Settings.master_volume, func(v): Settings.set_value("master_volume", v))
	_slider_row(box, "Music", Settings.music_volume, func(v): Settings.set_value("music_volume", v))
	_slider_row(box, "Effects", Settings.sfx_volume, func(v): Settings.set_value("sfx_volume", v))

	var fs := CheckButton.new()
	fs.name = "Fullscreen"
	fs.text = "Fullscreen"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on): Settings.set_value("fullscreen", on))
	box.add_child(fs)

	var tips := Button.new()
	tips.name = "ReplayTips"
	tips.text = "Show the beginner tips again"
	tips.pressed.connect(func():
		Settings.reset_tutorial()
		_tips_note.text = "Tips will show again in your next round.")
	box.add_child(tips)
	_tips_note = Label.new()
	_tips_note.add_theme_font_size_override("font_size", 13)
	_tips_note.modulate = Color(1, 1, 1, 0.7)
	_tips_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_tips_note)

	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.pressed.connect(func(): closed.emit())
	box.add_child(back)
	Sfx.wire_buttons(self)


func _slider_row(parent: Node, label_text: String, value01: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.name = label_text.replace(" ", "")
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = clampf(value01, 0.0, 1.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(46, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = "%d%%" % int(round(slider.value * 100))
	row.add_child(pct)
	slider.value_changed.connect(func(v):
		pct.text = "%d%%" % int(round(v * 100))
		on_change.call(v))
	parent.add_child(row)
	return slider
