## CALLOFBRAWL — mobile input controller.
##
## Single place where touch gestures are routed to the right control. Every touch
## index is claimed by exactly one control, which is what makes simultaneous
## movement + aiming + firing + reload work:
##
##   * joystick        -> claims its own index
##   * look pad        -> claims its own index
##   * fire button     -> claims its own index (drag while held aims)
##   * action buttons  -> claim their own index (reload / ADS / jump / pause)
##
## Unclaimed touches fall through to the look pad. On desktop the mouse is
## emulated as touch by the project settings, so the same code path works.
class_name CBMobileInputController
extends Node

## Emitted whenever the on-screen controls are re-laid-out (start-up, rotation).
signal layout_changed

var player: CBPlayerController
var hud: CanvasLayer
var aim_assist: CBAimAssist

var joystick: CBVirtualJoystick
var look_area: CBTouchLookArea
var fire_button: CBFireButton
var btn_reload: CBAdaptiveIconButton
var btn_ads: CBAdaptiveIconButton
var btn_jump: CBAdaptiveIconButton
var btn_pause: CBAdaptiveIconButton

## Layout constants in 720p units; every one is multiplied by the viewport scale.
const _EDGE := 14.0
const _STICK_BOX := 300.0
const _STICK_RADIUS := 104.0
const _FIRE_BOX := 220.0
const _FIRE_RADIUS := 84.0
const _BUTTON := 78.0
const _BUTTON_GAP := 12.0
const _ACTION_STACK_GAP := 18.0

var enabled: bool = true
var _scale: float = 1.0
var _sprint_hold: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	tree_exiting.connect(_on_tree_exiting)
	# The controls are 2D nodes parented to a plain Node, so they land in the root
	# canvas layer. The HUD draws in its own CanvasLayer on top of that, which is what
	# we want: the joystick must never be Z-ordered in front of the score/timer.
	_build_controls()
	_layout_controls()
	get_viewport().size_changed.connect(_layout_controls)


## Disconnect from the viewport signal on teardown. `size_changed` belongs to the
## viewport, not to this node, so without this the callback can fire on a freed
## controller during a scene change (restart / main menu) and log an access error.
func _on_tree_exiting() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_layout_controls):
		vp.size_changed.disconnect(_layout_controls)
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _build_controls() -> void:
	joystick = CBVirtualJoystick.new()
	joystick.name = "MoveStick"
	add_child(joystick)

	fire_button = CBFireButton.new()
	fire_button.name = "FireButton"
	add_child(fire_button)

	btn_reload = _make_button("BtnReload", CBAdaptiveIconButton.Icon.RELOAD)
	btn_ads = _make_button("BtnAds", CBAdaptiveIconButton.Icon.ADS)
	btn_ads.toggle_mode = true
	btn_jump = _make_button("BtnJump", CBAdaptiveIconButton.Icon.JUMP)
	btn_pause = _make_button("BtnPause", CBAdaptiveIconButton.Icon.PAUSE)
	btn_pause.radius = 32.0

	# The look pad is the fallback owner of "any touch that is not on a control". It is
	# added LAST so it sits on top of the others in the canvas, but it never steals a
	# touch: `_input` routes by priority and all these Controls ignore the mouse.
	look_area = CBTouchLookArea.new()
	look_area.name = "LookPad"
	look_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(look_area)
	look_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	btn_reload.pressed.connect(_on_reload)
	btn_ads.pressed.connect(_on_ads)
	btn_jump.pressed.connect(_on_jump)
	btn_pause.pressed.connect(_on_pause)

	joystick.changed.connect(_on_move_changed)
	look_area.look_delta.connect(_on_look_delta)
	fire_button.fire_started.connect(_on_fire_started)
	fire_button.fire_stopped.connect(_on_fire_stopped)
	fire_button.aim_delta.connect(_on_aim_drag)
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed("look_sensitivity", Settings.get_value("look_sensitivity"))


func _make_button(node_name: String, icon_type: int) -> CBAdaptiveIconButton:
	var b := CBAdaptiveIconButton.new()
	b.name = node_name
	b.icon = icon_type
	add_child(b)
	return b


