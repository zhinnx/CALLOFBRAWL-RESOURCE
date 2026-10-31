## CALLOFBRAWL — weapon controller.
##
## One controller drives both the local player's AK-47 and every bot rifle:
##   * hitscan raycasts through the camera (player) or the muzzle (bot)
##   * damage falloff over the effective/max range
##   * headshot / body / limb multipliers via hitbox groups
##   * recoil, spread, ADS, reload sequencing, ammo accounting
##   * muzzle flash, tracer, impact decals/sparks, positional gunfire audio
##   * friendly-fire rejection through the victim's HealthComponent
##
## Stats come from a CBWeaponData resource so nothing is hard-coded.
class_name CBWeaponController
extends Node

signal ammo_changed(mag: int, reserve: int)
signal reload_started(duration: float)
signal reload_finished
signal fired(recoil: Vector2)
signal hit_confirmed(victim_name: String, headshot: bool, killed: bool)
signal state_changed(state: int)

enum State { IDLE, FIRING, RELOADING, EQUIPPING }

## Bit values matching CBMapLoader: 1 = world geometry, 2 = combatants/hitboxes.
const LAYER_WORLD := 1 << 0
const LAYER_COMBATANT := 1 << 1

@export var data: CBWeaponData

## Combatant identity, wired by the owner (player or bot).
var owner_id: String = ""
var owner_team: int = CBTeam.NONE
var is_player: bool = false

var state: int = State.IDLE
var magazine: int = 30
var reserve: int = 120
var aiming: bool = false
var trigger_held: bool = false
var auto_fire: bool = true

var _fire_cooldown: float = 0.0
var _reload_timer: float = 0.0
var _reload_duration: float = 0.0
var _equip_timer: float = 0.0
var _recoil_accum: Vector2 = Vector2.ZERO
var _shot_count: int = 0
var _reload_stage: int = 0

## Nodes assigned by the owner.
var camera: Camera3D
var muzzle: Node3D
var rifle_model: Node3D
var flash_rig: Node3D
var holder: Node3D

var _space_state: PhysicsDirectSpaceState3D


func _ready() -> void:
	set_process(true)
	if data == null:
		data = load("res://resources/weapons/ak47.tres") as CBWeaponData
	if data != null:
		magazine = data.magazine_size
		reserve = data.reserve_ammo


func setup(id: String, team: int, player: bool) -> void:
	owner_id = id
	owner_team = team
	is_player = player
	state = State.IDLE
	_equip_timer = data.equip_time if data else 0.3
	state = State.EQUIPPING
	ammo_changed.emit(magazine, reserve)


func reset_loadout() -> void:
	if data == null:
		return
	magazine = data.magazine_size
	reserve = data.reserve_ammo
	state = State.IDLE
	_reload_timer = 0.0
	trigger_held = false
	_recoil_accum = Vector2.ZERO
	ammo_changed.emit(magazine, reserve)


# ---------------------------------------------------------------- input entry points
## Called every frame by the owner with the current trigger state.
func set_trigger(held: bool) -> void:
	trigger_held = held


## One-shot trigger for bots (they call fire_once and respect the cooldown).
func fire_once() -> void:
	trigger_held = true
	_try_fire()
	trigger_held = false


func set_aiming(value: bool) -> void:
	aiming = value


func request_reload() -> void:
	if data == null or state == State.RELOADING:
		return
	if magazine >= data.magazine_size or reserve <= 0:
		return
	_reload_duration = data.reload_time + (data.reload_empty_extra if magazine == 0 else 0.0)
	_reload_timer = _reload_duration
	_reload_stage = 0
	state = State.RELOADING
	reload_started.emit(_reload_duration)
	state_changed.emit(state)
	var pos := _audio_position()
	Audio.play_3d("reload_out", pos, -4.0, 0.05, 30.0)


# ---------------------------------------------------------------- simulation
func _process(delta: float) -> void:
	if data == null:
		return
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if _equip_timer > 0.0:
		_equip_timer -= delta
		if _equip_timer <= 0.0 and state == State.EQUIPPING:
			state = State.IDLE
			state_changed.emit(state)
	if state == State.RELOADING:
		_update_reload(delta)
	elif trigger_held and state != State.EQUIPPING:
		if auto_fire:
			_try_fire()
	# recoil recovery
	if _recoil_accum != Vector2.ZERO:
		var rec := data.recoil_recovery * delta
		_recoil_accum.x = move_toward(_recoil_accum.x, 0.0, rec)
		_recoil_accum.y = move_toward(_recoil_accum.y, 0.0, rec)


