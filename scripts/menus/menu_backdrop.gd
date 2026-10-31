## CALLOFBRAWL — animated 3D menu backdrop.
##
## Renders inside a SubViewport behind the main menu: the provided de_dust2 map with
## its original materials, a hero soldier from army_character_1.glb carrying the
## AK-47, a slow orbit camera and drifting dust motes. Purely presentational.
extends Node3D

const MAP_PATH := "res://de_dust2_-_cs_map.glb"
const CHARACTER_PATH := "res://army_character_1.glb"

var camera: Camera3D
var hero: Node3D
var _t: float = 0.0
var _orbit_radius: float = 7.5
var _focus: Vector3 = Vector3(-4.0, 1009.6, 1235.0)


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_map()
	_build_hero()
	_build_dust()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.13, 0.20, 0.34)
	mat.sky_horizon_color = Color(0.55, 0.44, 0.36)
	mat.ground_horizon_color = Color(0.22, 0.18, 0.14)
	mat.ground_bottom_color = Color(0.09, 0.08, 0.07)
	mat.sun_angle_max = 18.0
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.40, 0.38)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 140, 0)
	sun.light_color = Color(1.0, 0.86, 0.70)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = _focus + Vector3(2.0, 2.0, 2.0)
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 1.4
	rim.omni_range = 9.0
	add_child(rim)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.near = 0.1
	add_child(camera)
	camera.position = _focus + Vector3(-5.0, 2.2, 5.0)
	camera.look_at(_focus + Vector3(0, 0.9, 0), Vector3.UP)


func _build_map() -> void:
	var packed: PackedScene = load(MAP_PATH) as PackedScene
	if packed == null:
		return
	var map: Node3D = packed.instantiate() as Node3D
	map.name = "Dust2Showcase"
	add_child(map)


func _build_hero() -> void:
	hero = Node3D.new()
	hero.name = "Hero"
	hero.position = _focus + Vector3(0.0, -0.05, 0.0)
	add_child(hero)
	var packed: PackedScene = load(CHARACTER_PATH) as PackedScene
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		var s := 1.8 / 2.5
		model.scale = Vector3.ONE * s
		model.position = Vector3(0, 1.25 * s, 0)
		model.rotation_degrees = Vector3(0, -135, 0)
		hero.add_child(model)
	var rifle := CBWeaponModelFactory.build_rifle(Color.WHITE, true)
	rifle.position = Vector3(0.17, 1.02, -0.30)
	rifle.rotation_degrees = Vector3(-4, -8, 4)
	hero.add_child(rifle)


func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 6.0
	p.preprocess = 3.0
	p.position = _focus + Vector3(0, 1.2, 0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.9, 0.7, 0.5)
	mesh.material = mat
	p.draw_pass_1 = mesh
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(4, 2, 4)
	proc.direction = Vector3(0.3, 1, 0)
	proc.spread = 60.0
	proc.initial_velocity_min = 0.05
	proc.initial_velocity_max = 0.25
	proc.gravity = Vector3(0.02, 0.01, 0)
	proc.scale_min = 0.4
	proc.scale_max = 1.4
	p.process_material = proc
	add_child(p)


func _process(delta: float) -> void:
	_t += delta
	if camera == null:
		return
	var ang := _t * 0.12
	var pos := _focus + Vector3(sin(ang) * _orbit_radius, 1.9 + sin(_t * 0.5) * 0.25, cos(ang) * _orbit_radius)
	camera.position = camera.position.lerp(pos, minf(1.0, delta * 1.5))
	camera.look_at(_focus + Vector3(0, 1.05, 0), Vector3.UP)
	if hero != null:
		hero.rotation.y = sin(_t * 0.35) * 0.35
