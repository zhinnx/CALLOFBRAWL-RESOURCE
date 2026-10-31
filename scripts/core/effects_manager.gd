## CALLOFBRAWL — effects manager (autoload).
##
## Owns pooled, short-lived combat visual effects so gameplay code never allocates
## nodes during a firefight:
##   * bullet impact decals (pooled quads, radial gradient texture)
##   * impact spark bursts (pooled GPUParticles3D, one-shot)
##   * blood/flesh puffs (pooled GPUParticles3D)
##   * tracers (pooled stretched quads)
##   * muzzle flash (a shared Sprite3D the weapon controller parents to itself)
##
## Everything is generated procedurally, so the repository ships no image assets.
extends Node

const DECAL_POOL := 40
const SPARK_POOL := 10
const BLOOD_POOL := 6
const TRACER_POOL := 16

var _decal_pool: Array[MeshInstance3D] = []
var _decal_index: int = 0
var _spark_pool: Array[GPUParticles3D] = []
var _spark_index: int = 0
var _blood_pool: Array[GPUParticles3D] = []
var _blood_index: int = 0
var _tracer_pool: Array[MeshInstance3D] = []
var _tracer_expiry: Array[float] = []
var _tracer_index: int = 0
var _now: float = 0.0

var _decal_mesh: QuadMesh
var _decal_material: StandardMaterial3D
var _spark_mesh: QuadMesh
var _blood_mesh: QuadMesh
var _tracer_mesh: BoxMesh
var _tracer_material: StandardMaterial3D

var _spark_materials: Array[ParticleProcessMaterial] = []
var _blood_materials: Array[ParticleProcessMaterial] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_textures()
	_build_decals()
	_build_particles()
	_build_tracers()


func _process(delta: float) -> void:
	_now += delta
	for i in _tracer_pool.size():
		if _tracer_pool[i].visible and _tracer_expiry[i] <= _now:
			_tracer_pool[i].visible = false


# ---------------------------------------------------------------- resources
func _build_textures() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 64:
			var dx: float = (x - 31.5) / 31.5
			var dy: float = (y - 31.5) / 31.5
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.9
			var hole: float = clampf(d * 1.6 - 0.35, 0.0, 1.0)
			var c := Color(0.08, 0.07, 0.06, a * (0.35 + 0.55 * hole))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)

	_decal_material = StandardMaterial3D.new()
	_decal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_decal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_decal_material.albedo_texture = tex
	_decal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_decal_material.no_depth_test = false
	_decal_material.disable_receive_shadows = true

	var soft := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	soft.fill(Color(0, 0, 0, 0))
	for y in 32:
		for x in 32:
			var dx: float = (x - 15.5) / 15.5
			var dy: float = (y - 15.5) / 15.5
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			soft.set_pixel(x, y, Color(1, 1, 1, a * a))
	var soft_tex := ImageTexture.create_from_image(soft)


	_decal_mesh = QuadMesh.new()
	_decal_mesh.size = Vector2(0.16, 0.16)
	_decal_mesh.material = _decal_material

	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.035, 0.035)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_mat.albedo_texture = soft_tex
	spark_mat.albedo_color = Color(1.0, 0.78, 0.38)
	spark_mat.disable_receive_shadows = true
	_spark_mesh.material = spark_mat

	_blood_mesh = QuadMesh.new()
	_blood_mesh.size = Vector2(0.06, 0.06)
	var blood_mat := StandardMaterial3D.new()
	blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blood_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	blood_mat.albedo_texture = soft_tex
	blood_mat.albedo_color = Color(0.55, 0.05, 0.04)
	blood_mat.disable_receive_shadows = true
	_blood_mesh.material = blood_mat

	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3(0.012, 0.012, 1.0)
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_material.albedo_color = Color(1.0, 0.85, 0.45, 0.9)
	_tracer_material.disable_receive_shadows = true
	_tracer_mesh.material = _tracer_material


func _build_decals() -> void:
	var holder := Node3D.new()
	holder.name = "Decals"
	add_child(holder)
	for i in DECAL_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = _decal_mesh
		mi.visible = false
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		_decal_pool.append(mi)


func _build_particles() -> void:
	for i in SPARK_POOL:
		var p := _make_particles(_spark_mesh, 14, 0.35, Color(1.0, 0.72, 0.3), 5.5, 1.0)
		add_child(p)
		_spark_pool.append(p)
	for i in BLOOD_POOL:
		var p := _make_particles(_blood_mesh, 10, 0.45, Color(0.6, 0.05, 0.04), 2.6, 1.6)
		add_child(p)
		_blood_pool.append(p)


