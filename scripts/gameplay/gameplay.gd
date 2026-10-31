## CALLOFBRAWL — match scene controller.
##
## Boot order
##   1. build the world environment + sun (cheap, mobile-friendly)
##   2. load de_dust2 (geometry, collision, baked navigation region)
##   3. create the local player, mobile input, aim assist and HUD
##   4. hand control to MatchManager which spawns the 5 v 5 roster
##
## This node also owns the pause/restart/menu flow so scenes stay simple.
extends Node3D

const MAIN_MENU_SCENE := "res://scenes/menus/main_menu.tscn"

var map_loader: CBMapLoader
var player: CBPlayerController
var mobile_input: CBMobileInputController
var hud: CBHudController
var match_manager: CBMatchManager
var aim_assist: CBAimAssist
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var settings_panel: CBSettingsPanel

var _ready_done: bool = false


func _ready() -> void:
	Game.configure_match()
	randomize()
	_build_environment()
	_build_world()
	_build_player()
	_build_ui()
	_start_match()
	_ready_done = true


# ---------------------------------------------------------------- world
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.29, 0.44, 0.66)
	sky_mat.sky_horizon_color = Color(0.78, 0.76, 0.70)
	sky_mat.ground_bottom_color = Color(0.24, 0.21, 0.17)
	sky_mat.ground_horizon_color = Color(0.62, 0.58, 0.50)
	sky_mat.sun_angle_max = 22.0
	sky_mat.sky_energy_multiplier = 0.9
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.72, 0.74, 0.78)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = Settings.get_int("graphics_quality") >= 2
	env.fog_light_color = Color(0.74, 0.76, 0.80)
	env.fog_density = 0.006
	env.glow_enabled = false
	env.ssao_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.05

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.15
	sun.shadow_enabled = Settings.get_int("graphics_quality") > 0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	Settings.apply_graphics(get_viewport())


func _build_world() -> void:
	map_loader = CBMapLoader.new()
	map_loader.name = "Map"
	add_child(map_loader)
	map_loader.load_map()


func _build_player() -> void:
	player = CBPlayerController.new()
	player.name = "Player"
	add_child(player)
	player.configure(Game.local_combatant_id, str(Settings.get_value("player_name")), CBTeam.ALPHA)
	player.died.connect(_on_player_died)


func _build_ui() -> void:
	# --- mobile controls
	mobile_input = CBMobileInputController.new()
	mobile_input.name = "MobileInput"
	add_child(mobile_input)

	# --- aim assist
	aim_assist = CBAimAssist.new()
	aim_assist.name = "AimAssist"
	add_child(aim_assist)
	aim_assist.setup(CBTeam.ALPHA, player.camera)

	mobile_input.bind_target(player, aim_assist)

	# --- match
	match_manager = CBMatchManager.new()
	match_manager.name = "MatchManager"
	add_child(match_manager)
	match_manager.setup(map_loader, player)

	# --- hud
	hud = CBHudController.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(player, match_manager, mobile_input)
	hud.restart_requested.connect(_on_restart)
	hud.menu_requested.connect(_on_menu)
	hud.settings_requested.connect(_on_settings_from_pause)
	hud.pause_toggled.connect(_on_pause_toggled)

	mobile_input.hud = hud

	# --- settings overlay (used from the pause menu)
	settings_panel = CBSettingsPanel.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.visible = false
	hud.add_child(settings_panel)
	settings_panel.closed.connect(_on_settings_closed)


func _start_match() -> void:
	match_manager.start_match()
	hud.push_toast("GOOD LUCK, %s" % str(Settings.get_value("player_name")).to_upper())


# ---------------------------------------------------------------- events
func _on_player_died(attacker_id: String, headshot: bool) -> void:
	if match_manager != null:
		match_manager.on_player_died(attacker_id, headshot)


func _on_pause_toggled(paused: bool) -> void:
	if paused and mobile_input != null:
		mobile_input.set_enabled(false)
	elif not paused and mobile_input != null:
		mobile_input.set_enabled(true)


func _on_settings_from_pause() -> void:
	if settings_panel == null:
		return
	# hide the pause buttons while settings are open, so only one modal is interactive
	hud.hide_pause_menu()
	settings_panel.visible = true
	settings_panel.open()


func _on_settings_closed() -> void:
	# back to the pause menu (still paused) rather than straight into the match
	if hud != null:
		hud.visible = true
		hud.restore_pause_menu()


func _on_restart() -> void:
	Game.restart_match()


func _on_menu() -> void:
	Game.go_to_menu()


func _process(_delta: float) -> void:
	# apply the aim-assist rotation nudge (never snaps, capped per frame)
	if aim_assist != null and player != null and player.is_alive and not get_tree().paused:
		var assist = aim_assist.rotation_assist()
		if assist != Vector2.ZERO:
			player.add_look(assist.x, assist.y)
		if hud != null and hud.crosshair != null:
			hud.crosshair.aim_engaged = aim_assist.is_tracking()
