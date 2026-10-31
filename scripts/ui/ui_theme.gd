## CALLOFBRAWL — shared procedural UI theme and drawing helpers.
##
## Everything is built at runtime (fonts are the engine's default, rounded panels
## are StyleBoxFlat instances) so the repository needs no binary UI assets while
## still looking like a real game: dark glass panels, orange accent, chunky rounded
## buttons sized for thumbs.
class_name CBTheme
extends RefCounted

const BG_DEEP := Color(0.045, 0.052, 0.066)
const BG_PANEL := Color(0.075, 0.086, 0.106, 0.94)
const BG_CARD := Color(0.11, 0.125, 0.152, 0.96)
const ACCENT := Color(1.0, 0.52, 0.16)
const ACCENT_SOFT := Color(1.0, 0.66, 0.33)
const ALPHA_BLUE := Color(0.36, 0.68, 1.0)
const BRAVO_RED := Color(1.0, 0.42, 0.36)
const TEXT := Color(0.94, 0.95, 0.97)
const TEXT_DIM := Color(0.62, 0.66, 0.72)

static var _theme: Theme


static func style_panel(color: Color = BG_PANEL, radius: int = 16, border: int = 1,
		border_color: Color = Color(1, 1, 1, 0.07)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = border
	sb.border_width_top = border
	sb.border_width_right = border
	sb.border_width_bottom = border
	sb.border_color = border_color
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func style_button(bg: Color, radius: int = 14) -> StyleBoxFlat:
	var sb := style_panel(bg, radius, 0)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


## A single shared Theme for all menus so buttons/labels look consistent.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20

	t.set_stylebox("normal", "Button", style_button(Color(0.16, 0.19, 0.24)))
	t.set_stylebox("hover", "Button", style_button(Color(0.21, 0.25, 0.31)))
	t.set_stylebox("pressed", "Button", style_button(ACCENT * 0.85))
	t.set_stylebox("disabled", "Button", style_button(Color(0.12, 0.13, 0.15)))
	t.set_stylebox("focus", "Button", style_button(Color(0, 0, 0, 0)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_font_size("font_size", "Button", 22)

	t.set_stylebox("panel", "PanelContainer", style_panel())
	t.set_stylebox("panel", "Panel", style_panel())
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 20)

	t.set_stylebox("slider", "HSlider", style_panel(Color(0.2, 0.22, 0.26), 6, 0))
	t.set_stylebox("grabber_area", "HSlider", style_panel(ACCENT, 6, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", style_panel(ACCENT_SOFT, 6, 0))

	var check_off := style_panel(Color(0.18, 0.20, 0.24), 10, 1, Color(1, 1, 1, 0.12))
	var check_on := style_panel(ACCENT, 10, 0)
	t.set_stylebox("normal", "CheckButton", check_off)
	t.set_stylebox("pressed", "CheckButton", check_on)
	t.set_stylebox("hover", "CheckButton", style_panel(Color(0.24, 0.27, 0.32), 10, 0))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_pressed_color", "CheckButton", Color(0.1, 0.08, 0.05))

	var opt := style_panel(Color(0.16, 0.19, 0.24), 10)
	var opt_hl := style_panel(ACCENT, 10)
	t.set_stylebox("normal", "OptionButton", opt)
	t.set_stylebox("hover", "OptionButton", style_panel(Color(0.22, 0.26, 0.32), 10))
	t.set_stylebox("pressed", "OptionButton", opt_hl)
	t.set_stylebox("focus", "OptionButton", style_panel(Color(0, 0, 0, 0), 10))
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_pressed_color", "OptionButton", Color(0.1, 0.08, 0.05))

	t.set_stylebox("panel", "PopupMenu", style_panel(BG_CARD, 10))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_stylebox("separator", "HSeparator", style_panel(Color(1, 1, 1, 0.1), 1, 0))
	_theme = t
	return t


## Large stylised title text drawn with an offset "shadow" so it reads on any map.
static func draw_title(ci: CanvasItem, font: Font, text: String, pos: Vector2, size: int,
		color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(font, pos + Vector2(2, 3), text, align, width, size, Color(0, 0, 0, 0.55))
	ci.draw_string(font, pos, text, align, width, size, color)


static func draw_text(ci: CanvasItem, font: Font, text: String, pos: Vector2, size: int,
		color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	ci.draw_string(font, pos, text, align, width, size, color)


## Draws a rounded translucent panel inset by `margin`.
static func draw_panel(ci: CanvasItem, rect: Rect2, color: Color = BG_PANEL, radius: float = 14.0) -> void:
	ci.draw_rect(rect, color, true)
	# corner accents give the "hard glass" look without a texture
	var s := radius
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55))
	ci.draw_line(rect.position + Vector2(0, s), rect.position + Vector2(0, rect.size.y - s), Color(1, 1, 1, 0.06), 1.0)
