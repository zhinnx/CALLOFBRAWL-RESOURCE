## CALLOFBRAWL — main menu.
##
## Landscape, touch first: title block on the left, big action buttons on the right,
## animated 3D backdrop (the actual Dust2 map + a rotating character/rifle showcase
## rendered by a SubViewport) so the first screen already looks like the game.
extends Control

const BACKGROUND_SCENE := "res://scenes/menus/menu_backdrop.tscn"

var _title_pulse: float = 0.0
var _font: Font
var _buttons: Array[CBAdaptiveIconButton] = []
var settings_overlay: CBSettingsPanel
var _backdrop: SubViewportContainer
var _fps_timer: float = 0.0
var _credits_visible: bool = false
var _quit_button: CBAdaptiveIconButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = CBTheme.theme()
	_font = ThemeDB.fallback_font
	Game.configure_match()
	Audio.play_music()
	_build_backdrop()
	_build_buttons()
	_build_settings()
	Settings.apply_graphics(get_viewport())


# ---------------------------------------------------------------- 3D backdrop
func _build_backdrop() -> void:
	var container := SubViewportContainer.new()
	container.name = "BackdropContainer"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp := SubViewport.new()
	vp.name = "Backdrop"
	vp.size = Vector2i(960, 540)
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	container.add_child(vp)
	var scene: PackedScene = load(BACKGROUND_SCENE) as PackedScene
	if scene != null:
		vp.add_child(scene.instantiate())
	# dark gradient so text stays readable over the 3D scene
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.025, 0.035, 0.62)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_meta("scrim", true)
	add_child(scrim)


# ---------------------------------------------------------------- buttons
func _build_buttons() -> void:
	var play := _make_button(CBAdaptiveIconButton.Icon.PLAY, "PLAY")
	play.pressed.connect(_on_play)

	var settings := _make_button(CBAdaptiveIconButton.Icon.SETTINGS, "SETTINGS")
	settings.pressed.connect(_on_settings)

	var credits := _make_button(CBAdaptiveIconButton.Icon.SCORE, "CREDITS")
	credits.pressed.connect(_on_credits)

	_quit_button = _make_button(CBAdaptiveIconButton.Icon.EXIT, "EXIT")
	_quit_button.pressed.connect(_on_quit)
	# desktop / web builds may not be allowed to quit; hide the button then
	if OS.get_name() == "Web" or OS.get_name() == "HTML5":
		_quit_button.visible = false


func _make_button(icon_type: int, label: String) -> CBAdaptiveIconButton:
	var b := CBAdaptiveIconButton.new()
	b.icon = icon_type
	b.label = label
	b.radius = 46.0
	b.accent = Color(1, 1, 1, 0.8)
	add_child(b)
	_buttons.append(b)
	return b


func _layout_buttons() -> void:
	var w := size.x
	var h := size.y
	var btn_size := 116.0
	var start_y := h * 0.42
	var gap := 118.0
	var x := w * 0.74
	for i in _buttons.size():
		var b := _buttons[i]
		if not b.visible:
			continue
		b.size = Vector2(btn_size, btn_size)
		b.position = Vector2(x - btn_size * 0.5, start_y + i * gap)
		b.pivot_offset = b.size * 0.5


func _build_settings() -> void:
	settings_overlay = CBSettingsPanel.new()
	settings_overlay.name = "Settings"
	settings_overlay.visible = false
	settings_overlay.closed.connect(func() -> void: Audio.play_music())
	add_child(settings_overlay)


# ---------------------------------------------------------------- actions
func _on_play() -> void:
	Audio.play_ui("ui_click", -6.0)
	Game.start_match()


func _on_settings() -> void:
	Audio.play_ui("ui_click", -6.0)
	settings_overlay.visible = true
	settings_overlay.open()


func _on_credits() -> void:
	Audio.play_ui("ui_click", -6.0)
	_credits_visible = not _credits_visible
	queue_redraw()


