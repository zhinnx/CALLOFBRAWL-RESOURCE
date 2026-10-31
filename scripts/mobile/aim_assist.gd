## CALLOFBRAWL — optional mobile aim assist.
##
## Deliberately gentle: it never snaps or locks. It
##   * scans living enemy combatants inside a cone around the crosshair
##   * rejects anything that is not visible (single centre ray + head offset ray)
##   * while a valid target exists: slows the player's look sensitivity (sticky aim)
##   * when the crosshair is close to the target: adds a small, capped rotation
##   * never assists towards teammates or through walls
## All limits are configurable through Settings (assist toggle, strength, radius,
## cone FOV) and can be disabled entirely.
class_name CBAimAssist
extends Node

const MAX_ASSIST_DEG_PER_FRAME := 2.2

var enabled: bool = true
var strength: float = 0.6
var radius: float = 9.0
var cone_fov: float = 24.0
var team: int = CBTeam.ALPHA
var camera: Camera3D

var _target: Node3D = null
var _retarget_timer: float = 0.0
var _cache: Array[Node3D] = []
var _cache_timer: float = 0.0

signal target_changed(has_target: bool)


func setup(player_team: int, cam: Camera3D) -> void:
	team = player_team
	camera = cam
	refresh_settings()


func refresh_settings() -> void:
	enabled = Settings.get_bool("aim_assist")
	strength = clampf(Settings.get_float("aim_assist_strength"), 0.0, 1.0)
	radius = maxf(2.0, Settings.get_float("aim_assist_radius"))
	cone_fov = maxf(4.0, Settings.get_float("aim_assist_fov"))


func _process(delta: float) -> void:
	if not enabled or camera == null:
		if _target != null:
			_target = null
			target_changed.emit(false)
		return
	_retarget_timer -= delta
	_cache_timer -= delta
	if _cache_timer <= 0.0:
		_cache_timer = 0.5
		_refresh_cache()
	if _retarget_timer <= 0.0:
		_retarget_timer = 0.08
		_pick_target()


func _refresh_cache() -> void:
	_cache.clear()
	for node in get_tree().get_nodes_in_group(Game.GROUP_COMBATANT):
		var n3 := node as Node3D
		if n3 == null or not n3.visible:
			continue
		var hc: CBHealthComponent = n3.get("health_component") as CBHealthComponent
		if hc == null or not hc.is_alive():
			continue
		if CBTeam.is_friendly(hc.team, team):
			continue
		_cache.append(n3)


func _pick_target() -> void:
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var best: Node3D = null
	var best_score := -1.0
	var cos_limit := cos(deg_to_rad(cone_fov))
	for node in _cache:
		if node == null or not is_instance_valid(node):
			continue
		var hc: CBHealthComponent = node.get("health_component") as CBHealthComponent
		if hc == null or not hc.is_alive():
			continue
		var to = (node.global_position + Vector3(0, 1.2, 0)) - origin
		var dist: float = to.length()
		if dist > radius or dist < 0.4:
			continue
		var dir = to / dist
		var dot = forward.dot(dir)
		if dot < cos_limit:
			continue
		if not _visible(node, origin):
			continue
		# prefer targets near the crosshair, then near ones
		var score = dot * 2.0 - dist / radius
		if score > best_score:
			best_score = score
			best = node
	var had := _target != null
	_target = best
	if had != (_target != null):
		target_changed.emit(_target != null)


func _visible(target: Node3D, origin: Vector3) -> bool:
	var space = camera.get_world_3d().direct_space_state
	if space == null:
		return false
	var points := [target.global_position + Vector3(0, 1.2, 0), target.global_position + Vector3(0, 0.6, 0)]
	for p: Vector3 in points:
		var q := PhysicsRayQueryParameters3D.create(origin, p, CBMapLoader.LAYER_WORLD)
		q.collide_with_areas = false
		var hit = space.intersect_ray(q)
		if hit.is_empty():
			return true
	return false


## 0..1 stickiness applied to the player's look sensitivity (1 = no change).
func sensitivity_multiplier() -> float:
	if _target == null or not enabled:
		return 1.0
	return lerpf(1.0, 0.62, clampf(strength, 0.0, 1.0))


## True while a valid enemy is inside the assist cone with a clear line of sight.
func is_tracking() -> bool:
	return _target != null and is_instance_valid(_target)


## Gentle rotational pull towards the target, in screen degrees. The per-frame step is
## capped at MAX_ASSIST_DEG_PER_FRAME x strength (~1.3 deg/frame at 0.6 strength, applied
## once per rendered frame): enough to help a thumb settle on a target inside the cone,
## never enough to aim for the player.
func rotation_assist() -> Vector2:
	if _target == null or not enabled or strength <= 0.0:
		return Vector2.ZERO
	var origin := camera.global_position
	var aim_point := _target.global_position + Vector3(0, 1.05, 0)
	var to := aim_point - origin
	if to.length_squared() < 0.01:
		return Vector2.ZERO
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var basis := camera.global_transform.basis
	var cur_yaw := atan2(-basis.z.x, -basis.z.z)
	var cur_pitch = asin(clampf(basis.z.y, -1.0, 1.0)) * -1.0
	var d_yaw := wrapf(want_yaw - cur_yaw, -PI, PI)
	var d_pitch := wrapf(want_pitch - cur_pitch, -PI, PI)
	if absf(d_yaw) > deg_to_rad(cone_fov * 1.6) or absf(d_pitch) > deg_to_rad(cone_fov * 1.6):
		return Vector2.ZERO
	var gain = deg_to_rad(MAX_ASSIST_DEG_PER_FRAME) * strength
	var yaw_step := clampf(d_yaw * 0.25, -gain, gain)
	var pitch_step := clampf(d_pitch * 0.25, -gain, gain)
	# Both deltas are in "camera" space; CBPlayerController.add_look expects screen
	# deltas (it subtracts internally), so hand it the negated values. Without this the
	# assist would push the crosshair *away* from the target.
	return Vector2(rad_to_deg(-yaw_step), rad_to_deg(-pitch_step))


func has_target() -> bool:
	return _target != null


func target() -> Node3D:
	return _target


func debug_target_position() -> Vector3:
	if _target == null:
		return Vector3.ZERO
	return _target.global_position + Vector3(0, 1.9, 0)
