## CALLOFBRAWL — character visuals and procedural animation.
##
## IMPORTANT ASSET FACT: army_character_1.glb has **no skeleton and no animations**
## (7 rigid meshes grouped by material, exported from an OBJ). Instead of faking a
## rig, motion is produced procedurally from the model root:
##   * idle  : breathing bob + subtle sway
##   * walk  : vertical bob + step-synced roll (speed-scaled)
##   * run   : faster, larger bob with forward lean
##   * shoot : short recoil kick on the weapon arm/rifle plus muzzle flash
##   * death : falls backwards with a soft-body settle
##   * jump  : tuck/lean
## The provided AK-47 is attached at a measured grip anchor and is animated by the
## same controller, which reads as "aiming/shooting" from every angle.
class_name CBCharacterVisual
extends Node3D

const MODEL_PATH := "res://army_character_1.glb"
const MODEL_HEIGHT := 2.5            # measured world-space height of the GLB
const TARGET_HEIGHT := 1.8           # human scale used for gameplay
const MODEL_Y_MIN := -1.25           # measured world-space min Y of the GLB

## Bone-less anchors measured from the mesh (army_character_1.glb, metres, local).
##
## The export is 2.5 m tall on Y and faces **-X**: the sunglasses (the only narrow-band
## mesh) sit at the extreme -X end of the head (x -0.226..-0.172 inside a head that
## spans -0.229..0.062), and the shoulder line runs along Z. A -90 deg yaw maps -X to
## -Z, which both puts the face on Godot's forward axis and turns the 1.29 m Z span
## into a correct 0.94 m shoulder width. Verified numerically in docs/ASSET_NOTES.md.
const MODEL_YAW_DEGREES := -90.0
## Rifle grip in this node's space: in front of the chest (body front is z = -0.31).
const GRIP_ANCHOR := Vector3(0.13, 1.05, -0.34)
## Head/eye centre after the same transform (model head centre: -0.08, 0.975, -0.05).
const HEAD_ANCHOR := Vector3(0.04, 1.60, -0.06)

static var _packed_cache: PackedScene
static var _enemy_material: StandardMaterial3D
static var _friendly_material: StandardMaterial3D

var model_root: Node3D
var weapon_pivot: Node3D
var weapon_model: Node3D
var flash_rig: Node3D
var muzzle_marker: Node3D

var team: int = CBTeam.NONE
var is_local_player: bool = false

var _t: float = 0.0
var _walk_phase: float = 0.0
var _bob: float = 0.0
var _recoil: float = 0.0
var _lean: float = 0.0
var _dead: bool = false
var _death_time: float = 0.0
var _base_model_position: Vector3 = Vector3.ZERO
var _speed_ratio: float = 0.0


static func character_scene() -> PackedScene:
	if _packed_cache == null:
		_packed_cache = load(MODEL_PATH) as PackedScene
	return _packed_cache


func build(for_team: int, local_player: bool, with_rifle: bool = true) -> void:
	team = for_team
	is_local_player = local_player
	name = "CharacterVisual"
	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	add_child(model_root)
	var packed := character_scene()
	if packed == null:
		push_error("CBCharacterVisual: could not load %s" % MODEL_PATH)
		return
	var model: Node3D = packed.instantiate() as Node3D
	model.name = "Army"
	var s = TARGET_HEIGHT / MODEL_HEIGHT
	model.scale = Vector3.ONE * s
	# Drop the model so its feet rest exactly on this node's origin, then turn it so it
	# faces -Z (the direction a Node3D's "forward" points in this project).
	model.position = Vector3(0.0, -MODEL_Y_MIN * s, 0.0)
	model.rotation_degrees = Vector3(0, MODEL_YAW_DEGREES, 0)
	model_root.add_child(model)
	_base_model_position = model_root.position
	_apply_team_materials(model)
	if with_rifle:
		_build_weapon_rig()


# ---------------------------------------------------------------- materials
func _apply_team_materials(model: Node3D) -> void:
	var mat := _team_material(team)
	if mat == null:
		return
	# The GLB's material slots are: AF_01_D + AF_01_etc_D (uniform / kit), AF_Helmet_01_D,
	# AF_Mark_01_D (badge), Head_101_D (head), SunGla_Atype_D + SunGla_l (glasses).
	# Tint the uniform and helmet slots so teams are readable at a distance, and leave
	# the head, badge and sunglasses exactly as authored.
	var tint_tags := ["af_01", "helmet"]
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var source = mi.get_active_material(0)
		if source is StandardMaterial3D:
			var src := source as StandardMaterial3D
			var mat_name = src.resource_name.to_lower()
			var apply: bool = false
			for tag in tint_tags:
				if mat_name.contains(tag):
					apply = true
					break
			if apply:
				mi.material_override = mat
		elif source == null:
			mi.material_override = mat


static func _team_material(for_team: int) -> StandardMaterial3D:
	if for_team == CBTeam.ALPHA:
		if _friendly_material == null:
			_friendly_material = _make_uniform_material(Color(0.32, 0.52, 0.34))
		return _friendly_material
	if _enemy_material == null:
		_enemy_material = _make_uniform_material(Color(0.62, 0.48, 0.34))
	return _enemy_material


static func _make_uniform_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.metallic = 0.0
	m.resource_name = "team_uniform"
	return m


