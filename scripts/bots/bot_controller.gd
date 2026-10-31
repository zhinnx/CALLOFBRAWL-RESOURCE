## CALLOFBRAWL — AI combatant.
##
## A complete state machine on top of NavigationAgent3D. Bots
##   * only know enemy positions through line of sight (no wall hacks)
##   * patrol between tactical points of interest across the real Dust2 navmesh
##   * chase / engage / strafe / take cover / reload / retreat
##   * have per-bot accuracy, reaction time, aggression and jitter
##   * never shoot teammates (friendly fire is impossible and they re-target)
##   * respawn through the same spawn pipeline as the player
##
## Performance: perception runs at ~7 Hz (staggered), navigation at 10 Hz, and
## only the weapon fire check runs at frame rate while engaging.
class_name CBBotController
extends CharacterBody3D

signal bot_eliminated(victim_id: String, attacker_id: String, headshot: bool)

enum State { IDLE, PATROL, SEARCH, ENGAGE, RELOAD, RETREAT, RESPAWN }

const WALK_SPEED := 3.6
const ENGAGE_SPEED := 4.4
const CHASE_SPEED := 5.2
const RETREAT_SPEED := 5.4
const GRAVITY := 18.0

const PERCEPTION_INTERVAL := 0.14
const NAV_INTERVAL := 0.10
## Re-planning cadence for a *moving* goal (chasing a player). Bots re-plan at most
## twice a second, and only when the goal drifted away from the planned one.
const REPATH_INTERVAL := 0.5
const REPATH_DISTANCE := 1.6
const WAYPOINT_REACHED := 0.7
const MAX_TARGETS := 6

## Identity
var combatant_id: String = "bot"
var display_name: String = "Bot"
var team: int = CBTeam.ALPHA
var is_alive: bool = true
var state: int = State.IDLE

## Wired by MatchManager
var match_manager: Node
var map_loader: CBMapLoader
var target_manager: Node

## Behaviour tuning (randomised per bot at spawn)
var accuracy: float = 0.6
var reaction_time: float = 0.35
var aggression: float = 0.5
var preferred_range: float = 16.0
var fov_degrees: float = 110.0
var vision_range: float = 55.0

var health_component: CBHealthComponent
var weapon: CBWeaponController
var visual: CBCharacterVisual

## Path following (A* over the baked navigation graph, see CBNavMeshData).
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _goal: Vector3 = Vector3.ZERO
var _has_goal: bool = false
var path_next_index: int = 0

## Runtime
var _perception_timer: float = 0.0
var _nav_timer: float = 0.0
var _state_timer: float = 0.0
var _reaction_timer: float = 0.0
var _fire_timer: float = 0.0
var _strafe_timer: float = 0.0
var _strafe_dir: float = 1.0
var _burst_shots: int = 0
var _burst_timer: float = 0.0
var _patrol_point: Vector3 = Vector3.ZERO
var _last_known_enemy: Vector3 = Vector3.ZERO
var _has_last_known: bool = false
var _target: Node3D = null
var _search_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _shots_fired: int = 0
var _cover_point: Vector3 = Vector3.ZERO
var _aim_error: Vector3 = Vector3.ZERO
var _aim_error_timer: float = 0.0
var _spawn_yaw: float = 0.0

const ATTACH_POINTS := ["Head", "Torso", "Legs"]


func _ready() -> void:
	collision_layer = CBMapLoader.LAYER_COMBATANT
	collision_mask = CBMapLoader.LAYER_WORLD | CBMapLoader.LAYER_COMBATANT
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	floor_stop_on_slope = true
	add_to_group(Game.GROUP_COMBATANT)
	_build_nodes()
	_last_position = global_position


func _build_nodes() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Body"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0, 0.90, 0)
	add_child(shape)

	_register_hitbox("Head", Game.GROUP_HEAD, Vector3(0, 1.64, 0), 0.145)
	_register_hitbox("Torso", Game.GROUP_BODY, Vector3(0, 1.18, 0), 0.29)
	_register_hitbox("Legs", Game.GROUP_BODY, Vector3(0, 0.52, 0), 0.26)

	health_component = CBHealthComponent.new()
	health_component.name = "Health"
	add_child(health_component)
	health_component.setup(combatant_id, team, self)
	health_component.died.connect(_on_died)
	health_component.damaged.connect(_on_damaged)

	visual = CBCharacterVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(team, false, true)

	weapon = CBWeaponController.new()
	weapon.name = "Weapon"
	weapon.data = load("res://resources/weapons/ak47.tres") as CBWeaponData
	weapon.holder = self
	weapon.camera = null
	add_child(weapon)
	weapon.setup(combatant_id, team, false)
	weapon.muzzle = visual.muzzle_marker
	weapon.flash_rig = visual.flash_rig
	weapon.rifle_model = visual.weapon_model

	_has_goal = false
	path_next_index = 0


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


