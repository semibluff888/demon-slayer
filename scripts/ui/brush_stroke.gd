extends Node2D
## Dry-brush ink band painted by brush_band.gdshader. The quad may lean
## (`slant` shifts the top edge) and run right-to-left (`flip`); `reveal`
## wipes the stroke in with a ragged front. Purely decorative.
const SHADER = preload("res://scripts/ui/shaders/brush_band.gdshader")
var rect := Rect2(0, 0, 200, 40)
var color := Color("d02b3f")
var slant: float = 0.0
var flip: bool = false
var _white: ImageTexture

func _init(seed_value: float = 0.0) -> void:
	var paint := ShaderMaterial.new()
	paint.shader = SHADER
	material = paint
	set_param("seed", seed_value)
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)

func set_param(parameter: String, value: Variant) -> void:
	(material as ShaderMaterial).set_shader_parameter(parameter, value)

func configure(bounds: Rect2, tint: Color, lean: float = 0.0, reveal: float = 1.0, reversed: bool = false) -> void:
	rect = bounds
	color = tint
	slant = lean
	flip = reversed
	set_param("reveal", reveal)
	queue_redraw()

func set_reveal(value: float) -> void:
	set_param("reveal", clampf(value, 0, 1))

func _draw() -> void:
	if rect.size.x <= 0 or rect.size.y <= 0 or color.a <= 0:
		return
	var points := PackedVector2Array([rect.position + Vector2(slant, 0), Vector2(rect.end.x + slant, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])
	var uvs := PackedVector2Array([Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]) if flip else \
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	draw_polygon(points, PackedColorArray([color, color, color, color]), uvs, _white)
