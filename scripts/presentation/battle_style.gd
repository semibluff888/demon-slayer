class_name BattleStyle
extends RefCounted
## Shared ink, antique-gold and paper treatment, drawn at viewport resolution.
const PAPER := Color("fff0c8")
const GOLD := Color("e6c77f")
const INK := Color("090e1c")
const MUTED := Color("b7bfd0")

static func ink(canvas: CanvasItem, bounds: Rect2, color: Color = Color(0.025, 0.035, 0.06, 0.91)) -> void:
	var points := PackedVector2Array()
	for n in range(15):
		var u := n / 14.0
		points.append(bounds.position + Vector2(u * bounds.size.x, (sin(n * 9.3) * 0.045 + 0.04) * bounds.size.y))
	for n in range(14, -1, -1):
		var u := n / 14.0
		points.append(bounds.position + Vector2(u * bounds.size.x, (0.94 + sin(n * 5.7) * 0.04) * bounds.size.y))
	canvas.draw_colored_polygon(points, color)
	for n in range(5):
		var y := bounds.position.y + bounds.size.y * (0.16 + n * 0.15)
		canvas.draw_line(Vector2(bounds.position.x - 7 - n % 3 * 4, y), Vector2(bounds.end.x + 5 + n % 2 * 9, y - 3), Color(color, color.a * 0.5), 1.5, true)

static func diamond(canvas: CanvasItem, at: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	var points := PackedVector2Array([at + Vector2.UP * radius, at + Vector2.RIGHT * radius, at + Vector2.DOWN * radius, at + Vector2.LEFT * radius])
	if filled:
		canvas.draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		canvas.draw_polyline(points, color, 1.25, true)

static func cloud(canvas: CanvasItem, at: Vector2, direction: float, scale_value: float = 1.0, alpha: float = 1.0) -> void:
	# Compact scrolls echo the reference's Japanese cloud ornament.
	for n in range(3):
		var center := at + Vector2(direction * n * 10, -n * 3) * scale_value
		canvas.draw_arc(center, (10 - n * 2) * scale_value, -0.8, PI * 1.65, 24, Color(GOLD.darkened(0.25), alpha), 4 * scale_value, true)
		canvas.draw_arc(center + Vector2(0, -1), (10 - n * 2) * scale_value, -0.8, PI * 1.65, 24, Color(GOLD.lightened(0.1), alpha), 1.3 * scale_value, true)
	canvas.draw_line(at + Vector2(-direction * 10, 11) * scale_value, at + Vector2(direction * 45, 4) * scale_value, Color(GOLD, alpha), 2 * scale_value, true)

static func text(canvas: CanvasItem, font: Font, value: String, at: Vector2, font_size: int, color: Color = PAPER, outline: int = 3) -> void:
	canvas.draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(INK, color.a))
	canvas.draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
