## CALLOFBRAWL — drag-to-aim fire control.
##
## This is the heart of the mobile shooting feel:
##   * touch and hold  -> continuous automatic fire
##   * drag the same finger while firing -> the camera turns (aiming), the shot
##     keeps firing; the control forwards the drag delta to the player
##   * release -> stops firing
##   * up to two extra fingers can press without stealing the firing finger, so a
##     player can move (left thumb), fire+aim (right thumb) and tap reload (index)
##     at the same time.
## A short tap that never moves also fires (single tap = one burst).
class_name CBFireButton
extends Control

signal fire_started
signal fire_stopped
signal aim_delta(relative: Vector2)

@export var radius: float = 92.0
@export var accent: Color = Color(1.0, 0.34, 0.28)
@export var drag_sensitivity: float = 0.55

var pressed: bool = false
var touch_index: int = -1

var _pulse: float = 0.0
var _scale: float = 1.0
var _drag_accum: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	_scale = maxf(0.6, get_viewport_rect().size.y / 720.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 4.0)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := radius * _scale
	var col := accent
	col.a = 0.22 + 0.10 * _pulse
	draw_circle(c, r * (1.0 + 0.03 * _pulse), col)
	draw_arc(c, r, 0.0, TAU, 56, Color(accent.r, accent.g, accent.b, 0.85), maxf(2.0, 3.0 * _scale), true)
	# bullet glyph
	var inner := r * 0.52
	draw_circle(c, inner, Color(1, 1, 1, 0.16))
	var cross := r * 0.30
	var w := maxf(3.0, 4.0 * _scale)
	draw_line(c + Vector2(-cross, 0), c + Vector2(cross, 0), Color(1, 1, 1, 0.75), w)
	draw_line(c + Vector2(0, -cross), c + Vector2(0, cross), Color(1, 1, 1, 0.75), w)
	draw_circle(c, r * 0.10, Color(1, 1, 1, 0.85))


## Touch events arrive in screen coordinates; this control draws and measures in its
## own local space, so the hit test converts first.
func _to_local(p: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * p


func _accepts_point(p: Vector2) -> bool:
	var c := size * 0.5
	# generous slop so the thumb does not need pixel accuracy
	return (_to_local(p) - c).length() <= radius * _scale * 1.35


func handle_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if touch_index != -1:
				return false
			if not _accepts_point(t.position):
				return false
			touch_index = t.index
			pressed = true
			_pulse = 1.0
			_drag_accum = Vector2.ZERO
			fire_started.emit()
			queue_redraw()
			return true
		if t.index == touch_index:
			_release()
			return true
		return false
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == touch_index:
			_drag_accum += d.relative
			aim_delta.emit(d.relative * drag_sensitivity)
			return true
	return false


func _release() -> void:
	touch_index = -1
	pressed = false
	fire_stopped.emit()
	queue_redraw()


func reset() -> void:
	if touch_index != -1 or pressed:
		_release()
