## CALLOFBRAWL — local player.
##
## Movement (CharacterBody3D), first-person camera with recoil/landing effects,
## health, ammunition and respawn. Input arrives from CBVirtualInput (touch) and
## from the keyboard/mouse fallback, so the same class plays on desktop for
## debugging and on a phone.
class_name CBPlayerController
extends CharacterBody3D

const WALK_SPEED := 4.6
const SPRINT_SPEED := 6.4
const ADS_SPEED := 2.7
const ACCELERATION := 22.0
const AIR_ACCELERATION := 6.0
const FRICTION := 16.0
const JUMP_VELOCITY := 6.2

@export var eye_height: float = 1.62

var combatant_id: String = "player"
var display_name: String = "Player"
var team: int = CBTeam.ALPHA
var kills: int = 0
var deaths: int = 0
var is_alive: bool = true
var can_control: bool = false

var health_component: CBHealthComponent
var weapon: CBWeaponController
var visual: CBCharacterVisual
var camera: Camera3D
var camera_pivot: Node3D
var input_controller: Node

var _yaw: float = 0.0
var _pitch: float = 0.0
var _bob_time: float = 0.0
var _land_kick: float = 0.0
var _footstep_accum: float = 0.0
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0
var _spawn_position: Vector3 = Vector3.ZERO

signal died(attacker_id: String, headshot: bool)
signal respawned
signal ammo_updated(mag: int, reserve: int)
signal ads_changed(active: bool)
signal damaged(amount: float, attacker_id: String, headshot: bool)


func _ready() -> void:
	collision_layer = CBMapLoader.LAYER_COMBATANT
	collision_mask = CBMapLoader.LAYER_WORLD | CBMapLoader.LAYER_COMBATANT
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	floor_stop_on_slope = true
	floor_constant_speed = true
	slide_on_ceiling = true
	add_to_group(Game.GROUP_COMBATANT)
	_build_nodes()


func _build_nodes() -> void:
	# --- collision (capsule, with head sphere used for headshots)
	var shape := CollisionShape3D.new()
	shape.name = "Body"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0, 0.90, 0)
	add_child(shape)

	_register_hitbox("Head", Game.GROUP_HEAD, Vector3(0, 1.64, 0), 0.145)
	_register_hitbox("Torso", Game.GROUP_BODY, Vector3(0, 1.18, 0), 0.29)
	_register_hitbox("Legs", Game.GROUP_BODY, Vector3(0, 0.52, 0), 0.26)

	# --- health
	health_component = CBHealthComponent.new()
	health_component.name = "Health"
	add_child(health_component)
	health_component.setup(combatant_id, team, self)
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)

	# --- camera
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0, eye_height, 0)
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 260.0
	camera.current = true
	camera_pivot.add_child(camera)

	# --- weapon
	weapon = CBWeaponController.new()
	weapon.name = "Weapon"
	weapon.data = load("res://resources/weapons/ak47.tres") as CBWeaponData
	weapon.camera = camera
	weapon.holder = self
	add_child(weapon)
	weapon.setup(combatant_id, team, true)
	weapon.ammo_changed.connect(_on_ammo_changed)
	weapon.fired.connect(_on_weapon_fired)

	var rifle := CBWeaponModelFactory.build_rifle()
	rifle.name = "Viewmodel"
	# First-person viewmodel placement (metres, camera-local): right hand, slightly
	# below the eye line, barrel pointing down -Z. The rifle is ~1 m long, so 0.30 m
	# forward keeps the stock out of the near plane.
	rifle.position = Vector3(0.155, -0.145, -0.32)
	camera.add_child(rifle)
	weapon.rifle_model = rifle
	if rifle.has_node("MuzzleFlash"):
		weapon.flash_rig = rifle.get_node("MuzzleFlash")
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = CBWeaponModelFactory.MUZZLE_LOCAL
	rifle.add_child(muzzle)
	weapon.muzzle = muzzle

	# --- third person body (seen by others / on death cam); hidden in first person
	visual = CBCharacterVisual.new()
	visual.name = "Body"
	visual.visible = false
	add_child(visual)
	visual.build(team, true, true)


