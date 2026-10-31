## CALLOFBRAWL — settings screen (also works as an in-match overlay).
##
## Every control writes straight into Settings, which persists to user://settings.cfg
## and broadcasts the change to the camera, HUD, audio and renderer.
class_name CBSettingsPanel
extends Control

signal closed

const SENS_MIN := 0.05
const SENS_MAX := 1.5

var _font: Font
var _list: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _values: Dictionary = {}
## Guards against re-entrant rebuilds (a slider callback asking for a full rebuild).
var _rebuilding: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = CBTheme.theme()
	_font = ThemeDB.fallback_font
	resized.connect(_on_resized)
	# the panel may still be 0x0 during _ready; build once a real rect exists
	request_rebuild()


func open() -> void:
	visible = true
	request_rebuild()


func _on_resized() -> void:
	if visible:
		request_rebuild()


func refresh() -> void:
	_build()


func _build() -> void:
	if _rebuilding:
		return
	# A 0x0 rect means the control has not been laid out yet (parent not sized, or the
	# overlay is still inside `_ready`). Building now would size the frame from a zero
	# rect, which is how an invisible settings panel happens; try again next frame.
	if size.x < 1.0 or size.y < 1.0:
		request_rebuild()
		return
	for c in get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
		c.queue_free()
	_values.clear()
	# dim background
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.016, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var avail := size
	if avail.x <= 1.0 or avail.y <= 1.0:
		avail = get_viewport_rect().size
	if avail.x <= 1.0 or avail.y <= 1.0:
		avail = Vector2(1280, 720)
	var frame_size := Vector2(minf(780.0, avail.x * 0.92), minf(650.0, avail.y * 0.92))
	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", CBTheme.style_panel(Color(0.055, 0.062, 0.078, 0.98), 18, 0))
	frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	frame.custom_minimum_size = frame_size
	add_child(frame)
	frame.size = frame_size
	frame.position = (avail - frame_size) * 0.5

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", CBTheme.ACCENT)
	title.position = Vector2(30, 18)
	title.size = Vector2(300, 44)
	frame.add_child(title)

	var close := CBAdaptiveIconButton.new()
	close.icon = CBAdaptiveIconButton.Icon.CLOSE
	close.radius = 26.0
	# anchored to the frame's top-right corner: the frame may be resized later, and
	# anchored children follow it without another layout pass
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.size = Vector2(56, 56)
	close.position = Vector2(-70, 14)
	close.pressed.connect(_on_close)
	frame.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(24, 74)
	_scroll.size = Vector2(frame.size.x - 48, frame.size.y - 96)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)

	_header("CONTROLS")
	_slider("Camera sensitivity", "look_sensitivity", SENS_MIN, SENS_MAX, 0.01)
	_slider("ADS sensitivity", "ads_sensitivity_mult", 0.2, 1.2, 0.01)
	_toggle("Aim assist", "aim_assist")
	_slider("Aim assist strength", "aim_assist_strength", 0.0, 1.0, 0.05)
	_slider("Aim assist radius (m)", "aim_assist_radius", 3.0, 20.0, 0.5)
	_slider("Aim assist cone (°)", "aim_assist_fov", 6.0, 40.0, 1.0)

	_header("GRAPHICS")
	_options("Graphics quality", "graphics_quality", ["Low", "Medium", "High"])
	_slider("Render scale", "render_scale", 0.6, 1.0, 0.05)
	_options("FPS limit", "fps_limit", ["Unlimited", "30", "45", "60", "90", "120"])
	_slider("HUD scale", "hud_scale", 0.8, 1.3, 0.05)
	_toggle("Show FPS", "show_fps")

	_header("AUDIO")
	_slider("Sound volume", "sound_volume", 0.0, 1.0, 0.05)
	_slider("Music volume", "music_volume", 0.0, 1.0, 0.05)

	_header("MATCH")
	_slider_int("Score limit", "score_limit", 10, 100, 5)
	_slider("Match minutes", "match_minutes", 3.0, 20.0, 1.0)
	_slider("Respawn delay (s)", "respawn_delay", 0.0, 8.0, 0.5)
	_options("Bot difficulty", "bot_difficulty", ["Easy", "Normal", "Hard"])

	_header("")
	var reset := Button.new()
	reset.text = "RESET TO DEFAULTS"
	reset.custom_minimum_size = Vector2(0, 54)
	reset.pressed.connect(func() -> void:
		Settings.reset_to_defaults()
		# deferred: never free the button that is currently emitting the signal
		request_rebuild())
	_list.add_child(reset)


## Rebuilds the whole panel on the next idle frame.
func request_rebuild() -> void:
	if _rebuilding:
		return
	_rebuilding = true
	call_deferred("_finish_rebuild", null)


func _finish_rebuild(_unused: Variant) -> void:
	_rebuilding = false
	_build()


func _header(text: String) -> void:
	if text != "":
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", CBTheme.TEXT_DIM)
		l.custom_minimum_size = Vector2(0, 34)
		_list.add_child(l)


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 46)
	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)
	_list.add_child(row)
	return row


func _slider(label_text: String, key: String, mn: float, mx: float, step: float) -> void:
	var row := _row(label_text)
	var val := Label.new()
	val.custom_minimum_size = Vector2(72, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", CBTheme.ACCENT_SOFT)
	val.add_theme_font_size_override("font_size", 16)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = clampf(Settings.get_float(key), mn, mx)
	s.custom_minimum_size = Vector2(230, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.text = _fmt(s.value, step)
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		Settings.save_settings()
		val.text = _fmt(v, step))
	row.add_child(s)
	row.add_child(val)


func _slider_int(label_text: String, key: String, mn: int, mx: int, step: int) -> void:
	var row := _row(label_text)
	var val := Label.new()
	val.custom_minimum_size = Vector2(72, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_color", CBTheme.ACCENT_SOFT)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = clampf(Settings.get_int(key), mn, mx)
	s.custom_minimum_size = Vector2(230, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.text = str(int(s.value))
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, int(v))
		Settings.save_settings()
		val.text = str(int(v)))
	row.add_child(s)
	row.add_child(val)


func _toggle(label_text: String, key: String) -> void:
	var row := _row(label_text)
	var cb := CheckButton.new()
	cb.button_pressed = Settings.get_bool(key)
	cb.custom_minimum_size = Vector2(80, 40)
	cb.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		Settings.save_settings())
	row.add_child(cb)


func _options(label_text: String, key: String, items: Array) -> void:
	var row := _row(label_text)
	var opt := OptionButton.new()
	for i in items.size():
		opt.add_item(str(items[i]), i)
	var current := Settings.get_int(key)
	# FPS limit is stored in real fps, map it to its index
	if key == "fps_limit":
		current = maxi(0, Settings.FPS_LIMITS.find(Settings.get_int("fps_limit")))
	opt.selected = clampi(current, 0, items.size() - 1)
	opt.custom_minimum_size = Vector2(200, 44)
	opt.item_selected.connect(func(idx: int) -> void:
		var value: Variant = idx
		if key == "fps_limit":
			value = Settings.FPS_LIMITS[idx]
		Settings.set_value(key, value)
		Settings.save_settings())
	row.add_child(opt)


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(round(v))
	if step >= 0.1:
		return "%.1f" % v
	return "%.2f" % v


func _on_close() -> void:
	Audio.play_ui("ui_back", -8.0)
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
