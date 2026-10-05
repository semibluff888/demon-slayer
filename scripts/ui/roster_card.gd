extends Button
var portrait: Texture2D
var cursors: Array[int] = []
var locked: Array[bool] = [false, false]
var accent := Color("ed526b")

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_color_override("font_color", Color.TRANSPARENT)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("162334"))
	if portrait != null:
		draw_texture_rect(portrait, Rect2(3, 3, size.x - 6, size.y - 6), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color("5b6275"), false, 1)
	if is_hovered() or has_focus():
		draw_rect(Rect2(2, 2, size.x - 4, size.y - 4), Color("fff0cf"), false, 2)
	for slot: int in cursors:
		var tint := Color("69dbea") if slot == 0 else Color("f191ae")
		var y := 0.0 if slot == 0 else size.y - 22
		draw_rect(Rect2(0, y, size.x, 22), tint)
		draw_rect(Rect2(1 + slot * 3, 1 + slot * 3, size.x - 2 - slot * 6, size.y - 2 - slot * 6), tint, false, 3)
		draw_string(get_theme_font("font"), Vector2(7, y + 16), ("P%d" % [slot + 1]) + (" ✓" if locked[slot] else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("09121f"))
