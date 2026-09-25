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
