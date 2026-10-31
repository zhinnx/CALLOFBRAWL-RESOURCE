## CALLOFBRAWL — in-match HUD.
##
## Draws and routes everything the player needs during a match:
##   * top bar: team scores, match timer, alive counters, kill/death
##   * kill feed (right side) with team colours and headshot markers
##   * bottom bar: health, ammo, weapon name, reload progress
##   * crosshair + hit marker + directional damage indicators (CBCrosshair)
##   * respawn countdown, toast notifications, match end panel with a restart
##     button, pause menu (resume / restart / settings / main menu) and scoreboard
##
## The HUD owns no gameplay logic; it listens to MatchManager / player signals.
class_name CBHudController
extends CanvasLayer

signal pause_toggled(paused: bool)
signal restart_requested
signal menu_requested
signal settings_requested

const TOP_H := 92.0
const BOTTOM_H := 118.0

var player: CBPlayerController
var match_manager: CBMatchManager
var mobile_input: CBMobileInputController

var layer_root: HUDCanvas
var crosshair: CBCrosshair

var _kill_feed: Array[Dictionary] = []
var _kill_feed_life: Array[float] = []
var _toast: String = ""
var _toast_timer: float = 0.0
var _respawn_seconds: float = -1.0
var _paused: bool = false
var _match_over: bool = false
var _result: Dictionary = {}
var _hud_scale: float = 1.0

## Screen area taken by the touch controls (set by the gameplay scene). Readouts are
## laid out around it so nothing ends up underneath a thumb.
var touch_exclusion: Rect2 = Rect2()
var touch_left_block: float = 0.0
## Width reserved by the controls on the right edge (non-zero in left-handed mode).
var touch_right_block: float = 0.0
var _font: Font
var _show_scoreboard_timer: float = 0.0
var _zoom_hint_timer: float = 0.0

var _menu: CBModalMenu


# ---------------------------------------------------------------- setup
func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_hud_scale = clampf(Settings.get_float("hud_scale"), 0.75, 1.4)

	layer_root = HUDCanvas.new()
	layer_root.name = "HUDRoot"
	layer_root.hud = self
	layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer_root.set_offsets_preset(Control.PRESET_FULL_RECT)
	layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer_root)

	crosshair = CBCrosshair.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.set_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_root.add_child(crosshair)

	_menu = CBModalMenu.new()
	_menu.name = "Modal"
	_menu.visible = false
	_menu.restart_pressed.connect(func() -> void:
		_menu.dismiss()
		restart_requested.emit())
	_menu.resume_pressed.connect(func() -> void: toggle_pause())
	_menu.menu_pressed.connect(func() -> void:
		_menu.dismiss()
		menu_requested.emit())
	_menu.settings_pressed.connect(func() -> void: settings_requested.emit())
	add_child(_menu)

	Settings.changed.connect(_on_setting_changed)
	tree_exiting.connect(_on_tree_exiting)


## `Settings` and `Game` are autoloads: they outlive this HUD. Without disconnecting,
## every restart leaves a stale connection behind that (a) fires into a freed node and
## (b) makes the next match's HUD react twice to every kill-feed / setting change.
func _on_tree_exiting() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	if Game.kill_feed.is_connected(_on_kill_feed):
		Game.kill_feed.disconnect(_on_kill_feed)


func bind(p: CBPlayerController, mm: CBMatchManager, input_ctrl: CBMobileInputController) -> void:
	player = p
	match_manager = mm
	mobile_input = input_ctrl
	if player != null:
		player.weapon.hit_confirmed.connect(_on_hit_confirmed)
		player.damaged.connect(_on_player_damaged)
		player.died.connect(_on_player_died)
		player.respawned.connect(_on_player_respawned)
		crosshair.weapon = player.weapon
	if mm != null:
		mm.eliminated.connect(_on_eliminated)
		mm.match_finished.connect(_on_match_finished)
		mm.match_started.connect(_on_match_started)
		mm.respawn_countdown.connect(_on_respawn_countdown)
	Game.kill_feed.connect(_on_kill_feed)


# ---------------------------------------------------------------- events
func _on_hit_confirmed(victim: String, headshot: bool, killed: bool) -> void:
	crosshair.show_hit(headshot, killed)
	if killed:
		push_toast("ELIMINATED %s%s" % [victim.to_upper(), " — HEADSHOT" if headshot else ""])


