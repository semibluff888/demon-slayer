extends Button
## 「大正墨金」button with native mouse, keyboard and controller behavior.
## Menu variant: ink plate, crimson brush sweep on focus, seal ordinal and an
## English caption. Battle variant: bare text with a keycap, never focusable.
## Entry motion only offsets the drawing, so the hit area is live immediately.
const Kit = preload("res://scripts/ui/kit.gd")
const Brush = preload("res://scripts/ui/brush_stroke.gd")
var accent := Color("d02b3f")
var primary: bool = false
var selected: bool = false
var hover_amount: float = 0.0
var arrow: bool = false
## Seal glyph drawn at the left edge (for example 壹).
var kicker: String = ""
## Small English caption under the label.
var subtitle: String = ""
## Keycap shown after battle footer labels (for example Esc).
var hotkey: String = ""
## Tab variant draws an underline instead of a plate.
var tab: bool = false
## Keycap variant for key-binding buttons.
var keycap: bool = false
var portrait_texture: Texture2D
var battle_style: bool = false
var text_only: bool = false
var intro_delay: float = 0.0
var intro_time: float = 0.0
var caption_font: Font
var seal_font: Font
var _band: Node2D

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	if not battle_style:
		_band = Brush.new(float(get_instance_id() % 97) * 0.37)
		_band.show_behind_parent = true
		_band.set_param("taper", 0.5)
		_band.set_param("bristle", 0.45)
		add_child(_band)

func _process(delta: float) -> void:
	var goal := 1.0 if not disabled and (is_hovered() or has_focus() or selected or (toggle_mode and button_pressed)) else 0.0
	var previous := hover_amount
	hover_amount = move_toward(hover_amount, goal, delta * 8.0)
	var entering := intro_time < intro_delay + 0.3
	intro_time += delta
	if entering or not is_equal_approx(previous, hover_amount):
		queue_redraw()

func _intro() -> float:
	return Kit.ease_out((intro_time - intro_delay) / 0.2)

func _font() -> Font:
	return get_theme_font("font")

func _draw() -> void:
	if _band != null and (keycap or tab):
		_band.visible = false
	if battle_style:
		_draw_battle()
	elif keycap:
		_draw_keycap()
	elif tab:
		_draw_tab()
	else:
		_draw_menu()

func _draw_menu() -> void:
	var w := size.x
	var h := size.y
	var enter := _intro()
	var shift := Vector2(-18.0 * (1.0 - enter) + (1.0 if is_pressed() else 0.0), 1.0 if is_pressed() else 0.0)
	var active := hover_amount
	var plate := Kit.chamfer(Rect2(shift, size), minf(10.0, h * 0.24), 6)
	if primary:
		var top := Kit.CRIMSON.lerp(Color("e8445a"), active * 0.6)
		Kit.gradient_fill(self, plate, Color(top, enter), Color(Kit.CRIMSON_DEEP, enter))
		Kit.frame(self, plate, Kit.GOLD.lerp(Kit.GOLD_HI, active), enter, 3.0, 1.4)
	else:
		# The plate thins out as the crimson brush (drawn behind) sweeps in.
		var veil := (1.0 - active * 0.75) * enter
		Kit.gradient_fill(self, plate, Color(Kit.INK_700, 0.72 * veil), Color(Kit.INK_900, 0.82 * veil))
		draw_polyline(Kit.closed(plate), Color(Kit.GOLD, (0.22 + active * 0.5) * enter), 1.0, true)
	if _band != null:
		_band.configure(Rect2(shift.x - 8, 3, w + 16, h - 6), Color(Kit.CRIMSON, 0.92 * enter), 10.0, active, false)
		_band.visible = active > 0.02 and not primary
	if disabled:
		draw_colored_polygon(plate, Color(Kit.INK_900, 0.55))
	var font := _font()
	var font_size := get_theme_font_size("font_size")
	var paper := Kit.PAPER_DIM.lerp(Kit.PAPER, maxf(active, 0.75 if primary else 0.0))
	if disabled:
		paper = Color("6c7280")
	var text_x := 22.0
	if not kicker.is_empty():
		var seal := Rect2(shift.x + 14, (h - minf(30, h - 14)) * 0.5, minf(30, h - 14), minf(30, h - 14))
		Kit.seal(self, seal, seal_font if seal_font != null else font, kicker, Kit.CRIMSON if active > 0.5 or primary else Kit.INK_600,
			Kit.GOLD_HI if active > 0.5 else Kit.PAPER_DIM, enter)
		text_x = seal.end.x - shift.x + 14
	if portrait_texture != null:
		draw_texture_rect(portrait_texture, Rect2(shift + Vector2(9, 5), Vector2(h - 10, h - 10)), false, Color(1, 1, 1, enter))
		text_x = h + 6
	var has_caption := not subtitle.is_empty() and caption_font != null and h >= 50
	var ascent := font.get_ascent(font_size)
	var baseline := (h + ascent - font.get_descent(font_size)) * 0.5 - (7.0 if has_caption else 0.0)
	var centered := kicker.is_empty() and not has_caption and portrait_texture == null
	var text_width := Kit.width(font, text, font_size)
	var tx := (w - text_width) * 0.5 if centered else text_x + active * 6.0
	Kit.text(self, font, text, Vector2(tx, baseline) + shift, font_size, Color(paper, enter), 3)
	if has_caption:
		Kit.tracked(self, caption_font, subtitle, Vector2(tx + 1, baseline + 18) + shift, 11,
			Color(Kit.GOLD_HI if active > 0.5 else Kit.GOLD, (0.55 + active * 0.4) * enter), 2.0)
	if arrow:
		var at := Vector2(w - 22 + active * 4, h * 0.5) + shift
		var tint := Color(Kit.GOLD_HI, (0.35 + active * 0.65) * enter)
		draw_polyline(PackedVector2Array([at + Vector2(-6, -6), at, at + Vector2(-6, 6)]), tint, 2.0, true)
		draw_polyline(PackedVector2Array([at + Vector2(-13, -6), at + Vector2(-7, 0), at + Vector2(-13, 6)]), Color(tint, tint.a * 0.45), 2.0, true)
	if has_focus() and not disabled:
		Kit.brackets(self, Rect2(shift + Vector2(-3, -3), size + Vector2(6, 6)), 8.0, Color(Kit.GOLD_HI, enter), 1.5)

