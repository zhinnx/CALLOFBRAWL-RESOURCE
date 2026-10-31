## CALLOFBRAWL — modal overlay used for the pause menu and the match results.
##
## Big thumb-friendly buttons, works in portrait or landscape, pauses the tree.
class_name CBModalMenu
extends Control

signal resume_pressed
signal restart_pressed
signal menu_pressed
signal settings_pressed

var _title: String = "PAUSED"
var _subtitle: String = ""
var _buttons: Array[Button] = []
var _mode: String = "pause"
var _stats_rows: Array = []
var _winner: int = CBTeam.NONE
var _font: Font
var _panel: Panel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = CBTheme.theme()
	_font = ThemeDB.fallback_font
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", CBTheme.style_panel(Color(0.045, 0.052, 0.066, 0.97), 18, 0))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 520)
	add_child(_panel)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var w := minf(620.0, size.x * 0.86)
	var h := minf(560.0, size.y * 0.9)
	_panel.size = Vector2(w, h)
	_panel.position = (size - _panel.size) * 0.5
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	if _mode == "pause":
		_build_pause()
	else:
		_build_results()


func _make_button(text: String, y: float, height: float, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(_panel.size.x - 80.0, height)
	b.size = Vector2(_panel.size.x - 80.0, height)
	b.position = Vector2(40.0, y)
	b.add_theme_font_size_override("font_size", 24)
	if accent:
		b.add_theme_stylebox_override("normal", CBTheme.style_button(CBTheme.ACCENT * 0.9))
		b.add_theme_stylebox_override("pressed", CBTheme.style_button(CBTheme.ACCENT * 0.7))
		b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	_panel.add_child(b)
	_buttons.append(b)
	return b


func _build_pause() -> void:
	_title = "PAUSED"
	var b_resume := _make_button("RESUME", 120.0, 64.0, true)
	b_resume.pressed.connect(func() -> void: resume_pressed.emit())
	var b_restart := _make_button("RESTART MATCH", 200.0, 60.0)
	b_restart.pressed.connect(func() -> void: restart_pressed.emit())
	var b_settings := _make_button("SETTINGS", 276.0, 60.0)
	b_settings.pressed.connect(func() -> void: settings_pressed.emit())
	var b_menu := _make_button("MAIN MENU", 352.0, 60.0)
	b_menu.pressed.connect(func() -> void: menu_pressed.emit())
	var b_quit := _make_button("QUIT GAME", 442.0, 52.0)
	b_quit.pressed.connect(func() -> void: get_tree().quit())


func _build_results() -> void:
	var b_restart := _make_button("PLAY AGAIN", _panel.size.y - 150.0, 64.0, true)
	b_restart.pressed.connect(func() -> void: restart_pressed.emit())
	var b_menu := _make_button("MAIN MENU", _panel.size.y - 78.0, 56.0)
	b_menu.pressed.connect(func() -> void: menu_pressed.emit())
	queue_redraw()


## Leaves the modal cleanly: un-pauses the tree so the next scene (or the resumed
## match) is not frozen, and hides the overlay.
func dismiss() -> void:
	visible = false
	if get_tree().paused:
		get_tree().paused = false


func open_pause() -> void:
	_mode = "pause"
	_layout()
	queue_redraw()


func open_results(result: Dictionary) -> void:
	_mode = "results"
	_winner = int(result.get("winner", CBTeam.NONE))
	_stats_rows = []
	var stats: Dictionary = result.get("stats", {})
	for id in stats.keys():
		_stats_rows.append(stats[id])
	_stats_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("kills", 0)) > int(b.get("kills", 0)))
	_layout()
	queue_redraw()


func _draw() -> void:
	# dim the paused gameplay behind the panel
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.016, 0.72))
	if _font == null:
		return
	if _mode == "pause":
		_draw_pause()
	else:
		_draw_results()


func _draw_pause() -> void:
	var p := _panel.position
	var w := _panel.size.x
	CBTheme.draw_title(self, _font, "PAUSED", p + Vector2(w * 0.5 - 90, 76), 40, CBTheme.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, 180)
	CBTheme.draw_text(self, _font, "CALLOFBRAWL  •  TEAM DEATHMATCH", p + Vector2(w * 0.5 - 160, 100),
			13, CBTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 320)
	CBTheme.draw_text(self, _font, "%d — %d" % [Game.alpha_score, Game.bravo_score],
			p + Vector2(w * 0.5 - 100, 412), 24, CBTheme.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 200)
	CBTheme.draw_text(self, _font, "SCORE", p + Vector2(w * 0.5 - 60, 430), 11, CBTheme.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, 120)


func _draw_results() -> void:
	var p := _panel.position
	var w := _panel.size.x
	var winner: int = _winner
	var title := "VICTORY" if winner == CBTeam.ALPHA else ("DEFEAT" if winner == CBTeam.BRAVO else "DRAW")
	var color = CBTheme.ACCENT if winner == CBTeam.ALPHA else (CBTheme.BRAVO_RED if winner == CBTeam.BRAVO else CBTheme.TEXT)
	CBTheme.draw_title(self, _font, title, p + Vector2(w * 0.5 - 110, 74), 42, color,
			HORIZONTAL_ALIGNMENT_CENTER, 220)
	CBTheme.draw_text(self, _font, "%s  %d — %d" % [CBTeam.name_of(winner) if winner != CBTeam.NONE else "TIED",
			Game.alpha_score, Game.bravo_score], p + Vector2(w * 0.5 - 160, 104), 18, CBTheme.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, 320)
	# column headers + rows
	var y := 150.0
	var cols := [22.0, 300.0, 380.0, 460.0]
	CBTheme.draw_text(self, _font, "PLAYER", p + Vector2(cols[0] + 20, y), 11, CBTheme.TEXT_DIM)
	CBTheme.draw_text(self, _font, "TEAM", p + Vector2(cols[1], y), 11, CBTheme.TEXT_DIM)
	CBTheme.draw_text(self, _font, "K", p + Vector2(cols[2], y), 11, CBTheme.TEXT_DIM)
	CBTheme.draw_text(self, _font, "D", p + Vector2(cols[3], y), 11, CBTheme.TEXT_DIM)
	y += 20.0
	var rows = _stats_rows.slice(0, 10)
	for row: Dictionary in rows:
		var tcol := CBTeam.color_of(int(row.get("team", 0)))
		draw_rect(Rect2(p.x + cols[0] + 8, y - 12, 3, 16), tcol)
		CBTheme.draw_text(self, _font, str(row.get("name", "?")), p + Vector2(cols[0] + 18, y), 15,
				CBTheme.TEXT if not bool(row.get("is_local", false)) else CBTheme.ACCENT_SOFT)
		CBTheme.draw_text(self, _font, CBTeam.short_name(int(row.get("team", 0))), p + Vector2(cols[1], y), 12, tcol)
		CBTheme.draw_text(self, _font, str(row.get("kills", 0)), p + Vector2(cols[2], y), 15, CBTheme.TEXT)
		CBTheme.draw_text(self, _font, str(row.get("deaths", 0)), p + Vector2(cols[3], y), 15, CBTheme.TEXT_DIM)
		y += 22.0