## Team indicator: a small floating chevron above friendly bots is drawn by the HUD
## (2D overlay) — no extra 3D draw calls here.


# ---------------------------------------------------------------- weapon rig
func _build_weapon_rig() -> void:
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = GRIP_ANCHOR
	model_root.add_child(weapon_pivot)
	weapon_model = CBWeaponModelFactory.build_world_rifle()
	# The character rig draws its rifle slightly smaller so it reads correctly
	# against the 1.8 m body.
	weapon_model.scale = Vector3.ONE * 0.95
	weapon_model.position = Vector3(0.0, 0.0, 0.0)
	weapon_model.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	weapon_pivot.add_child(weapon_model)
	flash_rig = Fx.make_muzzle_flash()
	flash_rig.position = CBWeaponModelFactory.MUZZLE_LOCAL
	weapon_model.add_child(flash_rig)
	muzzle_marker = Node3D.new()
	muzzle_marker.name = "Muzzle"
	muzzle_marker.position = CBWeaponModelFactory.MUZZLE_LOCAL
	weapon_model.add_child(muzzle_marker)


# ---------------------------------------------------------------- state driven by owner
## `move_speed` in m/s, `moving` tells us whether to advance the step cycle.
func animate(delta: float, move_speed: float, on_floor: bool, vertical_speed: float) -> void:
	_t += delta
	if _dead:
		_update_death(delta)
		return
	_speed_ratio = clampf(move_speed / 5.6, 0.0, 1.6)
	var running := _speed_ratio > 0.75
	var stride := 7.0 if not running else 11.0
	if move_speed > 0.15:
		_walk_phase += delta * stride * clampf(_speed_ratio, 0.35, 1.6)
	else:
		_walk_phase = lerpf(_walk_phase, 0.0, minf(1.0, delta * 6.0))
	# breathing when still
	var breathe = sin(_t * 1.8) * 0.012 if move_speed < 0.15 else 0.0
	# vertical bob follows the step cycle
	var bob_amp = 0.035 * clampf(_speed_ratio, 0.4, 1.4) if on_floor else 0.0
	_bob = lerpf(_bob, -absf(sin(_walk_phase)) * bob_amp + breathe, minf(1.0, delta * 12.0))
	model_root.position = _base_model_position + Vector3(0.0, _bob, 0.0)
	# body roll while stepping
	var roll = sin(_walk_phase) * deg_to_rad(3.0) * clampf(_speed_ratio, 0.0, 1.0)
	# forward lean while running, plus a jump tuck
	var lean_target = deg_to_rad(-8.0) * clampf(_speed_ratio - 0.5, 0.0, 1.0) if on_floor else deg_to_rad(4.0)
	_lean = lerpf(_lean, lean_target, minf(1.0, delta * 5.0))
	model_root.rotation = Vector3(_lean, 0.0, roll + sin(_t * 1.1) * deg_to_rad(0.6))
	if weapon_pivot != null:
		_recoil = move_toward(_recoil, 0.0, delta * 9.0)
		weapon_pivot.position = GRIP_ANCHOR + Vector3(0.0, 0.0, _recoil * 0.06)
		weapon_pivot.rotation = Vector3(_recoil * 0.5, 0.0, 0.0)


## Visual kick when this character fires.
func play_shoot_kick() -> void:
	_recoil = clampf(_recoil + 0.6, 0.0, 1.2)
	if flash_rig != null:
		Fx.fire_muzzle_flash(flash_rig)


func play_death() -> void:
	_dead = true
	_death_time = 0.0


func revive() -> void:
	_dead = false
	_death_time = 0.0
	model_root.rotation = Vector3.ZERO
	model_root.position = _base_model_position
	visible = true


func _update_death(delta: float) -> void:
	_death_time += delta
	var t := clampf(_death_time / 0.55, 0.0, 1.0)
	var ease = 1.0 - pow(1.0 - t, 3.0)
	model_root.rotation.x = deg_to_rad(-82.0) * ease
	model_root.position = _base_model_position + Vector3(0.0, -0.65 * ease, -0.25 * ease)
	if _death_time > 2.6:
		visible = false


func is_dead_visual() -> bool:
	return _dead


func muzzle_position() -> Vector3:
	if muzzle_marker != null:
		return muzzle_marker.global_position
	return global_position + Vector3(0, 1.3, 0)


func head_position() -> Vector3:
	return to_global(HEAD_ANCHOR)


## Rotate smoothly to look at a world position (keeps the body upright).
func face_towards(world_point: Vector3, delta: float = 0.1, speed: float = 7.0) -> void:
	var flat := world_point - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	# The GLB faces +Z and is rotated 180 degrees at build time, so this node's forward
	# is -Z, matching Node3D's convention: yaw = atan2(-x, -z).
	var target_yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * speed, 0.0, 1.0))


## Rotate towards a direction vector.
func face_direction(dir: Vector3, delta: float = 0.1, speed: float = 6.0) -> void:
	if dir.length_squared() < 0.0001:
		return
	face_towards(global_position + dir, delta, speed)


## Point the whole character (and therefore its rifle) at a world position.
func aim_at(world_point: Vector3) -> void:
	var flat := world_point - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.001:
		return
	var yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, yaw, 0.35)