## Sizes and positions every control from the live viewport rect. Called on start
## and whenever the window/orientation changes, so the layout adapts to any
## landscape resolution without anchors (the controller is a plain Node so that it
## receives touches in `_input` before any Control can consume them).
func _layout_controls() -> void:
	# `size_changed` also fires while the scene is being torn down (scene change, app
	# going to the background on Android) and before the controls have been built.
	# Touching freed nodes there is an "Invalid access" error, so bail out instead.
	if not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	if joystick == null or fire_button == null or btn_reload == null:
		return
	_scale = clampf(vp.y / 720.0, 0.62, 1.9)
	var s := _scale

	# --- movement stick, bottom-left. SQUARE control whose size is twice the radius,
	#     so the dynamic origin has room and the drawn ring never leaves the box.
	joystick.size = Vector2(_STICK_BOX * s, _STICK_BOX * s)
	joystick.radius = _STICK_RADIUS * s
	joystick.position = Vector2(_EDGE * s, vp.y - _EDGE * s - joystick.size.y)

	# --- fire button, bottom-right, sized to reach with a thumb without covering
	#     anything else.
	fire_button.size = Vector2(_FIRE_BOX * s, _FIRE_BOX * s)
	fire_button.radius = _FIRE_RADIUS * s
	fire_button.position = Vector2(vp.x - _EDGE * s - fire_button.size.x,
			vp.y - _EDGE * s - fire_button.size.y)

	# --- action buttons: a diagonal strip along the right edge, ABOVE the fire button.
	#     Every one of them must stay clear of the fire control: a fire button that
	#     covers ADS/JUMP/PAUSE makes them untouchable (that was the original bug).
	var btn := _BUTTON * s
	var gap := _BUTTON_GAP * s
	var right_x := vp.x - _EDGE * s - btn
	var y := fire_button.position.y - _ACTION_STACK_GAP * s
	var stack := [btn_pause, btn_jump, btn_ads, btn_reload]
	for i in stack.size():
		var c: Control = stack[i]
		var size_i := btn * (0.82 if c == btn_pause else 1.0)
		var x_i := right_x + (btn - size_i) * 0.5
		y -= size_i
		c.size = Vector2(size_i, size_i)
		c.position = Vector2(x_i, y)
		c.pivot_offset = c.size * 0.5
		y -= gap

	# --- keep the ADS/reload strip from colliding with the stick on very short screens
	var lowest_action_x := right_x
	if lowest_action_x - (joystick.position.x + joystick.size.x) < gap:
		# not enough horizontal room (very narrow window): lift the strip instead
		var lift := gap * 2.0
		for c in stack:
			c.position.y -= lift

	if look_area != null:
		look_area.position = Vector2.ZERO
		look_area.size = vp
	layout_changed.emit()


## Rect of the action strip in viewport space, so the HUD can keep its readouts clear
## of the touch controls instead of guessing.
func action_strip_rect() -> Rect2:
	var r := Rect2()
	var first := true
	for c in [btn_pause, btn_jump, btn_ads, btn_reload]:
		if c == null:
			continue
		var cr := Rect2(c.position, c.size)
		r = cr if first else r.merge(cr)
		first = false
	return r


## Rect currently occupied by the movement stick.
func stick_rect() -> Rect2:
	if joystick == null:
		return Rect2()
	return Rect2(joystick.position, joystick.size)


func bind_target(p: CBPlayerController, assist: CBAimAssist) -> void:
	player = p
	aim_assist = assist


# ---------------------------------------------------------------- touch routing
func _input(event: InputEvent) -> void:
	if not enabled or player == null:
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# Gameplay is paused: the pause menu owns input. Still swallow gameplay touches so
	# they cannot leak through to the (invisible) controls.
	if get_tree().paused:
		_consume(event)
		return
	# 1. fixed action buttons
	if btn_pause.handle_touch(event):
		_consume(event)
		return
	if btn_reload.handle_touch(event):
		_consume(event)
		return
	if btn_jump.handle_touch(event):
		_consume(event)
		return
	if btn_ads.handle_touch(event):
		_consume(event)
		return
	# 2. fire control (drag while held aims)
	if fire_button.handle_touch(event):
		_consume(event)
		return
	# 3. movement stick
	if joystick.handle_touch(event):
		_consume(event)
		return
	# 4. look pad for everything else
	if look_area.handle_touch(event):
		_consume(event)
		return


