## CALLOFBRAWL — dynamic crosshair + hit marker + damage direction indicator.
##
## Draws a 4-line dynamic crosshair whose gap follows the real weapon spread, a
## hit marker (with headshot variant), and a red arc pointing towards whoever is
## shooting the player.
class_name CBCrosshair
extends Control

const HIT_TIME := 0.16

var weapon: CBWeaponController
var spread_pixels: float = 8.0
var hit_marker_timer: float = 0.0
var headshot_hit: bool = false
var hit_killed: bool = false
var damage_dirs: Array[Dictionary] = []
var accuracy_ring: float = 0.0
## True while aim assist is actively tracking a visible enemy (drives the HUD hint).
var aim_engaged: bool = false

var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if hit_marker_timer > 0.0:
		hit_marker_timer = maxf(0.0, hit_marker_timer - delta)
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 6.0)
	var keep: Array[Dictionary] = []
	for d in damage_dirs:
		var t: float = float(d.get("time", 0.0)) - delta
		if t > 0.0:
			d["time"] = t
			keep.append(d)
	damage_dirs = keep
	if weapon != null:
		var target := 4.0 + weapon.current_spread() * 5.5
		if weapon.aiming:
			target = 2.0
		spread_pixels = lerpf(spread_pixels, target, minf(1.0, delta * 12.0))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	_draw_damage_dirs(c)
	var col := Color(1, 1, 1, 0.92)
	var gap := spread_pixels
	var len := 9.0
	var w := 2.0
	if weapon != null and weapon.aiming:
		# ADS: thin fine cross + small dot
		col = Color(0.95, 1.0, 0.96, 0.85)
		len = 6.0
		w = 1.5
	draw_line(c + Vector2(0, -gap - len), c + Vector2(0, -gap), col, w)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, w)
	draw_line(c + Vector2(-gap - len, 0), c + Vector2(-gap, 0), col, w)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, w)
	draw_circle(c, 1.6, col)
	# hit marker
	if hit_marker_timer > 0.0:
		var a := hit_marker_timer / HIT_TIME
		var hc := Color(1.0, 0.25, 0.2, a) if not headshot_hit else Color(1.0, 0.85, 0.25, a)
		var r0 := 7.0
		var r1 := 15.0
		var hw := 2.6 if not hit_killed else 3.4
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dir: Vector2 = d.normalized()
			draw_line(c + dir * r0, c + dir * r1, hc, hw)


func _draw_damage_dirs(c: Vector2) -> void:
	for d in damage_dirs:
		var t: float = float(d.get("time", 0.0)) / float(d.get("total", 1.4))
		var angle: float = float(d.get("angle", 0.0))
		var alpha: float = clampf(t, 0.0, 1.0) * 0.75
		var color := Color(1.0, 0.18, 0.14, alpha)
		var radius := minf(size.x, size.y) * 0.24
		var dir := Vector2(sin(angle), -cos(angle))
		var start := c + dir * (radius - 34.0)
		var finish := c + dir * radius
		draw_line(start, finish, color, 5.0)
		draw_colored_polygon(PackedVector2Array([
			c + dir * (radius + 12.0),
			c + dir.rotated(0.28) * (radius - 6.0),
			c + dir.rotated(-0.28) * (radius - 6.0)]), color)


## Called by the gameplay controller when the player's bullet connects.
func show_hit(headshot: bool, killed: bool) -> void:
	hit_marker_timer = HIT_TIME if not killed else HIT_TIME * 1.6
	headshot_hit = headshot
	hit_killed = killed
	_pulse = 1.0


## `angle` is in radians, 0 = straight ahead, clockwise.
func show_damage_from(angle: float) -> void:
	damage_dirs.append({"angle": angle, "time": 1.4, "total": 1.4})
	if damage_dirs.size() > 4:
		damage_dirs.pop_front()