func _on_player_damaged(_amount: float, attacker_id: String, _headshot: bool) -> void:
	if player == null or crosshair == null:
		return
	var attacker := _find_combatant(attacker_id)
	if attacker == null:
		return
	crosshair.show_damage_from(_bearing_to(attacker.global_position))


## Angle of a world position relative to where the camera looks, measured in the
## screen plane: 0 = straight ahead, +=right, -=left. Uses dot products against the
## flattened forward/right axes so the indicator always points at the shooter.
func _bearing_to(world_pos: Vector3) -> float:
	var fwd := -player.camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var to := world_pos - player.global_position
	to.y = 0.0
	return atan2(to.dot(right), to.dot(fwd))


func _find_combatant(id: String) -> Node3D:
	if match_manager == null:
		return null
	if player != null and player.combatant_id == id:
		return player
	for bot in match_manager.bots:
		if bot.combatant_id == id:
			return bot
	return null


func _on_player_died(_attacker: String, _headshot: bool) -> void:
	_respawn_seconds = Game.respawn_delay
	if mobile_input != null:
		mobile_input.on_player_died()


func _on_player_respawned() -> void:
	_respawn_seconds = -1.0
	# it was hidden on death / match end; without this the player respawns with no
	# crosshair and cannot aim properly
	if crosshair != null and not _match_over:
		crosshair.visible = true
	if mobile_input != null:
		mobile_input.on_player_respawned()
	push_toast("RESPAWNED")


func _on_respawn_countdown(id: String, seconds_left: float) -> void:
	if id == Game.local_combatant_id:
		_respawn_seconds = seconds_left


func _on_eliminated(entry: Dictionary) -> void:
	if str(entry.get("attacker", "")) == str(Settings.get_value("player_name")):
		_show_scoreboard_timer = 1.2


func _on_kill_feed(entry: Dictionary) -> void:
	_kill_feed.append(entry)
	_kill_feed_life.append(5.0)
	if _kill_feed.size() > 6:
		_kill_feed.pop_front()
		_kill_feed_life.pop_front()


func _on_match_started() -> void:
	_match_over = false
	_result = {}
	push_toast("MATCH START — FIRST TO %d" % Game.score_limit)


func _on_match_finished(result: Dictionary) -> void:
	_match_over = true
	_result = result
	_respawn_seconds = -1.0
	if mobile_input != null:
		mobile_input.set_enabled(false)
	crosshair.visible = false
	_open_results()


# ---------------------------------------------------------------- process
func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
	for i in _kill_feed_life.size():
		_kill_feed_life[i] = maxf(0.0, _kill_feed_life[i] - delta)
	while _kill_feed_life.size() > 0 and _kill_feed_life[0] <= 0.0:
		_kill_feed_life.pop_front()
		_kill_feed.pop_front()
	if _show_scoreboard_timer > 0.0:
		_show_scoreboard_timer -= delta
	layer_root.queue_redraw()
	# keep the crosshair in sync with the current weapon
	if player != null and crosshair.weapon != player.weapon:
		crosshair.weapon = player.weapon


func push_toast(text: String) -> void:
	_toast = text
	_toast_timer = 2.4


func on_player_damaged_from(world_pos: Vector3) -> void:
	if player == null or crosshair == null:
		return
	crosshair.show_damage_from(_bearing_to(world_pos))


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "hud_scale":
		_hud_scale = clampf(Settings.get_float("hud_scale"), 0.75, 1.4)


# ---------------------------------------------------------------- modal
func _open_results() -> void:
	_menu.open_results(_result)
	_menu.visible = true


func toggle_pause() -> void:
	if _match_over:
		return
	set_paused(not _paused)


func set_paused(value: bool) -> void:
	_paused = value
	get_tree().paused = value
	if mobile_input != null:
		mobile_input.set_enabled(not value)
	if value:
		_menu.open_pause()
		_menu.visible = true
	else:
		_menu.visible = false
		crosshair.visible = not _match_over
		if mobile_input != null:
			mobile_input.set_enabled(true)
	pause_toggled.emit(value)


func is_paused() -> bool:
	return _paused


## Hides the pause buttons while the settings overlay is in front of them.
func hide_pause_menu() -> void:
	if _menu != null:
		_menu.visible = false


## Brings the pause menu back after the settings overlay closes.
func restore_pause_menu() -> void:
	if _menu == null or _match_over:
		return
	if _paused:
		_menu.open_pause()
		_menu.visible = true


