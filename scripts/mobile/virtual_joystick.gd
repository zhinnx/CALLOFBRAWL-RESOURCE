## CALLOFBRAWL — virtual thumbstick.
##
## Owns exactly ONE touch index at a time, so several fingers can drive several
## controls simultaneously (movement + look + fire + reload).
## Output is a normalised Vector2 in the -1..1 range with a dead zone applied,
## plus a `sprinting` flag when pushed beyond 85 % of travel.
class_name CBVirtualJoystick
extends Control

signal changed(value: Vector2, sprinting: bool)

@export var radius: float = 120.0
@export var dead_zone: float = 0.14
@export var sprint_threshold: float = 0.86
@export var base_color: Color = Color(1, 1, 1, 0.13)
@export var ring_color: Color = Color(1, 1, 1, 0.30)
@export var grip_color: Color = Color(0.90, 0.93, 1.0, 0.55)
@export var dynamic_origin: bool = true

var value: Vector2 = Vector2.ZERO
var sprinting: bool = false
var touch_index: int = -1

var _centre: Vector2 = Vector2.ZERO
var _grip: Vector2 = Vector2.ZERO
var _active: bool = false
var _scale: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scale = maxf(0.6, get_viewport_rect().size.y / 720.0)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if not _active:
		_centre = size * 0.5
		_grip = _centre
		_scale = maxf(0.6, get_viewport_rect().size.y / 720.0)
	queue_redraw()


func _draw() -> void:
	var r = radius * _scale
	draw_circle(_centre, r, base_color)
	draw_arc(_centre, r, 0.0, TAU, 48, ring_color, maxf(1.5, 2.0 * _scale), true)
	draw_arc(_centre, r * sprint_threshold, 0.0, TAU, 40, Color(1, 1, 1, 0.10), maxf(1.0, 1.5 * _scale), true)
	# grip
	var grip_r: float = 46.0 * _scale
	draw_circle(_grip, grip_r, Color(0, 0, 0, 0.18))
	draw_circle(_grip, grip_r * 0.86, grip_color)
	draw_circle(_grip, grip_r * 0.45, Color(1, 1, 1, 0.22))


## Called by the input controller for every touch event over the gameplay area.
## Returns true when the event was consumed.
func handle_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _active or touch_index != -1:
				return false
			if not _accepts_point(t.position):
				return false
			touch_index = t.index
			_active = true
			if dynamic_origin:
				# the stick re-centres under the thumb, clamped inside this control
				var local := _to_local(t.position)
				_centre = _clamp_centre(local)
				_grip = local
			else:
				_centre = size * 0.5
				_grip = _to_local(t.position)
			_update_from_point(t.position)
			return true
		if t.index == touch_index:
			_release()
			return true
		return false
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == touch_index:
			_update_from_point(d.position)
			return true
	return false


## Touch events arrive in *screen* coordinates; every check and every drawing value in
## this control is in local coordinates, so all comparisons go through this.
func _to_local(p: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * p


func _accepts_point(p: Vector2) -> bool:
	var r = radius * _scale * 1.8
	return (_to_local(p) - size * 0.5).length() <= r


## Keeps the dynamic origin (and therefore the whole stick) inside this control.
func _clamp_centre(local_point: Vector2) -> Vector2:
	var m = radius * _scale
	return Vector2(clampf(local_point.x, m, maxf(m, size.x - m)),
			clampf(local_point.y, m, maxf(m, size.y - m)))


func _update_from_point(screen_point: Vector2) -> void:
	var delta := _to_local(screen_point) - _centre
	var limit = radius * _scale
	var len: float = delta.length()
	if len > limit and len > 0.001:
		delta = delta / len * limit
	_grip = _centre + delta
	var norm = delta / maxf(1.0, limit)
	var mag: float = norm.length()
	if mag < dead_zone:
		value = Vector2.ZERO
		sprinting = false
	else:
		# remap so the response is smooth right after the dead zone
		var scaled := clampf((mag - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
		value = norm / maxf(0.001, mag) * scaled
		sprinting = mag >= sprint_threshold
	changed.emit(value, sprinting)
	queue_redraw()


func _release() -> void:
	touch_index = -1
	_active = false
	value = Vector2.ZERO
	sprinting = false
	if not dynamic_origin:
		_grip = size * 0.5
	changed.emit(Vector2.ZERO, false)
	queue_redraw()


func reset() -> void:
	_release()


func is_active() -> bool:
	return _active


## Exposed for the HUD to draw hints.
func normalised_value() -> Vector2:
	return value
