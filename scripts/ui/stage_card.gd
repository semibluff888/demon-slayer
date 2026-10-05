extends Button
var preview: Texture2D
var caption: String = ""
var selected: bool = false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111d30"))
	if preview != null:
		var source := Rect2(Vector2.ZERO, preview.get_size())
		var target := Rect2(4, 4, size.x - 8, size.y - 64)
		var wanted := target.size.x / target.size.y
		if source.size.x / source.size.y > wanted:
			source.size.x = source.size.y * wanted
			source.position.x = (preview.get_width() - source.size.x) * 0.5
		draw_texture_rect_region(preview, target, source)
	var tint := Color("f1d8a6") if selected else Color("728096")
	draw_rect(Rect2(0, size.y - 60, size.x, 60), Color("a33e55") if selected else Color("111d30"))
	draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), tint, false, 3 if selected or has_focus() else 1)
	var font := get_theme_font("font")
	draw_string(font, Vector2(22, size.y - 21), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("fff1d3"))
	if selected:
		draw_string(font, Vector2(size.x - 51, size.y - 22), "●", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tint)
