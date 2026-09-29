extends Node
## res://autoload/Settings.gd — autoload "Settings"
##
## Player preferences, saved to user://settings.cfg: mouse sensitivity,
## volumes (master / music / effects), fullscreen, and which onboarding
## hints this player has already completed. Also owns the "Music" and
## "SFX" audio buses (Sfx.gd plays on them) and the menu_open flag that
## gameplay input checks.

signal changed

const PATH := "user://settings.cfg"
const SENS_MIN := 0.0006
const SENS_MAX := 0.006

var mouse_sensitivity := 0.0025
var master_volume := 1.0     # linear 0..1
var music_volume := 0.8
var sfx_volume := 1.0
var fullscreen := false
var tutorial_done: Dictionary = {}   # hint id -> true

## True while a menu (pause, settings) is open: Player ignores gameplay
## input and keeps the mouse free.
var menu_open := false


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	load_settings()
	apply()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first run: keep defaults
	mouse_sensitivity = clampf(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity), SENS_MIN, SENS_MAX)
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	var done = cfg.get_value("tutorial", "done", {})
	tutorial_done = done if done is Dictionary else {}


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("tutorial", "done", tutorial_done)
	cfg.save(PATH)


## Pushes the current values into the engine.
func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	changed.emit()


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


## Set one value, apply and save (settings UI calls this on every change).
func set_value(key: String, value) -> void:
	set(key, value)
	apply()
	save_settings()


# --- onboarding hints --------------------------------------------------------

func is_hint_done(id: String) -> bool:
	return tutorial_done.get(id, false)


func mark_hint_done(id: String) -> void:
	if is_hint_done(id):
		return
	tutorial_done[id] = true
	save_settings()


func reset_tutorial() -> void:
	tutorial_done = {}
	save_settings()
	changed.emit()
