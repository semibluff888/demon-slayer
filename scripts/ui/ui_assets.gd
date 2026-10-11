extends RefCounted
## Lazily built UI resources owned by the visual catalog: rasterized SVG control
## icons, generated textures and the native-control Theme. Nothing is cached in
## static variables, so every texture is released with its owner.
const Kit = preload("res://scripts/ui/kit.gd")
## Icons rasterize at 3x and report their 1x size, staying crisp up to 4K.
const SCALE := 3.0
const SVG := {
	"toggle_off": '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="26" viewBox="0 0 50 26"><rect x="1.5" y="3.5" width="47" height="19" rx="9.5" fill="#0c1019" stroke="#9a7332" stroke-width="1.4"/><path d="M6 13h38" stroke="#2c3448" stroke-width="1"/><circle cx="13.5" cy="13" r="7.2" fill="#3a4152" stroke="#c9bfa8" stroke-width="1"/></svg>',
	"toggle_on": '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="26" viewBox="0 0 50 26"><rect x="1.5" y="3.5" width="47" height="19" rx="9.5" fill="#7c1222" stroke="#e0b460" stroke-width="1.6"/><path d="M8 9.5h22" stroke="#d02b3f" stroke-width="1.4" stroke-linecap="round"/><circle cx="36.5" cy="13" r="8.2" fill="#ffe9b0" stroke="#9a7332" stroke-width="1.2"/><path d="M36.5 8.6l4.4 4.4-4.4 4.4-4.4-4.4z" fill="#d02b3f"/></svg>',
	"grabber": '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22"><path d="M11 1.5L20.5 11 11 20.5 1.5 11z" fill="#e0b460" stroke="#06080d" stroke-width="1.8"/><path d="M11 6l5 5-5 5-5-5z" fill="#ffe9b0"/></svg>',
	"grabber_hi": '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22"><path d="M11 0.8L21.2 11 11 21.2 0.8 11z" fill="#ffe9b0" stroke="#06080d" stroke-width="1.6"/><path d="M11 5.5l5.5 5.5-5.5 5.5-5.5-5.5z" fill="#d02b3f"/></svg>',
	"arrow": '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M3 5.5l5 5 5-5" fill="none" stroke="#e0b460" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
	"radio_on": '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M8 1.5L14.5 8 8 14.5 1.5 8z" fill="none" stroke="#e0b460" stroke-width="1.3"/><path d="M8 4.8L11.2 8 8 11.2 4.8 8z" fill="#ffe9b0"/></svg>',
	"radio_off": '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M8 1.5L14.5 8 8 14.5 1.5 8z" fill="none" stroke="#9a7332" stroke-width="1.1" opacity="0.7"/></svg>',
	"check_on": '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20"><rect x="2" y="2" width="16" height="16" rx="2" fill="#7c1222" stroke="#e0b460" stroke-width="1.4"/><path d="M5.5 10.2l3 3 6-6.5" fill="none" stroke="#ffe9b0" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
	"check_off": '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20"><rect x="2" y="2" width="16" height="16" rx="2" fill="#0c1019" stroke="#9a7332" stroke-width="1.2"/></svg>',
}
var _icons: Dictionary = {}
var _white: ImageTexture
var _glow: GradientTexture2D

func icon(id: String, dimmed: bool = false) -> Texture2D:
	var key := id + (":dim" if dimmed else "")
	if _icons.has(key):
		return _icons[key]
	var image := Image.new()
	var source: String = SVG.get(id, SVG.arrow)
	if dimmed:
		source = source.replace("<svg ", '<svg opacity="0.45" ')
	if image.load_svg_from_string(source, SCALE) != OK:
		image = Image.create(3, 3, false, Image.FORMAT_RGBA8)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(roundi(image.get_width() / SCALE), roundi(image.get_height() / SCALE)))
	_icons[key] = texture
	return texture

## 1x1 white texture, so shaders on polygons always receive UVs.
func white() -> Texture2D:
	if _white == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(image)
	return _white

## Soft radial falloff used for impact cores, embers and blooms.
func glow() -> Texture2D:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0)])
		gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 128
		_glow.height = 128
	return _glow

