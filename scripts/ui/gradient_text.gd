extends Node2D
## Display text with an ink outline, a drop shadow and a metallic gradient fill.
## The node origin is the baseline; `align` 0/1/2 = left/center/right of it.
## Use `modulate` for fades and node scale/skew for pops and italics.
const SHADER = preload("res://scripts/ui/shaders/gradient_text.gdshader")
const GOLD_RAMP := [Color("fff3c8"), Color("e8b75a"), Color("8f6326")]
var font: Font
var text: String = ""
var font_size: int = 48
var align: int = 1
var outline: int = 8
var outline_color := Color(0.024, 0.031, 0.051, 0.95)
var shadow := Vector2(0, 5)
var shadow_color := Color(0, 0, 0, 0.5)
var glow_size: int = 0
var glow_color := Color(1, 0.6, 0.2, 0.0)
var fill: Node2D
var gradient: ShaderMaterial

func _init() -> void:
	gradient = ShaderMaterial.new()
	gradient.shader = SHADER
	fill = Node2D.new()
	fill.name = "Fill"
	fill.material = gradient
	fill.draw.connect(_draw_fill)
	add_child(fill)
	set_ramp(GOLD_RAMP)

func set_ramp(colors: Array) -> void:
	gradient.set_shader_parameter("top_color", colors[0])
	gradient.set_shader_parameter("mid_color", colors[1])
	gradient.set_shader_parameter("bottom_color", colors[2])

func set_glint(value: float) -> void:
	gradient.set_shader_parameter("glint", value)

func setup(display_font: Font, value: String, size: int, alignment: int = 1) -> void:
	font = display_font
	text = value
	font_size = size
	align = alignment
	refresh()

func text_width() -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else 0.0

func _start() -> float:
	var measured := text_width()
	return -measured * 0.5 if align == 1 else (-measured if align == 2 else 0.0)

func refresh() -> void:
	if font != null:
		gradient.set_shader_parameter("top", -font.get_ascent(font_size) * 0.86)
		gradient.set_shader_parameter("bottom", font.get_descent(font_size) * 0.4)
		gradient.set_shader_parameter("start", _start())
		gradient.set_shader_parameter("span", maxf(1, text_width()))
	queue_redraw()
	fill.queue_redraw()

func _draw() -> void:
	if font == null or text.is_empty():
		return
	var at := Vector2(_start(), 0)
	if glow_size > 0 and glow_color.a > 0:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glow_size, glow_color)
	if shadow != Vector2.ZERO:
		draw_string_outline(font, at + shadow, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, shadow_color)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, outline_color)

func _draw_fill() -> void:
	if font == null or text.is_empty():
		return
	fill.draw_string(font, Vector2(_start(), 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
