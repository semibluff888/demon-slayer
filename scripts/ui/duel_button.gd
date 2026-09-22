extends Button
## Illustrated ribbon with native mouse, keyboard and controller behavior.
var accent := Color("9f3549")
var primary: bool = false
var selected: bool = false
var hover_amount: float = 0.0
var arrow: bool = false
var kicker: String = ""
var portrait_texture: Texture2D
var battle_style: bool = false
var text_only: bool = false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)

func _process(delta: float) -> void:
	var goal := 1.0 if not disabled and (is_hovered() or has_focus() or selected or (toggle_mode and button_pressed)) else 0.0
	var previous := hover_amount
	hover_amount = move_toward(hover_amount, goal, delta * 8.0)
	if not is_equal_approx(previous, hover_amount):
		queue_redraw()

func _draw() -> void:
	if battle_style:
		_draw_battle()
		return
	var w := size.x
	var h := size.y
	var active := maxf(hover_amount, 0.72 if primary else 0.0)
	var fill := Color("101b2e").lerp(accent, active * (0.95 if primary else 0.66))
	if disabled:
		fill = Color("161d2b")
	if is_pressed():
		fill = fill.darkened(0.18)
	var shape := PackedVector2Array([Vector2(0, 0), Vector2(w - 12, 0), Vector2(w, h * 0.5), Vector2(w - 12, h), Vector2(0, h)])
	draw_colored_polygon(shape, fill)
	var gold := Color("c8ac7e").lerp(Color("ffebc3"), active * 0.8)
	draw_line(Vector2(1, h - 1), Vector2(w - 14, h - 1), Color(gold, 0.65), 1)
	draw_line(Vector2(0, 0), Vector2(w - 13, 0), Color(gold, 0.30 + active * 0.30), 1)
	if active > 0.02:
		draw_rect(Rect2(0, 9, 3, h - 18), Color(gold, active))
	if has_focus() and not disabled:
		draw_polyline(PackedVector2Array([Vector2(8, 7), Vector2(8, 3), Vector2(23, 3)]), gold, 1.2, true)
		draw_polyline(PackedVector2Array([Vector2(w - 27, h - 4), Vector2(w - 17, h - 4), Vector2(w - 13, h - 9)]), gold, 1.2, true)
	if portrait_texture != null:
		draw_texture_rect(portrait_texture, Rect2(9, 5, h - 10, h - 10), false)
	if arrow:
		var at := Vector2(w - 27 + hover_amount * 3, h * 0.5)
		draw_line(at - Vector2(12, 0), at, gold, 1.2, true)
		draw_polyline(PackedVector2Array([at + Vector2(-5, -4), at, at + Vector2(-5, 4)]), gold, 1.2, true)
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var tx := (w - text_width) * 0.5 + (15.0 if portrait_texture != null else 0.0)
	draw_string(font, Vector2(tx, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("767f91") if disabled else Color("f5ead7"))
	if not kicker.is_empty():
		draw_string(font, Vector2(21, h * 0.5 + 5), kicker, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(gold, 0.7))

func _draw_battle() -> void:
	var w := size.x
	var h := size.y
	var active := maxf(hover_amount, 0.65 if primary else 0.0)
	var gold := Color("d8c397")
	var paper := Color("f6f2e8")
	var color := gold if primary or (toggle_mode and button_pressed) else paper
	if text_only:
		color = paper if active > 0.1 else Color("c4ccd1")
	if disabled:
		color = Color("7b858e")
	elif is_pressed() and not toggle_mode:
		color = color.darkened(0.15)
	if not text_only:
		draw_line(Vector2(0, h - 1), Vector2(w - 8, h - 1), Color(gold, 0.22 + active * 0.45), 1, true)
		draw_line(Vector2(w - 8, h - 1), Vector2(w, h - 9), Color(gold, 0.22 + active * 0.45), 1, true)
		if active > 0.01:
			draw_line(Vector2(0, 9), Vector2(0, h - 11), Color(gold, active), 2, true)
		if has_focus() and not disabled:
			draw_line(Vector2(0, h - 1), Vector2(w - 8, h - 1), gold, 2, true)
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var tx := 14.0 if toggle_mode else (w - text_width) * 0.5
	draw_string_outline(font, Vector2(tx, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(0.025, 0.045, 0.07, 0.8))
	draw_string(font, Vector2(tx, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	if text_only and active > 0.01:
		draw_line(Vector2(tx, h - 2), Vector2(tx + text_width, h - 2), Color(gold, active), 1, true)
	if arrow:
		var at := Vector2(w - 25 + hover_amount * 2, h * 0.5)
		draw_line(at - Vector2(12, 0), at, gold, 1, true)
		draw_polyline(PackedVector2Array([at + Vector2(-4, -4), at, at + Vector2(-4, 4)]), gold, 1, true)
	if toggle_mode:
		var at := Vector2(w - 18, h * 0.5)
		draw_arc(at, 6, 0, TAU, 24, Color(gold, 0.8), 1, true)
		if button_pressed:
			draw_circle(at, 3, gold, true, -1, true)