func _make_particles(mesh: QuadMesh, amount: int, lifetime: float, color: Color,
		speed: float, gravity_scale: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.local_coords = false
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.05
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 75.0
	mat.initial_velocity_min = speed * 0.4
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, -9.8 * gravity_scale, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.color = color
	p.process_material = mat
	return p


func _build_tracers() -> void:
	_tracer_expiry.clear()
	var holder := Node3D.new()
	holder.name = "Tracers"
	add_child(holder)
	for i in TRACER_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = _tracer_mesh
		mi.visible = false
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		_tracer_pool.append(mi)
		_tracer_expiry.append(0.0)


# ---------------------------------------------------------------- spawn API
## Small dark hole decal aligned with the impact normal.
func spawn_impact(point: Vector3, normal: Vector3, scale: float = 1.0) -> void:
	var mi := _decal_pool[_decal_index]
	_decal_index = (_decal_index + 1) % _decal_pool.size()
	mi.visible = true
	mi.scale = Vector3.ONE * scale
	var up := normal.normalized()
	if absf(up.dot(Vector3.UP)) > 0.98:
		up = Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(-normal.normalized(), up), point + normal.normalized() * 0.012)


func spawn_spark_burst(point: Vector3, normal: Vector3) -> void:
	var p := _spark_pool[_spark_index]
	_spark_index = (_spark_index + 1) % _spark_pool.size()
	p.global_position = point + normal.normalized() * 0.05
	p.restart()
	p.emitting = true


func spawn_blood(point: Vector3, normal: Vector3) -> void:
	var p := _blood_pool[_blood_index]
	_blood_index = (_blood_index + 1) % _blood_pool.size()
	p.global_position = point + normal.normalized() * 0.05
	p.restart()
	p.emitting = true


## Brief tracer beam. `duration` keeps it subtle (0.045 s reads well at 60 fps).
func spawn_tracer(from: Vector3, to: Vector3, duration: float = 0.05) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.2:
		return
	var slot := _tracer_index
	var mi := _tracer_pool[slot]
	_tracer_index = (_tracer_index + 1) % _tracer_pool.size()
	var mid := (from + to) * 0.5
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.97 else Vector3.RIGHT)
	mi.global_transform = Transform3D(basis.scaled(Vector3(1, 1, length)), mid)
	mi.visible = true
	# Time-based expiry instead of a Tween: at 600 RPM with nine bots the tween churn
	# alone was measurable on a phone, and this costs one float per tracer.
	_tracer_expiry[slot] = _now + duration


## Builds a reusable muzzle-flash rig to be parented to a weapon muzzle.
func make_muzzle_flash() -> Node3D:
	var root := Node3D.new()
	root.name = "MuzzleFlash"

	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.82, 0.45)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 32:
		for x in 32:
			var dx: float = (x - 15.5) / 15.5
			var dy: float = (y - 15.5) / 15.5
			var d: float = sqrt(dx * dx + dy * dy)
			var spike: float = clampf(1.0 - absf(dx) * 6.0 - absf(dy), 0.0, 1.0) + clampf(1.0 - absf(dy) * 6.0 - absf(dx), 0.0, 1.0)
			var a: float = clampf(1.0 - d * 1.6, 0.0, 1.0) + spike * 0.6
			img.set_pixel(x, y, Color(1.0, 0.9, 0.6, clampf(a, 0.0, 1.0)))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	quad.material = mat
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flash)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.45)
	light.light_energy = 0.0
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.light_specular = 0.0
	root.add_child(light)

	root.set_meta("flash_mesh", flash)
	root.set_meta("flash_light", light)
	flash.visible = false
	return root


## Trigger the flash on a rig returned by make_muzzle_flash().
func fire_muzzle_flash(rig: Node3D) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var flash: MeshInstance3D = rig.get_meta("flash_mesh", null)
	var light: OmniLight3D = rig.get_meta("flash_light", null)
	if flash:
		flash.visible = true
		flash.rotation.z = randf() * TAU
		flash.scale = Vector3.ONE * randf_range(0.75, 1.15)
	if light and Settings.get_int("graphics_quality") > 0:
		light.light_energy = 2.2
	# A muzzle flash lives for ~45 ms; reuse a single tween stored on the rig instead of
	# allocating one per shot (600 RPM x 10 combatants would otherwise churn the heap).
	var tw: Tween = rig.get_meta("flash_tween", null)
	if tw != null and tw.is_valid():
		tw.kill()
	tw = rig.create_tween()
	rig.set_meta("flash_tween", tw)
	tw.tween_interval(0.045)
	tw.tween_callback(func() -> void:
		if is_instance_valid(flash):
			flash.visible = false
		if is_instance_valid(light):
			light.light_energy = 0.0)