func _register_hitbox(node_name: String, group: String, offset: Vector3, radius: float) -> void:
	var area := Area3D.new()
	area.name = node_name
	area.collision_layer = CBMapLoader.LAYER_COMBATANT
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	cs.shape = sphere
	cs.position = offset
	area.add_child(cs)
	area.add_to_group(Game.GROUP_HITBOX)
	area.add_to_group(group)
	add_child(area)


# ---------------------------------------------------------------- setup / respawn
func configure(id: String, player_name: String, player_team: int) -> void:
	combatant_id = id
	display_name = player_name
	team = player_team
	health_component.setup(id, team, self)


func teleport_to(pos: Vector3) -> void:
	_spawn_position = pos
	global_position = pos
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func on_spawn(pos: Vector3, yaw: float = 0.0) -> void:
	teleport_to(pos)
	for area_name in ["Head", "Torso", "Legs"]:
		var area := get_node_or_null(area_name) as Area3D
		if area != null:
			area.set_deferred("monitorable", true)
	var body_shape := get_node_or_null("Body") as CollisionShape3D
	if body_shape != null:
		body_shape.set_deferred("disabled", false)
	is_alive = true
	can_control = true
	_yaw = yaw
	_pitch = 0.0
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	health_component.reset()
	weapon.reset_loadout()
	visual.visible = false
	visual.revive()
	camera_pivot.position = Vector3(0, eye_height, 0)
	_update_camera_rotation(1.0)
	ammo_updated.emit(weapon.magazine, weapon.reserve)
	respawned.emit()


func on_death(attacker_id: String, headshot: bool) -> void:
	is_alive = false
	can_control = false
	set_trigger(false)
	set_aiming(false)
	# Stop blocking the living with the corpse, and show the body for the death cam.
	for area_name in ["Head", "Torso", "Legs"]:
		var area := get_node_or_null(area_name) as Area3D
		if area != null:
			area.set_deferred("monitorable", false)
	var body_shape := get_node_or_null("Body") as CollisionShape3D
	if body_shape != null:
		body_shape.set_deferred("disabled", true)
	visual.visible = true
	visual.play_death()
	_death_cam_time = 0.0
	died.emit(attacker_id, headshot)


## Death camera: pulls up and back over the body for the respawn wait.
var _death_cam_time: float = 0.0


# ---------------------------------------------------------------- input API
## `delta_pitch_degrees` follows the screen convention used by every caller (touch
## drag, mouse motion, aim assist): a positive value means "drag down", which looks
## down. Camera pitch is positive = up, hence the subtraction.
## Extra multiplier applied to every look input (aim assist slow-down while tracking).
var look_scale: float = 1.0


## Multiplier for the current aim state: full speed when hip firing, the configured
## fraction while aiming down sights.
func sight_scale() -> float:
	var ads_mult := clampf(Settings.get_float("ads_sensitivity_mult"), 0.1, 2.0)
	var aiming := weapon != null and weapon.aiming
	return ads_mult if aiming else 1.0


func add_look(delta_yaw_degrees: float, delta_pitch_degrees: float) -> void:
	if not is_alive:
		return
	var mult := sight_scale() * look_scale
	_yaw -= deg_to_rad(delta_yaw_degrees * mult)
	_pitch = clampf(_pitch - deg_to_rad(delta_pitch_degrees * mult), deg_to_rad(-85.0), deg_to_rad(85.0))


func set_look_degrees(yaw_deg: float, pitch_deg: float) -> void:
	_yaw = deg_to_rad(yaw_deg)
	_pitch = clampf(deg_to_rad(pitch_deg), deg_to_rad(-85.0), deg_to_rad(85.0))


func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


func set_move_input(dir: Vector2) -> void:
	_move_input_touch = dir