## Closes the in-match settings overlay if it is open; returns true when it did.
## The match stays paused and the pause menu becomes available again.
func close_settings_overlay() -> bool:
	for child in get_children():
		var panel := child as CBSettingsPanel
		if panel != null and panel.visible:
			panel.visible = false
			if _paused:
				_menu.open_pause()
				_menu.visible = true
			return true
	return false


func toggle_scoreboard(value: bool) -> void:
	_show_scoreboard_timer = 999.0 if value else 0.0


# ---------------------------------------------------------------- keyboard
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE or key == KEY_P:
		if close_settings_overlay():
			get_viewport().set_input_as_handled()
			return
		if not _match_over:
			toggle_pause()
			get_viewport().set_input_as_handled()
	elif key == KEY_TAB:
		toggle_scoreboard(true)
	elif key == KEY_R and _match_over:
		restart_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.is_pressed():
		if (event as InputEventKey).keycode == KEY_TAB:
			toggle_scoreboard(false)


# ---------------------------------------------------------------- painting
## All HUD drawing happens here (child Control of the CanvasLayer).
class HUDCanvas extends Control:
	var hud: CBHudController

	func _draw() -> void:
		if hud == null:
			return
		hud.paint(self)


## Paints top bar, feed, bottom bar, respawn overlay, scoreboard.
func paint(canvas: Control) -> void:
	var ci: CanvasItem = canvas
	var vp := canvas.size
	var s := _hud_scale * maxf(0.75, vp.y / 720.0)
	_paint_top(ci, vp, s)
	_paint_kill_feed(ci, vp, s)
	_paint_bottom(ci, vp, s)
	_paint_toast(ci, vp, s)
	_paint_respawn(ci, vp, s)
	if _show_scoreboard_timer > 0.0 and not _match_over:
		_paint_scoreboard(ci, vp, s, 0.85)


func _paint_top(ci: CanvasItem, vp: Vector2, s: float) -> void:
	var w := vp.x
	var bar := Rect2(0, 0, w, TOP_H * s)
	ci.draw_rect(bar, Color(0.03, 0.04, 0.05, 0.55))
	ci.draw_rect(Rect2(0, TOP_H * s - 2.0, w, 2.0), Color(CBTheme.ACCENT.r, CBTheme.ACCENT.g, CBTheme.ACCENT.b, 0.35))
	# score block
	var alpha_score := Game.alpha_score
	var bravo_score := Game.bravo_score
	var fs := int(40 * s)
	var score_w := 210.0 * s
	var centre := Vector2(w * 0.5, 26.0 * s)
	CBTheme.draw_text(ci, _font, str(alpha_score), centre + Vector2(-score_w * 0.5, 0), fs,
			CBTheme.ALPHA_BLUE, HORIZONTAL_ALIGNMENT_RIGHT, score_w * 0.5)
	CBTheme.draw_text(ci, _font, str(bravo_score), centre + Vector2(score_w * 0.5, 0), fs,
			CBTheme.BRAVO_RED, HORIZONTAL_ALIGNMENT_LEFT, score_w * 0.5)
	CBTheme.draw_text(ci, _font, "/ %d" % Game.score_limit, centre + Vector2(0, 0), int(15 * s),
			CBTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 120.0 * s)
	# timer
	var t := 0.0
	if match_manager != null:
		t = match_manager.time_left
	var mm := int(t) / 60
	var ss := int(t) % 60
	var timer_text := "%02d:%02d" % [mm, ss]
	var urgent := t <= 30.0
	CBTheme.draw_text(ci, _font, timer_text, centre + Vector2(0, 34.0 * s), int(26 * s),
			Color(1, 0.35, 0.3) if urgent else CBTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 200.0 * s)
	CBTheme.draw_text(ci, _font, "TEAM DEATHMATCH", centre + Vector2(0, 54.0 * s), int(12 * s),
			CBTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 220.0 * s)
	# team labels
	CBTheme.draw_text(ci, _font, "ALPHA", Vector2(24 * s, 30 * s), int(18 * s), CBTheme.ALPHA_BLUE)
	CBTheme.draw_text(ci, _font, "BRAVO", Vector2(w - 120 * s, 30 * s), int(18 * s), CBTheme.BRAVO_RED)
	if match_manager != null:
		CBTheme.draw_text(ci, _font, "%d alive" % match_manager.alpha_alive(), Vector2(24 * s, 52 * s), int(13 * s), CBTheme.TEXT_DIM)
		CBTheme.draw_text(ci, _font, "%d alive" % match_manager.bravo_alive(), Vector2(w - 120 * s, 52 * s), int(13 * s), CBTheme.TEXT_DIM)
	# personal stats
	if player != null:
		var stat := Game.get_stat(Game.local_combatant_id)
		var k := int(stat.get("kills", 0))
		var d := int(stat.get("deaths", 0))
		CBTheme.draw_text(ci, _font, "K %d   D %d" % [k, d], Vector2(24 * s, 76 * s), int(15 * s), CBTheme.TEXT)