# ---------------------------------------------------------------- setup
func configure(id: String, bot_name: String, bot_team: int, difficulty: int) -> void:
	combatant_id = id
	display_name = bot_name
	team = bot_team
	retune(difficulty)
	health_component.setup(id, team, self)


## Difficulty 0 easy / 1 normal / 2 hard. Each bot also gets personal jitter so no
## two bots behave identically.
func retune(difficulty: int) -> void:
	var base_acc := [0.42, 0.62, 0.78][clampi(difficulty, 0, 2)]
	var base_react := [0.62, 0.38, 0.24][clampi(difficulty, 0, 2)]
	accuracy = clampf(base_acc + randf_range(-0.10, 0.12), 0.2, 0.94)
	reaction_time = clampf(base_react + randf_range(-0.09, 0.16), 0.12, 0.9)
	aggression = randf_range(0.25, 1.0)
	preferred_range = randf_range(9.0, 24.0)
	fov_degrees = randf_range(95.0, 130.0)
	vision_range = randf_range(42.0, 62.0)


func on_spawn(pos: Vector3, yaw: float = 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	is_alive = true
	visible = true
	_reset_state()
	health_component.reset()
	weapon.reset_loadout()
	if visual:
		visual.visible = true
		visual.revive()
	_spawn_yaw = yaw
	rotation = Vector3(0, yaw, 0)
	_last_position = pos
	_patrol_point = _pick_patrol_point()
	_set_state(State.PATROL)


func _reset_state() -> void:
	_target = null
	_has_last_known = false
	_reaction_timer = 0.0
	_fire_timer = 0.0
	_burst_shots = 0
	_search_timer = 0.0
	_stuck_timer = 0.0
	_path = PackedVector3Array()
	path_next_index = 0
	_has_goal = false
	set_physics_process(true)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	_state_timer = 0.0
	match state:
		State.ENGAGE:
			_reaction_timer = reaction_time
		State.RELOAD:
			weapon.request_reload()
		State.PATROL:
			_patrol_point = _pick_patrol_point()


# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_state_timer += delta
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = PERCEPTION_INTERVAL * randf_range(0.85, 1.2)
		_update_perception()

	match state:
		State.IDLE: _tick_idle(delta)
		State.PATROL: _tick_patrol(delta)
		State.SEARCH: _tick_search(delta)
		State.ENGAGE: _tick_engage(delta)
		State.RELOAD: _tick_reload(delta)
		State.RETREAT: _tick_retreat(delta)
		State.RESPAWN:
			# dead: never move, never keep residual velocity
			velocity = Vector3.ZERO

	move_and_slide()
	_check_stuck(delta)
	if visual:
		var speed := Vector2(velocity.x, velocity.z).length()
		visual.animate(delta, speed, is_on_floor(), velocity.y)
		if _target != null and _target is Node3D:
			visual.face_towards((_target as Node3D).global_position, delta)


# ---------------------------------------------------------------- perception
func _update_perception() -> void:
	var previous := _target
	_target = _find_best_visible_enemy()
	if _target != null:
		_has_last_known = true
		_last_known_enemy = (_target as Node3D).global_position
	if _target == null and previous != null:
		_search_timer = randf_range(2.0, 4.5)
		_set_state(State.SEARCH)
	elif _target != null and state != State.ENGAGE and state != State.RELOAD and state != State.RETREAT:
		_set_state(State.ENGAGE)


func _find_best_visible_enemy() -> Node3D:
	var best: Node3D = null
	var best_score := -1.0
	var origin := global_position + Vector3(0, 1.55, 0)
	var forward := -global_transform.basis.z
	var cos_fov := cos(deg_to_rad(fov_degrees * 0.5))
	for node in get_tree().get_nodes_in_group(Game.GROUP_COMBATANT):
		if node == self:
			continue
		var n3 := node as Node3D
		if n3 == null or not n3.visible and not n3.get("is_alive"):
			continue
		var hc: CBHealthComponent = n3.get("health_component") as CBHealthComponent
		if hc == null or not hc.is_alive():
			continue
		if CBTeam.is_friendly(hc.team, team):
			continue
		var to := (n3.global_position + Vector3(0, 1.2, 0)) - origin
		var dist := to.length()
		if dist > vision_range or dist < 0.5:
			continue
		var dir := to / dist
		if forward.dot(dir) < cos_fov and dist > 6.0:
			continue
		if not _has_line_of_sight(origin, n3):
			continue
		# closer + more in front is better; low health enemies get priority
		var score := (1.0 - dist / vision_range) * 1.4 + forward.dot(dir) * 0.6
		if hc.health_fraction() < 0.4:
			score += 0.25
		if score > best_score:
			best_score = score
			best = n3
	return best


func _has_line_of_sight(origin: Vector3, target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var points := [
		target.global_position + Vector3(0, 1.55, 0),
		target.global_position + Vector3(0, 0.95, 0),
		target.global_position + Vector3(0, 0.45, 0),
	]
	for p: Vector3 in points:
		var q := PhysicsRayQueryParameters3D.create(origin, p, CBMapLoader.LAYER_WORLD)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
	return false


# ---------------------------------------------------------------- navigation
## Steers the bot along an A* path towards `target_pos`. The path is recomputed when
## the goal moves (chasing), when it is exhausted, or when the bot drifted off it.
func _move_towards(target_pos: Vector3, speed: float, delta: float) -> void:
	_nav_timer -= delta
	var drifted := _has_goal and _goal.distance_to(target_pos) > REPATH_DISTANCE
	var exhausted := _path.is_empty() or path_next_index >= _path.size()
	if _nav_timer <= 0.0 and (exhausted or drifted):
		_nav_timer = REPATH_INTERVAL
		_plan_path(target_pos)

	if _path.is_empty():
		# no navmesh path (target outside the playable area): walk straight at it
		_steer_towards(target_pos, speed, delta)
		return

	# skip waypoints we are already past
	while path_next_index < _path.size():
		var wp := _path[path_next_index]
		if Vector2(wp.x - global_position.x, wp.z - global_position.z).length() <= WAYPOINT_REACHED:
			path_next_index += 1
		else:
			break
	if path_next_index >= _path.size():
		_slow_stop(delta)
		return
	_steer_towards(_path[path_next_index], speed, delta)


func _plan_path(target_pos: Vector3) -> void:
	var path := CBNavMeshData.find_path(global_position, target_pos)
	_path = CBNavMeshData.path_points(path)
	path_next_index = 0
	# drop the first waypoint when it is the cell we already stand in
	if _path.size() > 1 and _path[0].distance_to(global_position) < 1.2:
		path_next_index = 1
	_goal = target_pos
	_has_goal = true
	if _path.size() > 0:
		# the final waypoint is the goal cell centre; aim at the real target when it
		# is close enough to be reached directly
		if _path[_path.size() - 1].distance_to(target_pos) < 1.5:
			_path.append(target_pos)


func _steer_towards(point: Vector3, speed: float, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.2:
		_slow_stop(delta)
		return
	dir = dir.normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(dir * speed, 18.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if visual:
		visual.face_direction(dir, delta)


## How far the current plan still wants the bot to walk (used by the stuck check).
func path_remaining() -> int:
	return maxi(0, _path.size() - path_next_index)


func _slow_stop(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 22.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _pick_patrol_point() -> Vector3:
	var pois := CBNavMeshData.points_of_interest()
	if pois.is_empty():
		return global_position
	# Prefer points that are towards the middle of the map / enemy side.
	var enemy_side := 1.0 if team == CBTeam.ALPHA else -1.0
	var best := pois[randi() % pois.size()]
	for i in 5:
		var candidate: Vector3 = pois[randi() % pois.size()]
		var score := (candidate.z - 1215.0) * enemy_side * -0.02 + randf() * 0.6
		var best_score := (best.z - 1215.0) * enemy_side * -0.02
		if score > best_score:
			best = candidate
	return best


# ---------------------------------------------------------------- states
func _tick_idle(delta: float) -> void:
	_slow_stop(delta)
	if _state_timer > 2.0:
		_set_state(State.PATROL)


func _tick_patrol(delta: float) -> void:
	if _target != null:
		_set_state(State.ENGAGE)
		return
	if global_position.distance_to(_patrol_point) < 2.0 or _state_timer > 18.0:
		_set_state(State.PATROL)
		_patrol_point = _pick_patrol_point()
		_state_timer = 0.0
	_move_towards(_patrol_point, WALK_SPEED, delta)
	# idle scan: turn slowly towards patrol direction
	if visual:
		visual.face_direction((_patrol_point - global_position).normalized(), delta)


func _tick_search(delta: float) -> void:
	if _target != null:
		_set_state(State.ENGAGE)
		return
	if _has_last_known:
		_move_towards(_last_known_enemy, ENGAGE_SPEED, delta)
		if global_position.distance_to(_last_known_enemy) < 3.0:
			_has_last_known = false
	_search_timer -= delta
	if _search_timer <= 0.0:
		_set_state(State.PATROL)


func _tick_engage(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		if _has_last_known:
			_set_state(State.SEARCH)
		else:
			_set_state(State.PATROL)
		return
	var enemy := _target as Node3D
	var hc: CBHealthComponent = enemy.get("health_component") as CBHealthComponent
	if hc == null or not hc.is_alive():
		_target = null
		return
	var to := enemy.global_position - global_position
	var dist := Vector2(to.x, to.z).length()
	var full_dist := to.length()

	# look at the enemy (visual) and aim the weapon
	if visual:
		visual.face_towards(enemy.global_position, delta)

	# movement decision: keep preferred range, strafe, or chase
	var moving := false
	if dist > preferred_range * 1.35 and aggression > 0.35:
		_move_towards(enemy.global_position, CHASE_SPEED, delta)
		moving = true
	elif dist < preferred_range * 0.55:
		# back off while firing
		var away := (global_position - enemy.global_position).normalized()
		var back := global_position + away * 6.0
		_move_towards(back, WALK_SPEED, delta)
		moving = true
	else:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(0.7, 1.8)
			_strafe_dir = 1.0 if randf() > 0.5 else -1.0
			if randf() < 0.22:
				_strafe_dir = 0.0
		if _strafe_dir != 0.0:
			var side := Vector3(-to.z, 0.0, to.x).normalized() * _strafe_dir
			var goal := global_position + side * 4.0
			_move_towards(goal, WALK_SPEED * 0.9, delta)
			moving = true
		else:
			_slow_stop(delta)

	# retreat when badly hurt
	if health_component.health_fraction() < 0.25 and aggression < 0.75 and randf() < 0.02:
		_set_state(State.RETREAT)
		return

	# reload when dry
	if weapon.magazine <= 0:
		_set_state(State.RELOAD)
		return
	if weapon.magazine < 6 and weapon.reserve > 0 and dist > 12.0 and randf() < 0.02:
		_set_state(State.RELOAD)
		return

	# reaction time then fire
	_reaction_timer -= delta
	if _reaction_timer > 0.0:
		return
	if _fire_timer > 0.0:
		_fire_timer -= delta
		return
	# accuracy: hit probability falls with distance and movement
	var hit_chance := accuracy
	hit_chance *= clampf(1.15 - full_dist / maxf(1.0, vision_range), 0.25, 1.0)
	if moving:
		hit_chance *= 0.82
	if not _has_line_of_sight(global_position + Vector3(0, 1.55, 0), enemy):
		return
	if _friendly_in_line(enemy):
		return
	_shoot_at(enemy, hit_chance, full_dist)
	_fire_timer = weapon.data.fire_interval() * randf_range(1.0, 1.9) if weapon.data else 0.12
	_burst_shots += 1
	if _burst_shots >= int(randi_range(3, 7)):
		_burst_shots = 0
		_fire_timer += randf_range(0.25, 0.7)


## Returns true when a living teammate is between us and the target.
func _friendly_in_line(enemy: Node3D) -> bool:
	var from := global_position + Vector3(0, 1.45, 0)
	var to := enemy.global_position + Vector3(0, 1.2, 0)
	for node in get_tree().get_nodes_in_group(Game.GROUP_COMBATANT):
		var other := node as Node3D
		if other == null or other == self or other == enemy:
			continue
		var hc: CBHealthComponent = other.get("health_component") as CBHealthComponent
		if hc == null or not hc.is_alive() or not CBTeam.is_friendly(hc.team, team):
			continue
		var p := other.global_position + Vector3(0, 1.0, 0)
		var seg := to - from
		var t := clampf((p - from).dot(seg) / maxf(0.001, seg.length_squared()), 0.0, 1.0)
		if t <= 0.05 or t >= 0.98:
			continue
		if (from + seg * t).distance_to(p) < 0.55:
			return true
	return false


## Fires one round. Bots do not use perfect aim: a fraction of shots are "misses"
## which are sent at an offset direction, so the player sees near-misses.
func _shoot_at(enemy: Node3D, hit_chance: float, dist: float) -> void:
	var muzzle := visual.muzzle_position() if visual else global_position
	var aim_point := enemy.global_position + Vector3(0, 1.2, 0)
	# strafing bots lead slightly; add distance-dependent jitter
	var dir := (aim_point - muzzle).normalized()
	var will_hit := randf() < hit_chance
	if not will_hit:
		var spread := deg_to_rad(randf_range(3.0, 9.0))
		var axis := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)).normalized()
		dir = (dir + axis * tan(spread)).normalized()
	_aim_error = dir
	_shots_fired += 1
	if visual:
		visual.play_shoot_kick()
		fire_bot_hitscan(enemy, muzzle, dir, will_hit)
	weapon.consume_round()
	set_meta("last_dir", dir)


## The bot's bullets are resolved here (not via WeaponController) so the AI fully
## controls hit probability, while the player's WeaponController stays authoritative
## for the local weapon.
func fire_bot_hitscan(enemy: Node3D, muzzle: Vector3, dir: Vector3, will_hit: bool) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var max_range: float = weapon.data.max_range if weapon.data else 120.0
	var end := muzzle + dir * max_range
	var q := PhysicsRayQueryParameters3D.create(muzzle, end,
			CBMapLoader.LAYER_WORLD | CBMapLoader.LAYER_COMBATANT)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	var point := end
	var victim: Node = null
	if not hit.is_empty():
		point = hit.get("position", end)
		var collider: Object = hit.get("collider")
		if collider is Node:
			var combatant := _combatant_of(collider as Node)
			if combatant != null and combatant != self:
				victim = combatant
	Fx.spawn_tracer(muzzle, point, 0.04)
	Audio.play_3d("rifle", muzzle, -3.0, 0.1, 70.0)
	if victim == null:
		if not hit.is_empty():
			Fx.spawn_impact(point, hit.get("normal", Vector3.UP), 0.9)
			Fx.spawn_spark_burst(point, hit.get("normal", Vector3.UP))
		return
	# Never damage teammates.
	var hc: CBHealthComponent = victim.get("health_component") as CBHealthComponent
	if hc == null:
		return
	if CBTeam.is_friendly(hc.team, team):
		return
	if not will_hit:
		# aimed miss that grazed a teammate/other body: no damage
		return
	var headshot := randf() < 0.12
	var base: float = weapon.data.damage_head if headshot else weapon.data.damage_body
	var dmg: float = base * clampf(1.2 - point.distance_to(muzzle) / 90.0, 0.5, 1.0)
	dmg *= weapon.data.bot_damage_scale
	var dealt := hc.apply_damage(dmg, combatant_id, team, headshot)
	if dealt > 0.0:
		Fx.spawn_blood(point, dir * -1.0)
		Audio.play_3d("impact_flesh", point, -8.0, 0.1, 30.0)
	Game.report_damage_credit(combatant_id, str(victim.get("combatant_id")), headshot)


func _combatant_of(hitbox: Node) -> Node:
	var cur: Node = hitbox
	while cur != null:
		if cur.is_in_group(Game.GROUP_COMBATANT):
			return cur
		cur = cur.get_parent()
	var direct := get_tree().get_nodes_in_group(Game.GROUP_COMBATANT)
	for n in direct:
		if n == hitbox:
			return n
	return null


func _tick_reload(delta: float) -> void:
	_slow_stop(delta)
	if _target != null and visual:
		visual.face_towards((_target as Node3D).global_position, delta)
	if not weapon.is_reloading():
		if _target != null:
			_set_state(State.ENGAGE)
		else:
			_set_state(State.PATROL)


func _tick_retreat(delta: float) -> void:
	# break line of sight: run away from the last known enemy, offset sideways so the
	# bot slides behind cover instead of backing into open ground
	var away: Vector3
	if _has_last_known:
		away = (global_position - _last_known_enemy).normalized()
	else:
		away = global_transform.basis.z
	away.y = 0.0
	away = away.normalized()
	var dir_sign := _strafe_dir if _strafe_dir != 0.0 else 1.0
	var side := Vector3(-away.z, 0.0, away.x) * dir_sign
	var goal := global_position + away * 9.0 + side * 4.0
	_cover_point = goal
	_move_towards(goal, RETREAT_SPEED, delta)
	if _state_timer > 2.4:
		_set_state(State.ENGAGE if _target != null else State.SEARCH)
	if health_component.health_fraction() > 0.6:
		_set_state(State.ENGAGE if _target != null else State.PATROL)


func _check_stuck(delta: float) -> void:
	if state == State.IDLE or state == State.RELOAD:
		return
	var moved := global_position.distance_to(_last_position)
	if moved < 0.05 and Vector2(velocity.x, velocity.z).length() > 1.0:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta)
	_last_position = global_position
	if _stuck_timer > 1.2:
		_stuck_timer = 0.0
		# jump once to hop small ledges, then re-plan somewhere else
		if is_on_floor():
			velocity.y = 4.2
		_path = PackedVector3Array()
		path_next_index = 0
		_set_state(State.PATROL)
		_patrol_point = _pick_patrol_point()
		_has_goal = false


# ---------------------------------------------------------------- damage / death
## Being shot reveals the shooter's position to this bot (and, with a delay, to its
## nearby teammates) — that is how a real squad reacts, and it stays fair because
## the shooter really did give its position away by firing.
func _on_damaged(_amount: float, attacker_id: String, _headshot: bool, _remaining: float) -> void:
	if attacker_id == combatant_id or attacker_id == "":
		return
	var attacker := _find_combatant_by_id(attacker_id)
	if attacker == null:
		return
	if CBTeam.is_friendly(_team_of(attacker), team):
		return
	_last_known_enemy = attacker.global_position
	_has_last_known = true
	_target = attacker
	_reaction_timer = minf(_reaction_timer, reaction_time * 0.6)
	if state != State.ENGAGE and state != State.RELOAD:
		_set_state(State.ENGAGE)
	alert_teammates(attacker.global_position, 22.0)


## Shares a contact with friendly bots in range (approximate, no wall knowledge:
## they still need their own line of sight before firing).
func alert_teammates(position: Vector3, radius: float) -> void:
	for node in get_tree().get_nodes_in_group(Game.GROUP_COMBATANT):
		var other := node as CBBotController
		if other == null or other == self or not other.is_alive:
			continue
		if not CBTeam.is_friendly(other.team, team):
			continue
		if other.global_position.distance_to(global_position) > radius:
			continue
		if not other._has_last_known:
			other._last_known_enemy = position
			other._has_last_known = true
			if other.state == State.PATROL or other.state == State.IDLE:
				other._set_state(State.SEARCH)
				other._search_timer = 6.0


func _find_combatant_by_id(id: String) -> Node3D:
	for node in get_tree().get_nodes_in_group(Game.GROUP_COMBATANT):
		var n3 := node as Node3D
		if n3 != null and str(n3.get("combatant_id")) == id and n3 != self:
			return n3
	return null


func _team_of(n: Node) -> int:
	var hc: CBHealthComponent = n.get("health_component") as CBHealthComponent
	if hc != null:
		return hc.team
	return CBTeam.NONE


func _on_died(attacker_id: String, headshot: bool) -> void:
	is_alive = false
	velocity = Vector3.ZERO
	set_physics_process(false)
	if visual:
		visual.play_death()
	_path = PackedVector3Array()
	path_next_index = 0
	_has_goal = false
	bot_eliminated.emit(combatant_id, attacker_id, headshot)
	if match_manager != null and match_manager.has_method("on_bot_died"):
		match_manager.call("on_bot_died", self, attacker_id, headshot)
	# hide the corpse from physics: no movement blocking and no hitscan hits
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)
		elif child is Area3D:
			(child as Area3D).set_deferred("monitorable", false)
	var timer := get_tree().create_timer(2.4)
	timer.timeout.connect(_finish_death)


func _finish_death() -> void:
	if is_alive:
		return
	visible = false
	if match_manager != null and match_manager.has_method("begin_respawn_timer"):
		match_manager.call("begin_respawn_timer", self)


func on_respawn(pos: Vector3, yaw: float) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", false)
			(child as Node3D).set_deferred("visible", true)
		elif child is Area3D:
			(child as Node3D).set_deferred("visible", true)
	on_spawn(pos, yaw)


func state_name() -> String:
	var keys := State.keys()
	return str(keys[state]) if state >= 0 and state < keys.size() else "?"


func ammo_text() -> String:
	return weapon.ammo_text() if weapon else "-"