func _update_reload(delta: float) -> void:
	_reload_timer -= delta
	var elapsed := _reload_duration - _reload_timer
	if _reload_stage == 0 and elapsed > _reload_duration * 0.55:
		_reload_stage = 1
		Audio.play_3d("reload_in", _audio_position(), -4.0, 0.05, 30.0)
	elif _reload_stage == 1 and elapsed > _reload_duration * 0.82:
		_reload_stage = 2
		Audio.play_3d("reload_bolt", _audio_position(), -6.0, 0.05, 30.0)
	if _reload_timer <= 0.0:
		var needed: int = data.magazine_size - magazine
		var take: int = mini(needed, reserve)
		magazine += take
		reserve -= take
		state = State.IDLE
		_reload_stage = 0
		ammo_changed.emit(magazine, reserve)
		reload_finished.emit()
		state_changed.emit(state)


func _try_fire() -> void:
	if state == State.RELOADING or state == State.EQUIPPING:
		return
	if _fire_cooldown > 0.0:
		return
	if magazine <= 0:
		if reserve > 0:
			request_reload()
		else:
			_fire_cooldown = 0.35
			if is_player:
				Audio.play_ui("empty", -6.0)
		return
	_fire_cooldown = data.fire_interval()
	magazine -= 1
	_shot_count += 1
	ammo_changed.emit(magazine, reserve)
	_do_shot()
	if magazine == 0 and reserve > 0:
		# automatic reload as soon as the mag is dry, like a mobile-friendly shooter
		request_reload()


## Removes one round from the magazine without firing (used by bot AI, which
## resolves its own hitscan so it can control hit probability).
func consume_round() -> bool:
	if magazine <= 0:
		request_reload()
		return false
	magazine -= 1
	ammo_changed.emit(magazine, reserve)
	_fire_cooldown = data.fire_interval() if data else 0.1
	if magazine == 0 and reserve > 0:
		request_reload()
	return true


func _do_shot() -> void:
	var origin: Vector3
	var direction: Vector3
	if camera != null and is_player:
		origin = camera.global_position
		direction = -camera.global_transform.basis.z
	else:
		# bots fire from the muzzle the model factory measured
		if muzzle != null:
			origin = muzzle.global_position
			direction = -muzzle.global_transform.basis.z
		else:
			origin = _holder_position()
			direction = -basis_from_holder().z
	# spread
	var spread_deg := current_spread()
	if spread_deg > 0.0:
		var yaw := deg_to_rad(randf_range(-spread_deg, spread_deg))
		var pitch := deg_to_rad(randf_range(-spread_deg, spread_deg))
		var basis := Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT)
		direction = (basis * Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))).normalized()

	# apply recoil (player only rotates the camera; bots keep aiming at the target)
	var recoil := Vector2.ZERO
	if is_player:
		# Camera pitch is positive = looking up (camera_pivot.rotation.x), so a positive
		# vertical value kicks the view upward the way an AK-47 climbs.
		recoil = Vector2(deg_to_rad(randf_range(-data.recoil_horizontal, data.recoil_horizontal)),
				deg_to_rad(data.recoil_vertical))
		_recoil_accum += recoil
		fired.emit(recoil)

	# muzzle presentation + audio
	if flash_rig != null:
		Fx.fire_muzzle_flash(flash_rig)
	var sound := data.muzzle_sound
	if is_player:
		Audio.play_ui(sound, -3.0, randf_range(0.96, 1.04))
	else:
		Audio.play_3d(sound, origin, -1.0, 0.08, 70.0)

	# hitscan
	var hit_point: Vector3 = origin + direction * data.max_range
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * data.max_range,
			LAYER_WORLD | LAYER_COMBATANT, [])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var space := _space()
	var result := space.intersect_ray(query) if space != null else {}
	var tracer_end: Vector3 = origin + direction * data.max_range
	if not result.is_empty():
		hit_point = result.get("position", hit_point)
		tracer_end = hit_point
		_handle_hit(result, origin)
	if is_player or owner_id.begins_with("bot"):
		Fx.spawn_tracer(muzzle_position(), tracer_end, 0.04)


func _handle_hit(result: Dictionary, origin: Vector3) -> void:
	var collider: Object = result.get("collider")
	var point: Vector3 = result.get("position", Vector3.ZERO)
	var normal: Vector3 = result.get("normal", Vector3.UP)
	if collider is Node:
		var node := collider as Node
		if node.is_in_group(Game.GROUP_HITBOX):
			var headshot := node.is_in_group(Game.GROUP_HEAD)
			var combatant := _find_combatant(node)
			if combatant != null:
				_apply_combatant_damage(combatant, point, normal, headshot, origin)
				return
	# world hit
	Fx.spawn_impact(point, normal, randf_range(0.8, 1.25))
	Fx.spawn_spark_burst(point, normal)
	Audio.play_3d("impact_concrete", point, -8.0, 0.12, 40.0)