func _paint_kill_feed(ci: CanvasItem, vp: Vector2, s: float) -> void:
	var y := TOP_H * s + 12.0 * s
	var x := vp.x - 18.0 * s
	for i in range(_kill_feed.size() - 1, -1, -1):
		var e := _kill_feed[i]
		var life := _kill_feed_life[i] if i < _kill_feed_life.size() else 0.0
		var a := clampf(life, 0.0, 1.0)
		if a <= 0.0:
			continue
		var victim := str(e.get("victim", "?"))
		var attacker := str(e.get("attacker", "?"))
		var vteam := int(e.get("victim_team", 0))
		var ateam := int(e.get("attacker_team", 0))
		var hs := " ◎" if bool(e.get("headshot", false)) else ""
		var text := "%s%s  ⟶  %s" % [attacker, hs, victim]
		var fs := int(15 * s)
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(x - width - 14 * s, y, width + 14 * s, 24 * s)
		ci.draw_rect(box, Color(0.02, 0.03, 0.04, 0.55 * a))
		ci.draw_rect(Rect2(box.position, Vector2(3 * s, box.size.y)),
				Color(CBTeam.color_of(ateam).r, CBTeam.color_of(ateam).g, CBTeam.color_of(ateam).b, a))
		CBTheme.draw_text(ci, _font, text, Vector2(box.position.x + 8 * s, y + 17 * s), fs,
				Color(1, 1, 1, a))
		y += 28.0 * s
		# stop the feed above the touch cluster so a growing feed can never run
		# underneath the fire button / action strip on a short screen
		if touch_exclusion.size.y > 0.0 and y + 24 * s > touch_exclusion.position.y - 8.0 * s:
			break