## Direction in [-1,1]^2 on the XZ plane as requested by whichever device is active.
var _move_input_touch: Vector2 = Vector2.ZERO
var _move_input: Vector2 = Vector2.ZERO
## Desktop keyboard state (WASD / arrows / Shift sprint). Touch input is unaffected.
var _keyboard_active: bool = false


func set_trigger(held: bool) -> void:
	if weapon:
		weapon.set_trigger(held and is_alive and can_control)


func set_aiming(value: bool) -> void:
	if weapon and weapon.aiming != value:
		weapon.set_aiming(value)
		ads_changed.emit(value)


func set_sprinting(value: bool) -> void:
	_sprinting = value and not (weapon != null and weapon.aiming)


var _sprinting: bool = false


func request_reload() -> void:
	if weapon and is_alive:
		weapon.request_reload()


func request_jump() -> void:
	if is_alive and is_on_floor() and can_control:
		velocity.y = JUMP_VELOCITY
		Audio.play_ui("jump", -12.0)


# ---------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	if not is_alive:
		_update_death_camera(delta)
		return
	_poll_keyboard()
	# gravity
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	# desired direction in world space
	var input_dir := _move_input
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var basis_yaw := Basis(Vector3.UP, _yaw)
	var wish := basis_yaw * Vector3(input_dir.x, 0.0, input_dir.y)
	var speed := WALK_SPEED
	if weapon != null and weapon.aiming:
		speed = ADS_SPEED
	elif _sprinting and input_dir.y < -0.35:
		speed = SPRINT_SPEED
	if not can_control:
		wish = Vector3.ZERO
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	if wish.length_squared() > 0.0001:
		horizontal = horizontal.move_toward(wish * speed, accel * delta * speed)
	else:
		if is_on_floor():
			horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta * 2.0)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var was_on_floor := is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()

	if not was_on_floor and is_on_floor():
		if fall_speed < -4.0:
			_land_kick = clampf(absf(fall_speed) * 0.012, 0.0, 0.09)
			Audio.play_ui("land", -12.0)

	_update_footsteps(delta, horizontal.length())
	_update_camera_rotation(delta)
	_update_weapon_presentation(delta)


func _update_death_camera(delta: float) -> void:
	# Rise above and behind the body so the player can watch the fight continue.
	_death_cam_time += delta
	var t := clampf(_death_cam_time / 1.1, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - t, 2.0)
	camera_pivot.position = Vector3(0.0, eye_height + 2.4 * ease, 3.4 * ease)
	camera_pivot.rotation = Vector3(deg_to_rad(-26.0) * ease, 0.0, 0.0)


func _update_footsteps(delta: float, speed: float) -> void:
	if speed > 1.2 and is_on_floor():
		_footstep_accum += delta * speed * 1.35
		if _footstep_accum > 1.6:
			_footstep_accum = 0.0
			if display_name != "":
				Audio.play_3d("footstep", global_position, -14.0, 0.25, 18.0)
	else:
		_footstep_accum = 0.0


func _update_camera_rotation(delta: float) -> void:
	if camera_pivot == null:
		return
	# recoil is applied as a temporary offset that decays
	if weapon != null:
		var target := weapon.recoil_offset()
		_recoil_pitch = lerpf(_recoil_pitch, target.x, minf(1.0, delta * 14.0))
		_recoil_yaw = lerpf(_recoil_yaw, target.y, minf(1.0, delta * 14.0))
	# walking head bob
	var speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and speed > 0.5:
		_bob_time += delta * speed * 1.9
	else:
		_bob_time = lerpf(_bob_time, 0.0, minf(1.0, delta * 5.0))
	var bob_amp := 0.012 * clampf(speed / WALK_SPEED, 0.0, 1.3)
	_land_kick = move_toward(_land_kick, 0.0, delta * 0.45)
	var bob_y := sin(_bob_time) * bob_amp
	rotation = Vector3(0.0, _yaw, 0.0)
	camera_pivot.rotation = Vector3(_pitch + _recoil_pitch + _land_kick, _recoil_yaw, sin(_bob_time * 0.5) * bob_amp * 1.6)
	camera_pivot.position = Vector3(0, eye_height + bob_y, 0)