func _on_quit() -> void:
	Audio.play_ui("ui_back", -6.0)
	get_tree().quit()


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	_title_pulse += delta
	_layout_buttons()
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# left side callout panels
	var left := w * 0.055
	var top := h * 0.20
	# title
	var t_size := int(clampf(h * 0.13, 54.0, 120.0))
	CBTheme.draw_title(self, _font, "CALLOF", Vector2(left, top), t_size, CBTheme.TEXT)
	CBTheme.draw_title(self, _font, "BRAWL", Vector2(left, top + t_size * 0.95), t_size, CBTheme.ACCENT)
	# animated underline
	var line_w := t_size * 3.1
	draw_rect(Rect2(left, top + t_size * 1.92, line_w * (0.5 + 0.5 * sin(_title_pulse * 1.2) * 0.5 + 0.25), 4), CBTheme.ACCENT)
	CBTheme.draw_text(self, _font, "MOBILE FPS  •  TEAM DEATHMATCH  •  DE_DUST2",
			Vector2(left, top + t_size * 2.25), int(clampf(h * 0.026, 13.0, 22.0)), CBTheme.TEXT_DIM)
	# match settings summary card
	var card := Rect2(left, h * 0.70, w * 0.36, h * 0.20)
	CBTheme.draw_panel(self, card, Color(0.04, 0.05, 0.06, 0.62), 10)
	CBTheme.draw_text(self, _font, "5 v 5", card.position + Vector2(18, 34), 24, CBTheme.TEXT)
	CBTheme.draw_text(self, _font, "FIRST TO %d" % Settings.get_int("score_limit"), card.position + Vector2(18, 62), 15, CBTheme.ACCENT_SOFT)
	CBTheme.draw_text(self, _font, "%d MIN MATCH   •   3s RESPAWN" % int(Settings.get_float("match_minutes")),
			card.position + Vector2(18, 84), 13, CBTheme.TEXT_DIM)
	CBTheme.draw_text(self, _font, "ALPHA", card.position + Vector2(card.size.x - 150, 34), 16, CBTheme.ALPHA_BLUE)
	CBTheme.draw_text(self, _font, "VS", card.position + Vector2(card.size.x - 96, 34), 16, CBTheme.TEXT_DIM)
	CBTheme.draw_text(self, _font, "BRAVO", card.position + Vector2(card.size.x - 74, 34), 16, CBTheme.BRAVO_RED)
	CBTheme.draw_text(self, _font, "WASD / MOUSE ON DESKTOP  •  TOUCH ON MOBILE",
			card.position + Vector2(18, 112), 12, CBTheme.TEXT_DIM)
	# version tag
	CBTheme.draw_text(self, _font, "v1.0  •  GODOT %s" % Engine.get_version_info().get("string", "4"),
			Vector2(left, h - 24), 12, Color(1, 1, 1, 0.35))
	if _credits_visible:
		_draw_credits()


func _draw_credits() -> void:
	var w := minf(760.0, size.x * 0.8)
	var h := minf(420.0, size.y * 0.78)
	var box := Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)
	draw_rect(box, Color(0.03, 0.035, 0.045, 0.96))
	draw_rect(Rect2(box.position, Vector2(box.size.x, 3)), CBTheme.ACCENT)
	var lines := [
		["CALLOFBRAWL", 26, CBTheme.ACCENT],
		["Mobile FPS Team Deathmatch", 15, CBTheme.TEXT_DIM],
		["", 8, CBTheme.TEXT],
		["3D ASSETS (CC-BY 4.0)", 14, CBTheme.TEXT],
		["de_dust2 - CS map — vrchris (Sketchfab)", 13, CBTheme.TEXT_DIM],
		["Army Character 1 — Muhamad Mirza Arrafi (Sketchfab)", 13, CBTheme.TEXT_DIM],
		["AK47 with scope — Wolf Schevelenbos (Sketchfab)", 13, CBTheme.TEXT_DIM],
		["", 8, CBTheme.TEXT],
		["AUDIO", 14, CBTheme.TEXT],
		["All sound effects and music are synthesised at runtime", 13, CBTheme.TEXT_DIM],
		["(no third-party audio files are shipped with the project)", 13, CBTheme.TEXT_DIM],
		["", 8, CBTheme.TEXT],
		["ENGINE: Godot 4 — Compatibility renderer (mobile)", 13, CBTheme.TEXT_DIM],
	]
	var y := box.position.y + 44
	for entry: Array in lines:
		CBTheme.draw_text(self, _font, str(entry[0]), Vector2(box.position.x + 28, y), int(entry[1]), entry[2])
		y += float(entry[1]) + 8.0
