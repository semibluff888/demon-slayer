extends Button
## Stage list entry: slanted thumbnail, calligraphic name and subtitle.
const Kit = preload("res://scripts/ui/kit.gd")
const Brush = preload("res://scripts/ui/brush_stroke.gd")
var preview: Texture2D
var caption: String = ""
var subtitle: String = ""
var selected: bool = false
var title_font: Font
var body_font: Font
var _band: Node2D

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_color_override("font_color", Color.TRANSPARENT)
	_band = Brush.new(float(get_instance_id() % 53) * 0.71)
	_band.show_behind_parent = true
	_band.set_param("taper", 0.4)
	add_child(_band)

func _draw() -> void:
	var hot := is_hovered() or has_focus()
	var plate := Kit.chamfer(Rect2(Vector2.ZERO, size), 12, 6)
	_band.configure(Rect2(size.x * 0.32, 8, size.x * 0.6, size.y - 16), Color(Kit.CRIMSON, 0.9), 12.0, 1.0)
	_band.visible = selected
	Kit.gradient_fill(self, plate, Color(Kit.INK_600, 0.62 if selected else 0.9), Color(Kit.INK_900, 0.7 if selected else 0.94))
	var thumb_rect := Rect2(6, 6, minf(size.x * 0.42, (size.y - 12) * 16.0 / 9.0), size.y - 12)
	var thumb := Kit.slant(thumb_rect, 14)
	if preview != null:
		Kit.clipped_texture(self, preview, thumb, thumb_rect, Kit.cover_region(preview, thumb_rect.size), false,
			Color.WHITE if selected or hot else Color(0.72, 0.74, 0.8))
	draw_polyline(Kit.closed(thumb), Color(Kit.GOLD, 0.7 if selected else 0.35), 1.0, true)
	var line := Kit.GOLD_HI if selected else (Kit.GOLD if hot else Color(Kit.GOLD, 0.3))
	draw_polyline(Kit.closed(plate), line, 2.0 if selected or hot else 1.0, true)
	var font: Font = title_font if title_font != null else get_theme_font("font")
	var small: Font = body_font if body_font != null else get_theme_font("font")
	var x := thumb_rect.end.x + 18
	var size_title := Kit.fitted(font, caption, 26, size.x - x - 36)
	Kit.text(self, font, caption, Vector2(x, size.y * 0.5 + 4), size_title, Kit.PAPER if selected or hot else Kit.PAPER_DIM, 4)
	if not subtitle.is_empty():
		Kit.text(self, small, subtitle, Vector2(x + 1, size.y * 0.5 + 26), 13, Color(Kit.GOLD_HI if selected else Kit.MUTED, 0.95), 3)
	if selected:
		Kit.diamond(self, Vector2(size.x - 22, size.y * 0.5), 7, Kit.INK_900)
		Kit.diamond(self, Vector2(size.x - 22, size.y * 0.5), 5.5, Kit.GOLD_HI)
	if has_focus():
		Kit.brackets(self, Rect2(-3, -3, size.x + 6, size.y + 6), 9.0, Kit.GOLD_HI, 1.5)