func _paint_bottom(ci: CanvasItem, vp: Vector2, s: float) -> void:
	if player == null:
		return
	var w := vp.x
	var h := vp.y
	var bar := Rect2(0, h - BOTTOM_H * s, w, BOTTOM_H * s)
	ci.draw_rect(bar, Color(0.03, 0.04, 0.05, 0.42))
	# --- readouts share the bottom band with the thumbs, so both of them are
	#     positioned relative to the control cluster instead of the screen edges.
	#     `_right_limit` is the left edge of the fire/action cluster: everything to
	#     the right of it belongs to the controls.
	var right_limit := w - 30.0 * s - touch_right_block
	if touch_exclusion.size.x > 0.0 and touch_exclusion.position.x > w * 0.45:
		right_limit = touch_exclusion.position.x - 16.0 * s
	right_limit = maxf(right_limit, w * 0.35)

	# health bar: on the side that the movement stick is NOT on. In left-handed mode the
	# stick owns the right edge, and anchoring the bar on the left would put it straight
	# on top of the fire button.
	var hp := player.health_component.health_fraction()
	var hw := clampf(w * 0.30, 110.0 * s, 240.0 * s)
	var hx := maxf(28.0 * s, touch_left_block + 16.0 * s)
	if touch_right_block > 0.0:
		hx = maxf(28.0 * s, w - touch_right_block - 16.0 * s - hw)
	hw = clampf(minf(hw, right_limit - 20.0 * s - hx), 90.0 * s, 240.0 * s)
	var hy := h - 52.0 * s
	var hh := 16.0 * s
	ci.draw_rect(Rect2(hx, hy, hw, hh), Color(0, 0, 0, 0.5))
	var hcol := Color(0.35, 0.85, 0.45) if hp > 0.5 else (Color(0.95, 0.75, 0.25) if hp > 0.25 else Color(0.95, 0.3, 0.25))
	ci.draw_rect(Rect2(hx, hy, hw * hp, hh), hcol)
	CBTheme.draw_text(ci, _font, "HEALTH", Vector2(hx, hy - 8 * s), int(12 * s), CBTheme.TEXT_DIM)
	CBTheme.draw_text(ci, _font, str(int(ceil(player.health_component.current_health()))),
			Vector2(hx + hw - 60 * s, hy - 4 * s), int(20 * s), CBTheme.TEXT)

	# ammo counter (right, just left of the fire button so the thumb never hides it)
	var weapon := player.weapon
	if weapon != null:
		var ax := right_limit
		var mag := weapon.magazine
		var reserve := weapon.reserve
		var mag_text := str(mag)
		var fs := int(42 * s)
		var mag_w := _font.get_string_size(mag_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		CBTheme.draw_text(ci, _font, mag_text, Vector2(ax - 74 * s - mag_w, h - 34 * s), fs,
				Color(1, 0.35, 0.3) if mag <= 5 else CBTheme.TEXT)
		CBTheme.draw_text(ci, _font, "/ %d" % reserve, Vector2(ax - 70 * s, h - 34 * s), int(20 * s), CBTheme.TEXT_DIM)
		CBTheme.draw_text(ci, _font, weapon.data.display_name if weapon.data else "AK-47",
				Vector2(ax - 200 * s, h - 58 * s), int(14 * s), CBTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 200 * s)
		if weapon.is_reloading():
			CBTheme.draw_text(ci, _font, "RELOADING", Vector2(ax - 220 * s, h - 78 * s), int(16 * s),
					CBTheme.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_RIGHT, 220 * s)
	# aim assist indicator: dim when idle, accent-coloured while it is actually
	# slowing the crosshair onto an enemy
	if Settings.get_bool("aim_assist") and player.is_alive:
		var tracking := crosshair != null and crosshair.aim_engaged
		var col := Color(1.0, 0.55, 0.18, 0.85) if tracking else Color(1, 1, 1, 0.25)
		var label := "AIM ASSIST ●" if tracking else "AIM ASSIST ON"
		CBTheme.draw_text(ci, _font, label, Vector2(w * 0.5 - 70 * s, h - 14 * s),
				int(11 * s), col, HORIZONTAL_ALIGNMENT_CENTER, 140 * s)


func _paint_toast(ci: CanvasItem, vp: Vector2, s: float) -> void:
	if _toast_timer <= 0.0:
		return
	var a := clampf(_toast_timer / 0.5, 0.0, 1.0)
	var fs := int(20 * s)
	var sz := _font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	# clamp to the viewport: a long notification must not start left of x=0 or run
	# past the right edge on a narrow portrait-ish viewport
	var pos := Vector2(clampf(vp.x * 0.5 - sz.x * 0.5, 18.0 * s, maxf(18.0 * s, vp.x - sz.x - 18.0 * s)), vp.y * 0.30)
	var box := Rect2(pos.x - 18 * s, pos.y - sz.y + 4 * s, sz.x + 36 * s, sz.y + 14 * s)
	ci.draw_rect(box, Color(0.03, 0.04, 0.05, 0.62 * a))
	ci.draw_rect(Rect2(box.position, Vector2(box.size.x, 2 * s)),
			Color(CBTheme.ACCENT.r, CBTheme.ACCENT.g, CBTheme.ACCENT.b, 0.8 * a))
	CBTheme.draw_text(ci, _font, _toast, pos, fs, Color(1, 1, 1, a))


func _paint_respawn(ci: CanvasItem, vp: Vector2, s: float) -> void:
	if _respawn_seconds < 0.0 or _match_over:
		return
	var centre := vp * 0.5
	ci.draw_rect(Rect2(0, centre.y - 90 * s, vp.x, 150 * s), Color(0.02, 0.02, 0.03, 0.45))
	CBTheme.draw_text(ci, _font, "ELIMINATED", centre + Vector2(-vp.x * 0.5, -40 * s), int(34 * s),
			Color(1, 0.35, 0.3), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	CBTheme.draw_text(ci, _font, str(int(ceil(_respawn_seconds))), centre + Vector2(-vp.x * 0.5, 34 * s),
			int(58 * s), CBTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	CBTheme.draw_text(ci, _font, "RESPAWNING", centre + Vector2(-vp.x * 0.5, 52 * s), int(16 * s),
			CBTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _paint_scoreboard(ci: CanvasItem, vp: Vector2, s: float, alpha: float) -> void:
	var rows := Game.scoreboard_rows()
	# The board is centred, but it must not be drawn underneath the thumbs. Fit it
	# into the free band between the stick (left) and the control cluster (right);
	# when that band is narrow the board shrinks instead of overlapping a control.
	var band_left := touch_left_block + 10.0 * s
	var band_right := vp.x - 26.0 * s - touch_right_block
	if touch_exclusion.size.x > 0.0 and touch_exclusion.position.x > vp.x * 0.45:
		band_right = touch_exclusion.position.x - 10.0 * s
	elif touch_exclusion.size.x > 0.0:
		# mirrored layout: the cluster hugs the LEFT edge, so the free band starts past it
		band_left = maxf(band_left, touch_exclusion.position.x + touch_exclusion.size.x + 10.0 * s)
	band_right = maxf(band_right, band_left + 200.0 * s)
	var w := clampf(band_right - band_left, 220.0 * s, minf(620.0 * s, vp.x * 0.86))
	var board_x := clampf(vp.x * 0.5 - w * 0.5, band_left, maxf(band_left, band_right - w))
	# 10 combatants do not fit on a 720-unit-tall phone if the row height is fixed,
	# so the rows are compressed to whatever vertical space the viewport actually has
	var h := minf(vp.y * 0.88, 96.0 * s + 30.0 * s * maxf(10.0, float(rows.size())))
	var row_h := clampf((h - 96.0 * s) / maxf(10.0, float(rows.size())), 14.0 * s, 30.0 * s)
	var box := Rect2(board_x, (vp.y - h) * 0.5, w, h)
	ci.draw_rect(box, Color(0.03, 0.04, 0.05, 0.90 * alpha))
	ci.draw_rect(Rect2(box.position, Vector2(box.size.x, 3 * s)), CBTheme.ACCENT)
	CBTheme.draw_text(ci, _font, "SCOREBOARD", box.position + Vector2(20 * s, 32 * s), int(22 * s),
			CBTheme.TEXT)
	CBTheme.draw_text(ci, _font, "%d — %d" % [Game.alpha_score, Game.bravo_score],
			box.position + Vector2(w - 150 * s, 32 * s), int(22 * s), CBTheme.ACCENT_SOFT,
			HORIZONTAL_ALIGNMENT_RIGHT, 130 * s)
	var y := box.position.y + 60 * s
	var cols := [20.0, 250.0, 330.0, 400.0, 470.0]
	CBTheme.draw_text(ci, _font, "PLAYER", box.position + Vector2(cols[0] * s, y), int(12 * s), CBTheme.TEXT_DIM)
	CBTheme.draw_text(ci, _font, "TEAM", box.position + Vector2(cols[1] * s, y), int(12 * s), CBTheme.TEXT_DIM)
	CBTheme.draw_text(ci, _font, "K", box.position + Vector2(cols[2] * s, y), int(12 * s), CBTheme.TEXT_DIM)
	CBTheme.draw_text(ci, _font, "D", box.position + Vector2(cols[3] * s, y), int(12 * s), CBTheme.TEXT_DIM)
	CBTheme.draw_text(ci, _font, "HS", box.position + Vector2(cols[4] * s, y), int(12 * s), CBTheme.TEXT_DIM)
	y += row_h * 0.85
	for row in rows:
		var rteam := int(row.get("team", 0))
		var name := str(row.get("name", "?"))
		var is_local := bool(row.get("is_local", false))
		if is_local:
			ci.draw_rect(Rect2(box.position.x + 8 * s, y - 18 * s, w - 16 * s, row_h * 0.9),
					Color(CBTheme.ACCENT.r, CBTheme.ACCENT.g, CBTheme.ACCENT.b, 0.12))
		var tcol := CBTeam.color_of(rteam)
		ci.draw_rect(Rect2(box.position.x + 12 * s, y - 14 * s, 4 * s, 18 * s), tcol)
		CBTheme.draw_text(ci, _font, name, box.position + Vector2(cols[0] + 8 * s, y), int(16 * s),
				CBTheme.TEXT if not is_local else CBTheme.ACCENT_SOFT)
		CBTheme.draw_text(ci, _font, CBTeam.short_name(rteam), box.position + Vector2(cols[1] * s, y),
				int(14 * s), tcol)
		CBTheme.draw_text(ci, _font, str(row.get("kills", 0)), box.position + Vector2(cols[2] * s, y),
				int(16 * s), CBTheme.TEXT)
		CBTheme.draw_text(ci, _font, str(row.get("deaths", 0)), box.position + Vector2(cols[3] * s, y),
				int(16 * s), CBTheme.TEXT_DIM)
		CBTheme.draw_text(ci, _font, str(row.get("headshots", 0)), box.position + Vector2(cols[4] * s, y),
				int(16 * s), CBTheme.TEXT_DIM)
		y += row_h