func _draw_tab() -> void:
	var w := size.x
	var h := size.y
	var active := maxf(hover_amount, 1.0 if selected else 0.0)
	var font := _font()
	var font_size := get_theme_font_size("font_size")
	var text_width := Kit.width(font, text, font_size)
	var baseline := (h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	if selected:
		var plate := Kit.chamfer(Rect2(Vector2.ZERO, size), 8, 6)
		Kit.gradient_fill(self, plate, Color(Kit.CRIMSON, 0.95), Color(Kit.CRIMSON_DEEP, 0.95))
		Kit.frame(self, plate, Kit.GOLD, 1.0, 2.0, 1.2)
	else:
		draw_line(Vector2(8, h - 2), Vector2(w - 8, h - 2), Color(Kit.GOLD, 0.25 + hover_amount * 0.6), 1.5, true)
	Kit.text(self, font, text, Vector2((w - text_width) * 0.5, baseline), font_size,
		Kit.PAPER_DIM.lerp(Kit.GOLD_HI if selected else Kit.PAPER, active), 3)
	if has_focus():
		Kit.brackets(self, Rect2(-3, -3, w + 6, h + 6), 7.0, Kit.GOLD_HI, 1.5)

func _draw_keycap() -> void:
	var w := size.x
	var h := size.y
	var active := hover_amount
	var face := Kit.chamfer(Rect2(Vector2.ZERO, size), 5)
	var listening := selected
	Kit.gradient_fill(self, face, Kit.CRIMSON if listening else Kit.INK_600.lightened(0.08 + active * 0.08), Kit.CRIMSON_DEEP if listening else Kit.INK_900)
	draw_polyline(Kit.closed(face), Kit.GOLD_HI if listening or has_focus() else Color(Kit.GOLD, 0.35 + active * 0.4), 1.4 if has_focus() else 1.0, true)
	draw_line(Vector2(5, h - 1.5), Vector2(w - 5, h - 1.5), Color(Kit.INK_900, 0.9), 3.0, true)
	var font := _font()
	var font_size := get_theme_font_size("font_size")
	var label := text
	font_size = Kit.fitted(font, label, font_size, w - 16)
	var baseline := (h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5 - 1
	Kit.text_aligned(self, font, label, Vector2(w * 0.5, baseline), font_size, Kit.GOLD_HI if listening else Kit.PAPER, 1, 3)

func _draw_battle() -> void:
	var w := size.x
	var h := size.y
	var active := maxf(hover_amount, 0.65 if primary else 0.0)
	var color := Kit.GOLD if primary or (toggle_mode and button_pressed) else Kit.PAPER
	if text_only:
		color = Kit.PAPER if active > 0.1 else Color("c4ccd1")
	if disabled:
		color = Color("7b858e")
	elif is_pressed() and not toggle_mode:
		color = color.darkened(0.15)
	var font := _font()
	var font_size := get_theme_font_size("font_size")
	var text_width := Kit.width(font, text, font_size)
	var cap := 0.0
	if not hotkey.is_empty():
		cap = maxf(h - 8, Kit.width(font, hotkey, int((h - 8) * 0.56)) + (h - 8) * 0.6) + 8
	var tx := (w - text_width - cap) * 0.5
	var baseline := (h + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	if not text_only:
		draw_line(Vector2(0, h - 1), Vector2(w - 8, h - 1), Color(Kit.GOLD, 0.22 + active * 0.45), 1, true)
		if active > 0.01:
			draw_line(Vector2(0, 9), Vector2(0, h - 11), Color(Kit.GOLD, active), 2, true)
		if has_focus() and not disabled:
			draw_line(Vector2(0, h - 1), Vector2(w - 8, h - 1), Kit.GOLD, 2, true)
	Kit.text(self, font, text, Vector2(tx, baseline), font_size, color, 3)
	if not hotkey.is_empty():
		Kit.keycap(self, font, hotkey, Vector2(tx + text_width + 8, h * 0.5), h - 8, active > 0.5)
	if text_only and active > 0.01:
		draw_line(Vector2(tx, h - 2), Vector2(tx + text_width, h - 2), Color(Kit.GOLD, active), 1, true)
	if arrow:
		var at := Vector2(w - 25 + hover_amount * 2, h * 0.5)
		draw_line(at - Vector2(12, 0), at, Kit.GOLD, 1, true)
		draw_polyline(PackedVector2Array([at + Vector2(-4, -4), at, at + Vector2(-4, 4)]), Kit.GOLD, 1, true)
	if toggle_mode:
		var at := Vector2(w - 18, h * 0.5)
		draw_arc(at, 6, 0, TAU, 24, Color(Kit.GOLD, 0.8), 1, true)
		if button_pressed:
			draw_circle(at, 3, Kit.GOLD, true, -1, true)