static func _box(fill: Color, border: Color = Color.TRANSPARENT, widths: Array = [0, 0, 0, 0], margins: Array = [12, 6, 12, 6], radius: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.border_width_left = widths[0]
	box.border_width_top = widths[1]
	box.border_width_right = widths[2]
	box.border_width_bottom = widths[3]
	box.content_margin_left = margins[0]
	box.content_margin_top = margins[1]
	box.content_margin_right = margins[2]
	box.content_margin_bottom = margins[3]
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	return box

## Theme for every native control the menus still use (toggles, sliders,
## dropdowns, popups, scrollbars, tooltips and plain labels).
func build_theme(body_font: Font, title_font: Font) -> Theme:
	var theme := Theme.new()
	theme.default_font = body_font
	theme.default_font_size = 18
	var paper := Kit.PAPER
	var dim := Kit.PAPER_DIM
	# Labels
	theme.set_color("font_color", "Label", paper)
	theme.set_color("font_shadow_color", "Label", Color(Kit.INK_900, 0.6))
	theme.set_constant("shadow_offset_y", "Label", 2)
	# Toggle switches
	for state in ["normal", "pressed", "disabled", "hover_pressed"]:
		theme.set_stylebox(state, "CheckButton", _box(Color.TRANSPARENT, Color.TRANSPARENT, [0, 0, 0, 0], [12, 4, 10, 4]))
	theme.set_stylebox("hover", "CheckButton", _box(Color(Kit.INK_600, 0.55), Color(Kit.GOLD, 0.25), [0, 0, 0, 1], [12, 4, 10, 4]))
	theme.set_stylebox("hover_pressed", "CheckButton", _box(Color(Kit.INK_600, 0.55), Color(Kit.GOLD, 0.25), [0, 0, 0, 1], [12, 4, 10, 4]))
	theme.set_stylebox("focus", "CheckButton", _box(Color(Kit.CRIMSON_DEEP, 0.28), Kit.GOLD, [2, 0, 0, 1], [12, 4, 10, 4], 0))
	for state in ["checked", "checked_mirrored"]:
		theme.set_icon(state, "CheckButton", icon("toggle_on"))
	for state in ["unchecked", "unchecked_mirrored"]:
		theme.set_icon(state, "CheckButton", icon("toggle_off"))
	for state in ["checked_disabled", "checked_disabled_mirrored"]:
		theme.set_icon(state, "CheckButton", icon("toggle_on", true))
	for state in ["unchecked_disabled", "unchecked_disabled_mirrored"]:
		theme.set_icon(state, "CheckButton", icon("toggle_off", true))
	for state in ["font_color", "font_pressed_color"]:
		theme.set_color(state, "CheckButton", dim)
	for state in ["font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "CheckButton", paper)
	theme.set_color("font_disabled_color", "CheckButton", Color(dim, 0.4))
	theme.set_constant("h_separation", "CheckButton", 12)
	# Check boxes
	theme.set_icon("checked", "CheckBox", icon("check_on"))
	theme.set_icon("unchecked", "CheckBox", icon("check_off"))
	theme.set_stylebox("focus", "CheckBox", _box(Color.TRANSPARENT, Kit.GOLD, [0, 0, 0, 1]))
	# Sliders
	var track := _box(Color(Kit.INK_900, 0.95), Color(Kit.GOLD_LO, 0.8), [1, 1, 1, 1], [0, 3, 0, 3], 2)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", _box(Kit.GOLD_LO, Color.TRANSPARENT, [0, 0, 0, 0], [0, 3, 0, 3], 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(Kit.GOLD, Color.TRANSPARENT, [0, 0, 0, 0], [0, 3, 0, 3], 2))
	theme.set_icon("grabber", "HSlider", icon("grabber"))
	theme.set_icon("grabber_highlight", "HSlider", icon("grabber_hi"))
	theme.set_icon("grabber_disabled", "HSlider", icon("grabber", true))
	theme.set_stylebox("focus", "HSlider", _box(Color.TRANSPARENT, Color(Kit.GOLD, 0.8), [0, 0, 0, 1], [0, 0, 0, 0], 0))
	# Dropdowns
	var field := _box(Color(Kit.INK_800, 0.96), Color(Kit.GOLD_LO, 0.85), [1, 1, 1, 1], [14, 6, 30, 6], 2)
	var field_hover := _box(Color(Kit.INK_600, 0.98), Kit.GOLD, [1, 1, 1, 1], [14, 6, 30, 6], 2)
	theme.set_stylebox("normal", "OptionButton", field)
	theme.set_stylebox("hover", "OptionButton", field_hover)
	theme.set_stylebox("pressed", "OptionButton", _box(Color(Kit.CRIMSON_DEEP, 0.9), Kit.GOLD, [1, 1, 1, 1], [14, 6, 30, 6], 2))
	theme.set_stylebox("disabled", "OptionButton", _box(Color(Kit.INK_800, 0.6), Color(Kit.LINE, 0.8), [1, 1, 1, 1], [14, 6, 30, 6], 2))
	theme.set_stylebox("focus", "OptionButton", _box(Color.TRANSPARENT, Kit.GOLD_HI, [2, 2, 2, 2], [14, 6, 30, 6], 2))
	theme.set_icon("arrow", "OptionButton", icon("arrow"))
	theme.set_constant("arrow_margin", "OptionButton", 10)
	for state in ["font_color", "font_pressed_color"]:
		theme.set_color(state, "OptionButton", paper)
	for state in ["font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(state, "OptionButton", Kit.GOLD_HI)
	theme.set_color("font_disabled_color", "OptionButton", Color(dim, 0.45))
	theme.set_font("font", "OptionButton", body_font)
	# Popup menus (dropdown lists)
	var popup := _box(Color(Kit.INK_800, 0.985), Kit.GOLD_LO, [1, 1, 1, 1], [6, 6, 6, 6], 2)
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 10
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", _box(Color(Kit.CRIMSON_DEEP, 0.95), Color(Kit.GOLD, 0.7), [2, 0, 0, 0], [10, 4, 10, 4], 0))
	theme.set_stylebox("separator", "PopupMenu", _box(Color(Kit.GOLD_LO, 0.4), Color.TRANSPARENT, [0, 0, 0, 0], [0, 1, 0, 1], 0))
	theme.set_color("font_color", "PopupMenu", dim)
	theme.set_color("font_hover_color", "PopupMenu", Kit.GOLD_HI)
	theme.set_color("font_disabled_color", "PopupMenu", Color(dim, 0.4))
	theme.set_constant("v_separation", "PopupMenu", 10)
	theme.set_constant("item_start_padding", "PopupMenu", 10)
	theme.set_constant("item_end_padding", "PopupMenu", 14)
	theme.set_icon("radio_checked", "PopupMenu", icon("radio_on"))
	theme.set_icon("radio_unchecked", "PopupMenu", icon("radio_off"))
	theme.set_icon("checked", "PopupMenu", icon("check_on"))
	theme.set_icon("unchecked", "PopupMenu", icon("check_off"))
	theme.set_font("font", "PopupMenu", body_font)
	theme.set_font_size("font_size", "PopupMenu", 18)
	# Scrollbars
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, _box(Color(Kit.INK_900, 0.55), Color.TRANSPARENT, [0, 0, 0, 0], [3, 3, 3, 3], 3))
		theme.set_stylebox("scroll_focus", bar, _box(Color(Kit.INK_900, 0.55), Color.TRANSPARENT, [0, 0, 0, 0], [3, 3, 3, 3], 3))
		theme.set_stylebox("grabber", bar, _box(Color(Kit.GOLD_LO, 0.8), Color.TRANSPARENT, [0, 0, 0, 0], [3, 3, 3, 3], 3))
		theme.set_stylebox("grabber_highlight", bar, _box(Kit.GOLD, Color.TRANSPARENT, [0, 0, 0, 0], [3, 3, 3, 3], 3))
		theme.set_stylebox("grabber_pressed", bar, _box(Kit.GOLD_HI, Color.TRANSPARENT, [0, 0, 0, 0], [3, 3, 3, 3], 3))
	# Tooltips
	theme.set_stylebox("panel", "TooltipPanel", _box(Color(Kit.INK_800, 0.97), Kit.GOLD_LO, [1, 1, 1, 1], [10, 6, 10, 6], 2))
	theme.set_color("font_color", "TooltipLabel", paper)
	theme.set_font("font", "TooltipLabel", body_font)
	theme.set_font_size("font_size", "TooltipLabel", 15)
	# Plain buttons fall back to a quiet lacquer style.
	theme.set_stylebox("normal", "Button", field)
	theme.set_stylebox("hover", "Button", field_hover)
	theme.set_stylebox("pressed", "Button", _box(Color(Kit.CRIMSON_DEEP, 0.9), Kit.GOLD, [1, 1, 1, 1]))
	theme.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, Kit.GOLD_HI, [2, 2, 2, 2]))
	theme.set_stylebox("disabled", "Button", _box(Color(Kit.INK_800, 0.6), Color(Kit.LINE, 0.8), [1, 1, 1, 1]))
	theme.set_font("font", "Button", title_font)
	return theme
