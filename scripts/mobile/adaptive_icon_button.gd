## CALLOFBRAWL — round touch button with vector-drawn icon.
##
## Used for reload, ADS, jump, pause and the menu's secondary buttons. Icons are
## drawn with CanvasItem primitives so the project needs no icon textures, and the
## whole thing is a real Control (touch target) with a 96 px minimum size.
class_name CBAdaptiveIconButton
extends Control

signal pressed

enum Icon { RELOAD, ADS, JUMP, PAUSE, PLAY, SETTINGS, EXIT, BACK, MENU, RESTART, CLOSE, SCORE, SOUND, CAMERA, AIM }

@export var icon: Icon = Icon.RELOAD
@export var label: String = ""
@export var accent: Color = Color(1, 1, 1, 0.85)
@export var fill: Color = Color(0.06, 0.07, 0.09, 0.42)
@export var radius: float = 44.0
@export var toggle_mode: bool = false
@export var toggled_on: bool = false

var touch_index: int = -1
var _down: bool = false
var _scale: float = 1.0
var _flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	mouse_entered.connect(func() -> void: queue_redraw())
	_on_resized()


func _on_resized() -> void:
	_scale = maxf(0.6, get_viewport_rect().size.y / 720.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := radius * _scale
	var active := (toggle_mode and toggled_on) or _down
	var bg := fill
	if active:
		bg = Color(accent.r, accent.g, accent.b, 0.35)
	var ring := accent
	ring.a = 0.9 if active else 0.55
	draw_circle(c, r * (1.0 + 0.03 * _flash), bg)
	draw_arc(c, r, 0.0, TAU, 48, ring, maxf(1.8, 2.2 * _scale), true)
	var ink := Color(1, 1, 1, 0.92 if not active else 1.0)
	var u := r * 0.62
	match icon:
		Icon.RELOAD:
			draw_arc(c, u * 0.78, deg_to_rad(-40), deg_to_rad(250), 32, ink, maxf(2.0, 2.6 * _scale), true)
			var tip := c + Vector2(cos(deg_to_rad(-40)), sin(deg_to_rad(-40))) * u * 0.78
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-u * 0.30, -u * 0.20),
					tip + Vector2(u * 0.28, -u * 0.12), tip + Vector2(-u * 0.02, u * 0.34)]), ink)
		Icon.ADS:
			draw_arc(c, u * 0.74, 0.0, TAU, 36, ink, maxf(2.0, 2.6 * _scale), true)
			draw_line(c + Vector2(-u, 0), c + Vector2(-u * 0.35, 0), ink, maxf(2, 2.4 * _scale))
			draw_line(c + Vector2(u * 0.35, 0), c + Vector2(u, 0), ink, maxf(2, 2.4 * _scale))
			draw_line(c + Vector2(0, -u), c + Vector2(0, -u * 0.35), ink, maxf(2, 2.4 * _scale))
			draw_line(c + Vector2(0, u * 0.35), c + Vector2(0, u), ink, maxf(2, 2.4 * _scale))
			draw_circle(c, u * 0.10, ink)
		Icon.JUMP:
			draw_line(c + Vector2(0, u * 0.7), c + Vector2(0, -u * 0.55), ink, maxf(2.2, 2.8 * _scale))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.45, -u * 0.25),
					c + Vector2(u * 0.45, -u * 0.25), c + Vector2(0, -u * 0.85)]), ink)
			draw_line(c + Vector2(-u * 0.6, u * 0.85), c + Vector2(u * 0.6, u * 0.85), ink, maxf(2.0, 2.4 * _scale))
		Icon.PAUSE:
			draw_rect(Rect2(c + Vector2(-u * 0.45, -u * 0.6), Vector2(u * 0.3, u * 1.2)), ink)
			draw_rect(Rect2(c + Vector2(u * 0.15, -u * 0.6), Vector2(u * 0.3, u * 1.2)), ink)
		Icon.PLAY:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.4, -u * 0.65),
					c + Vector2(-u * 0.4, u * 0.65), c + Vector2(u * 0.62, 0)]), ink)
		Icon.SETTINGS:
			draw_arc(c, u * 0.42, 0.0, TAU, 28, ink, maxf(2.0, 2.6 * _scale), true)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * u * 0.55, c + d * u * 0.90, ink, maxf(2.0, 2.6 * _scale))
		Icon.EXIT:
			draw_line(c + Vector2(-u * 0.7, -u * 0.7), c + Vector2(u * 0.7, u * 0.7), ink, maxf(2.4, 3.0 * _scale))
			draw_line(c + Vector2(u * 0.7, -u * 0.7), c + Vector2(-u * 0.7, u * 0.7), ink, maxf(2.4, 3.0 * _scale))
		Icon.CLOSE:
			draw_line(c + Vector2(-u * 0.55, -u * 0.55), c + Vector2(u * 0.55, u * 0.55), ink, maxf(2.0, 2.6 * _scale))
			draw_line(c + Vector2(u * 0.55, -u * 0.55), c + Vector2(-u * 0.55, u * 0.55), ink, maxf(2.0, 2.6 * _scale))
		Icon.BACK:
			draw_line(c + Vector2(u * 0.45, -u * 0.6), c + Vector2(-u * 0.35, 0), ink, maxf(2.2, 2.8 * _scale))
			draw_line(c + Vector2(-u * 0.35, 0), c + Vector2(u * 0.45, u * 0.6), ink, maxf(2.2, 2.8 * _scale))
		Icon.MENU:
			for i in 3:
				var y := -u * 0.55 + i * u * 0.55
				draw_line(c + Vector2(-u * 0.7, y), c + Vector2(u * 0.7, y), ink, maxf(2.2, 2.8 * _scale))
		Icon.RESTART:
			draw_arc(c, u * 0.72, deg_to_rad(30), deg_to_rad(330), 36, ink, maxf(2.2, 2.8 * _scale), true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(u * 0.42, -u * 0.82),
					c + Vector2(u * 0.92, -u * 0.55), c + Vector2(u * 0.35, -u * 0.20)]), ink)
		Icon.SCORE:
			for i in 3:
				var x := -u * 0.55 + i * u * 0.55
				draw_line(c + Vector2(x, -u * 0.55), c + Vector2(x, u * 0.55), ink, maxf(2.0, 2.4 * _scale))
			draw_line(c + Vector2(-u * 0.7, -u * 0.55), c + Vector2(u * 0.7, -u * 0.55), ink, maxf(2.0, 2.4 * _scale))
		Icon.SOUND:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.7, -u * 0.25),
					c + Vector2(-u * 0.3, -u * 0.25), c + Vector2(u * 0.2, -u * 0.7),
					c + Vector2(u * 0.2, u * 0.7), c + Vector2(-u * 0.3, u * 0.25),
					c + Vector2(-u * 0.7, u * 0.25)]), ink)
			draw_arc(c + Vector2(u * 0.25, 0), u * 0.45, deg_to_rad(-50), deg_to_rad(50), 20, ink, maxf(1.8, 2.2 * _scale), true)
		Icon.CAMERA:
			draw_rect(Rect2(c + Vector2(-u * 0.7, -u * 0.35), Vector2(u * 1.4, u * 0.85)), ink, false, maxf(2.0, 2.4 * _scale))
			draw_circle(c + Vector2(0, u * 0.08), u * 0.30, ink)
		Icon.AIM:
			draw_arc(c, u * 0.72, 0.0, TAU, 32, ink, maxf(1.8, 2.2 * _scale), true)
			draw_circle(c, u * 0.16, ink)
	if label != "":
		var font := get_theme_default_font()
		var fs := int(18 * _scale)
		draw_string(font, Vector2(0, size.y - 4 * _scale), label, HORIZONTAL_ALIGNMENT_CENTER,
				size.x, fs, Color(1, 1, 1, 0.75))


func handle_touch(event: InputEvent) -> bool:
	if not is_visible_in_tree():
		return false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if touch_index != -1:
				return false
			if not _accepts(t.position):
				return false
			touch_index = t.index
			_down = true
			_flash = 1.0
			queue_redraw()
			return true
		if t.index == touch_index:
			touch_index = -1
			_down = false
			queue_redraw()
			_activate()
			return true
		return false
	return false


func _accepts(p: Vector2) -> bool:
	var local := p - global_position
	var c := size * 0.5
	return (local - c).length() <= radius * _scale * 1.22


func _activate() -> void:
	if toggle_mode:
		toggled_on = not toggled_on
		pressed.emit()
		queue_redraw()
	else:
		pressed.emit()


## Convenience for keyboard/desktop and menu wiring.
func press() -> void:
	_flash = 1.0
	_activate()
