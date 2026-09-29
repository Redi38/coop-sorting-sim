extends Control

@onready var name_input: LineEdit = %NameInput
@onready var ip_input: LineEdit = %IpInput
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	_add_menu_extras()
	Sfx.wire_buttons(self)
	Settings.menu_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


const SettingsPanelScript := preload("res://scenes/ui/SettingsPanel.gd")
var _settings_panel: PanelContainer
var _settings_layer: CenterContainer

## Settings + Quit under Host/Join, and the settings panel as an overlay.
func _add_menu_extras() -> void:
	var box := join_button.get_parent()
	var settings_btn := Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = "Settings"
	box.add_child(settings_btn)
	box.move_child(settings_btn, join_button.get_index() + 1)
	var quit_btn := Button.new()
	quit_btn.name = "QuitButton"
	quit_btn.text = "Quit"
	box.add_child(quit_btn)
	box.move_child(quit_btn, settings_btn.get_index() + 1)
	quit_btn.pressed.connect(func(): Sfx.quit_cleanly())

	_settings_layer = CenterContainer.new()
	_settings_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_layer.visible = false
	add_child(_settings_layer)
	_settings_panel = SettingsPanelScript.new()
	_settings_layer.add_child(_settings_panel)
	var menu_center := box.get_parent()
	settings_btn.pressed.connect(func():
		menu_center.visible = false
		_settings_layer.visible = true)
	_settings_panel.closed.connect(func():
		_settings_layer.visible = false
		menu_center.visible = true)


func _on_host_pressed() -> void:
	NetworkManager.local_player_name = _display_name()
	var err := NetworkManager.host_game()
	if err != OK:
		status_label.text = "Failed to host (port %d busy?)." % NetworkManager.PORT


func _on_join_pressed() -> void:
	NetworkManager.local_player_name = _display_name()
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	status_label.text = "Connecting to %s ..." % address
	NetworkManager.join_game(address)


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP and try again."


func _display_name() -> String:
	var n := name_input.text.strip_edges()
	return n if not n.is_empty() else "Player"
