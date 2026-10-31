## CALLOFBRAWL — settings manager (autoload).
##
## Owns every user-facing option, persists it through Godot's ConfigFile system
## (user://settings.cfg) and broadcasts changes so HUD, camera, audio and the
## renderer can react without knowing about each other.
extends Node

signal changed(key: String, value: Variant)
signal graphics_changed

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "settings"

const FPS_LIMITS: Array[int] = [0, 30, 45, 60, 90, 120]

## Default values. Keep keys flat and primitive so ConfigFile round-trips cleanly.
const DEFAULTS := {
	"look_sensitivity": 0.42,       # touch look, 0.05 .. 1.5
	"ads_sensitivity_mult": 0.55,   # multiplier applied while aiming down sights
	"aim_assist": true,
	"aim_assist_strength": 0.6,     # 0 .. 1
	"aim_assist_radius": 9.0,       # metres
	"aim_assist_fov": 24.0,         # degrees around the crosshair
	"graphics_quality": 2,          # 0 low / 1 medium / 2 high
	"render_scale": 1.0,            # 0.6 .. 1.0
	"sound_volume": 0.9,
	"music_volume": 0.35,
	"fps_limit": 60,
	"hud_scale": 1.0,
	"left_handed": false,
	"show_fps": false,
	"player_name": "Player",
	"score_limit": 50,
	"match_minutes": 10.0,
	"respawn_delay": 3.0,
	"bot_difficulty": 1,            # 0 easy / 1 normal / 2 hard
}

var _data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_data = DEFAULTS.duplicate(true)
	load_settings()
	apply_all()


# ---------------------------------------------------------------- persistence
func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		return
	for key in DEFAULTS.keys():
		var value: Variant = cfg.get_value(SECTION, key, _data[key])
		if typeof(value) == typeof(DEFAULTS[key]):
			_data[key] = value


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	for key in _data.keys():
		cfg.set_value(SECTION, key, _data[key])
	cfg.save(CONFIG_PATH)
	changed.emit("saved", null)


func reset_to_defaults() -> void:
	_data = DEFAULTS.duplicate(true)
	apply_all()
	save_settings()


# ---------------------------------------------------------------- accessors
func get_value(key: String) -> Variant:
	return _data.get(key, DEFAULTS.get(key))


func get_float(key: String) -> float:
	return float(get_value(key))


func get_bool(key: String) -> bool:
	return bool(get_value(key))


func get_int(key: String) -> int:
	return int(get_value(key))


func set_value(key: String, value: Variant) -> void:
	if not _data.has(key) and not DEFAULTS.has(key):
		push_warning("Settings: unknown key '%s'" % key)
		return
	if _data.get(key) == value:
		return
	_data[key] = value
	_apply_one(key, value)
	changed.emit(key, value)


## Apply every value to the live engine state.
func apply_all() -> void:
	Engine.max_fps = get_int("fps_limit")
	Audio.apply_volumes(get_float("sound_volume"), get_float("music_volume"))
	graphics_changed.emit()


func _apply_one(key: String, value: Variant) -> void:
	match key:
		"fps_limit":
			Engine.max_fps = int(value)
		"sound_volume", "music_volume":
			Audio.apply_volumes(get_float("sound_volume"), get_float("music_volume"))
		"graphics_quality", "render_scale":
			graphics_changed.emit()


# ---------------------------------------------------------------- helpers for UI
func fps_limit_index() -> int:
	return maxi(0, FPS_LIMITS.find(get_int("fps_limit")))


# ---------------------------------------------------------------- graphics
## Applies the graphics quality preset + render scale to the active viewport and
## returns whether shadows/particle budgets may be enabled.
func apply_graphics(viewport: Viewport) -> void:
	var quality := get_int("graphics_quality")
	var scale := clampf(get_float("render_scale"), 0.5, 1.0)
	match quality:
		0:
			scale = minf(scale, 0.72)
		1:
			scale = minf(scale, 0.9)
		_:
			pass
	# Keep the device in landscape and hide the navigation bar on phones; harmless on
	# desktop, where these calls are simply ignored.
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	if viewport != null:
		viewport.scaling_3d_scale = scale
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if quality == 0 else Viewport.SCREEN_SPACE_AA_FXAA
		viewport.use_taa = false
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


func quality_shadows_enabled() -> bool:
	return get_int("graphics_quality") >= 1