func _find_combatant(hitbox: Node) -> Node:
	var cur: Node = hitbox
	while cur != null:
		if cur.is_in_group(Game.GROUP_COMBATANT):
			return cur
		cur = cur.get_parent()
	return null


func _apply_combatant_damage(combatant: Node, point: Vector3, normal: Vector3, headshot: bool, origin: Vector3) -> void:
	var health: CBHealthComponent = combatant.get("health_component") as CBHealthComponent
	if health == null:
		return
	var victim_team: int = health.team
	if CBTeam.is_friendly(owner_team, victim_team):
		# Friendly fire is disabled: show a "blocked" impact, no damage.
		Fx.spawn_impact(point, normal, 0.7)
		return
	var dist := origin.distance_to(point)
	# Nominal damage: 100 head, 25 torso, 18 limb. Beyond `effective_range` (45 m) the
	# value scales down to `range_falloff` (55 %) at `max_range`, so a cross-map body
	# shot deals ~14 while a close-range headshot always kills.
	var base := data.damage_head if headshot else data.damage_body
	if not headshot and not _is_torso_point(combatant, point):
		base = data.damage_limb
	var dmg := base * _falloff(dist)
	if not is_player:
		dmg *= data.bot_damage_scale
	var victim_id: String = combatant.get("combatant_id")
	var dealt := health.apply_damage(dmg, owner_id, owner_team, headshot)
	if dealt <= 0.0:
		return
	Fx.spawn_blood(point, normal if normal != Vector3.ZERO else Vector3.UP)
	Audio.play_3d("impact_flesh", point, -6.0, 0.1, 30.0)
	var killed := not health.is_alive()
	if is_player:
		Audio.play_ui("headshot" if headshot else "hitmarker", -6.0 if not headshot else -3.0)
		hit_confirmed.emit(str(combatant.get("display_name")), headshot, killed)
	Game.report_damage_credit(owner_id, victim_id, headshot)


func _is_torso_point(combatant: Node, point: Vector3) -> bool:
	var node3d := combatant as Node3D
	if node3d == null:
		return true
	var local_y := point.y - node3d.global_position.y
	return local_y > 0.85


func _falloff(dist: float) -> float:
	if dist <= data.effective_range:
		return 1.0
	var t: float = clampf((dist - data.effective_range) / maxf(1.0, data.max_range - data.effective_range), 0.0, 1.0)
	return lerpf(1.0, data.range_falloff, t)


# ---------------------------------------------------------------- helpers
func current_spread() -> float:
	if data == null:
		return 0.0
	if is_player:
		if aiming:
			return data.spread_ads
		var moving := false
		if holder is CharacterBody3D:
			var body := holder as CharacterBody3D
			moving = Vector2(body.velocity.x, body.velocity.z).length() > 1.5
		return data.spread_moving if moving else data.spread_standing
	return data.spread_ads


func recoil_offset() -> Vector2:
	return _recoil_accum


func muzzle_position() -> Vector3:
	if muzzle != null:
		return muzzle.global_position
	if camera != null:
		return camera.global_position
	return _holder_position()


func ammo_text() -> String:
	return "%d / %d" % [magazine, reserve]


func is_reloading() -> bool:
	return state == State.RELOADING


func can_shoot() -> bool:
	return state != State.RELOADING and state != State.EQUIPPING and magazine > 0 and _fire_cooldown <= 0.0


func _space() -> PhysicsDirectSpaceState3D:
	if _space_state == null:
		var vp := get_viewport()
		if vp != null and vp.world_3d != null:
			_space_state = vp.world_3d.direct_space_state
	return _space_state


func _audio_position() -> Vector3:
	return _holder_position()


## This controller is a plain Node (it is not part of the 3D scene graph), so world
## positions must come from the node that owns it, never from `self`.
func _holder_position() -> Vector3:
	if holder != null:
		return holder.global_position
	if camera != null:
		return camera.global_position
	return Vector3.ZERO


## Forward axis of the holder, used when no muzzle node was supplied.
func basis_from_holder() -> Basis:
	if holder != null:
		return holder.global_transform.basis
	if camera != null:
		return camera.global_transform.basis
	return Basis.IDENTITY
