class_name BattleStyle
extends RefCounted
## Lightweight screen-space strokes shared by the battle HUD and overlays.
const PAPER := Color("f6f2e8")
const GOLD := Color("d8c397")
const INK := Color("0a1420")
const MUTED := Color("b9c5ce")

static func blade_points(bounds: Rect2, reverse: bool = false) -> PackedVector2Array:
	var cut := minf(bounds.size.y * 0.5, bounds.size.x * 0.5)
	var points := PackedVector2Array([
		bounds.position, Vector2(bounds.end.x - cut, bounds.position.y),
		Vector2(bounds.end.x, bounds.get_center().y),
		Vector2(bounds.end.x - cut, bounds.end.y), Vector2(bounds.position.x, bounds.end.y)])
	if reverse:
		for i in range(points.size()):
			points[i].x = bounds.position.x + bounds.end.x - points[i].x
	return points

static func blade(canvas: CanvasItem, bounds: Rect2, color: Color, reverse: bool = false) -> void:
	if bounds.size.x <= 0:
		return
	var points := blade_points(bounds, reverse)
	var colors := PackedColorArray()
	for point in points:
		colors.append(color.lightened(0.16) if point.y <= bounds.get_center().y else color)
	canvas.draw_polygon(points, colors)

static func diamond(canvas: CanvasItem, at: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	var points := PackedVector2Array([at + Vector2.UP * radius, at + Vector2.RIGHT * radius, at + Vector2.DOWN * radius, at + Vector2.LEFT * radius])
	if filled:
		canvas.draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		canvas.draw_polyline(points, color, 1.0, true)

static func text(canvas: CanvasItem, font: Font, value: String, at: Vector2, font_size: int, color: Color = PAPER, outline: int = 2) -> void:
	canvas.draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(INK, color.a * 0.9))
	canvas.draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
