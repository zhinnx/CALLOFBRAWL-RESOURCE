## CALLOFBRAWL — touch look pad.
##
## Owns ONE touch index and converts drags into look rotation. It sits between the
## UI buttons and the fire button, so any finger that lands on a button is ignored
## here (the buttons are Controls laid over this node and consume the event first).
class_name CBTouchLookArea
extends Control

signal look_delta(relative: Vector2)

@export var sensitivity: float = 0.42
@export var ads_multiplier: float = 0.55

var touch_index: int = -1
var aiming: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func handle_touch(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if touch_index != -1:
				return false
			touch_index = t.index
			return true
		if t.index == touch_index:
			touch_index = -1
			return true
		return false
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == touch_index:
			var mult = sensitivity * (ads_multiplier if aiming else 1.0)
			look_delta.emit(d.relative * mult)
			return true
	return false


func reset() -> void:
	touch_index = -1