func _consume(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


# ---------------------------------------------------------------- callbacks
func _on_move_changed(value: Vector2, sprinting: bool) -> void:
	if player == null:
		return
	player.set_move_input(value)
	if player.weapon != null and sprinting and value.y < -0.4:
		if player.weapon.aiming:
			player.set_aiming(false)
			btn_ads.toggled_on = false
	player.set_sprinting(sprinting)


func _on_look_delta(relative: Vector2) -> void:
	if player == null:
		return
	var s := Settings.get_float("look_sensitivity")
	# aim assist slow-down is applied through the player so ADS sensitivity also
	# composes correctly (the player multiplies by its own sight scale)
	player.look_scale = aim_assist.sensitivity_multiplier() if aim_assist != null else 1.0
	player.add_look(relative.x * s * 6.0, relative.y * s * 6.0)


func _on_aim_drag(relative: Vector2) -> void:
	# Drag-to-aim: the same finger that fires turns the camera (with assist stickiness).
	_on_look_delta(relative)


func _on_fire_started() -> void:
	if player != null:
		player.set_trigger(true)


func _on_fire_stopped() -> void:
	if player != null:
		player.set_trigger(false)


func _on_reload() -> void:
	if player != null:
		player.request_reload()
	# reloading drops the sight picture (only when a reload actually started)
	if btn_ads != null and btn_ads.toggled_on and player.weapon != null and player.weapon.is_reloading():
		btn_ads.toggled_on = false
		btn_ads.queue_redraw()
		player.set_aiming(false)


func _on_ads() -> void:
	if player != null:
		player.set_aiming(btn_ads.toggled_on)


func _on_jump() -> void:
	if player != null:
		player.request_jump()


func _on_pause() -> void:
	if hud != null and hud.has_method("toggle_pause"):
		hud.call("toggle_pause")


func _on_settings_changed(key: String, _value: Variant) -> void:
	if aim_assist != null and key.begins_with("aim_assist"):
		aim_assist.refresh_settings()
	if look_area != null:
		look_area.sensitivity = Settings.get_float("look_sensitivity")
		# ADS sensitivity is applied by the player (it composes with aim assist), so the
		# look area must NOT scale again or the value would be squared.
		look_area.ads_multiplier = 1.0


# ---------------------------------------------------------------- state
func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if fire_button:
		fire_button.visible = value
	if joystick:
		joystick.visible = value
	for b in [btn_reload, btn_ads, btn_jump, btn_pause]:
		if b:
			b.visible = value
	if not value:
		_reset_all()


## A phone that loses focus (incoming call, notification shade, app switch) never
## delivers the "finger lifted" events, which used to leave the fire button stuck on
## and the character walking. Clear every claimed touch when that happens.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_release_all_touches()
		NOTIFICATION_APPLICATION_PAUSED:
			_release_all_touches()
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_all_touches()


func _release_all_touches() -> void:
	if joystick != null:
		joystick.reset()
	if fire_button != null:
		fire_button.reset()
	if look_area != null:
		look_area.reset()
	for b in [btn_reload, btn_ads, btn_jump, btn_pause]:
		if b != null:
			b.reset()
	if player != null:
		player.set_move_input(Vector2.ZERO)
		player.set_trigger(false)
		player.set_sprinting(false)


## Full reset: clears every claimed touch, every latched button state and the
## movement/trigger/sprint inputs that the player would otherwise keep applying
## while the controls are hidden (pause menu, settings, death, results screen).
func _reset_all() -> void:
	_release_all_touches()
	if btn_ads != null:
		btn_ads.toggled_on = false
	_sprint_hold = false


## Dead player: hide the combat controls but keep the world visible.
func on_player_died() -> void:
	if fire_button:
		fire_button.visible = false
	if joystick:
		joystick.visible = false
	for b in [btn_reload, btn_ads, btn_jump]:
		if b:
			b.visible = false
	_reset_all()


func on_player_respawned() -> void:
	if btn_ads:
		btn_ads.toggled_on = false
	if fire_button:
		fire_button.visible = true
	if joystick:
		joystick.visible = true
	for b in [btn_reload, btn_ads, btn_jump, btn_pause]:
		if b:
			b.visible = true
	_reset_all()