func _update_weapon_presentation(delta: float) -> void:
	if weapon == null:
		return
	var rifle := weapon.rifle_model
	if rifle == null:
		return
	var ads := weapon.aiming
	var target_pos := Vector3(0.16, -0.14, -0.30)
	var target_rot := Vector3(0.0, 0.0, 0.0)
	if ads:
		# align the scope with the screen centre using the model's measured scope offset
		target_pos = Vector3(0.0, -0.054, -0.16)
	# recoil kick: the viewmodel is pushed back and rolled while firing, then recovers
	_viewmodel_kick = move_toward(_viewmodel_kick, 0.0, delta * 7.0)
	_viewmodel_kick_side = move_toward(_viewmodel_kick_side, 0.0, delta * 5.0)
	target_pos += Vector3(_viewmodel_kick_side * 0.05, 0.0, _viewmodel_kick * 0.07)
	target_rot += Vector3(-_viewmodel_kick * 9.0, 0.0, _viewmodel_kick_side * 6.0)
	# slow sway while walking so the gun is not glued to the screen
	var speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and speed > 0.5:
		target_pos += Vector3(sin(_bob_time * 0.5) * 0.008, cos(_bob_time) * 0.006, 0.0)
	var t := minf(1.0, delta * 11.0)
	rifle.position = rifle.position.lerp(target_pos, t)
	rifle.rotation = rifle.rotation.lerp(target_rot, t)
	if camera != null:
		var target_fov := 55.0 if ads else 78.0
		camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 10.0))


# ---------------------------------------------------------------- weapon events
## Called by the weapon for every round actually fired by the player.
## Drives the viewmodel kick (position + roll) and a tiny landing-style camera nudge,
## so the gun feels like it is pushing back between shots.
func _on_weapon_fired(recoil: Vector2) -> void:
	_viewmodel_kick = clampf(_viewmodel_kick + absf(recoil.y) * 6.0, 0.0, 1.0)
	_viewmodel_kick_side = clampf(_viewmodel_kick_side + recoil.x * 4.0, -0.4, 0.4)
	_land_kick = minf(_land_kick + 0.004, 0.03)


var _viewmodel_kick: float = 0.0
var _viewmodel_kick_side: float = 0.0


func _on_ammo_changed(mag: int, reserve: int) -> void:
	ammo_updated.emit(mag, reserve)


func _on_damaged(amount: float, attacker_id: String, headshot: bool, _remaining: float) -> void:
	damaged.emit(amount, attacker_id, headshot)


func _on_died(attacker_id: String, headshot: bool) -> void:
	deaths += 1
	on_death(attacker_id, headshot)


# ---------------------------------------------------------------- desktop keyboard
## Polled every physics tick so desktop builds get real WASD/arrow movement and
## Shift-to-sprint. On mobile no key is ever down, so this costs two array reads.
func _poll_keyboard() -> void:
	if not can_control:
		return
	var x := 0.0
	var y := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		y += 1.0
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT)
	if x != 0.0 or y != 0.0:
		_keyboard_active = true
		_move_input = Vector2(x, y).normalized()
		set_sprinting(sprint and y < 0.0)
	elif _keyboard_active:
		# keys released: hand control back to the touch stick
		_keyboard_active = false
		_move_input = _move_input_touch
		set_sprinting(false)
	elif not _keyboard_active:
		_move_input = _move_input_touch


# ---------------------------------------------------------------- debug / desktop
func _unhandled_input(event: InputEvent) -> void:
	if not can_control or not is_alive:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_R:
				request_reload()
			KEY_SPACE:
				request_jump()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			set_trigger(mb.pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			set_aiming(mb.pressed)
	elif event is InputEventMouseMotion:
		# desktop look speed follows the same setting as touch (0.22 -> 1.0 range)
		var sens := Settings.get_float("look_sensitivity") * 0.35
		add_look((event as InputEventMouseMotion).relative.x * sens,
				(event as InputEventMouseMotion).relative.y * sens)
