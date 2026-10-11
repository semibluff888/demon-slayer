class_name BattleStyle
extends RefCounted
## Lightweight screen-space strokes shared by the battle HUD and overlays.
## Colors come from the 「大正墨金」kit so battle and menus share one palette.
const Kit = preload("res://scripts/ui/kit.gd")
const PAPER := Kit.PAPER
const GOLD := Kit.GOLD
const INK := Kit.INK_800
const MUTED := Kit.MUTED

static func blade_points(bounds: Rect2, reverse: bool = false) -> PackedVector2Array:
	return Kit.blade(bounds, reverse)

static func blade(canvas: CanvasItem, bounds: Rect2, color: Color, reverse: bool = false) -> void:
	if bounds.size.x <= 0:
		return
	var points := blade_points(bounds, reverse)
	var colors := PackedColorArray()
	for point in points:
		colors.append(color.lightened(0.16) if point.y <= bounds.get_center().y else color)
	canvas.draw_polygon(points, colors)

static func diamond(canvas: CanvasItem, at: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	Kit.diamond(canvas, at, radius, color, filled, 1.0)

static func text(canvas: CanvasItem, font: Font, value: String, at: Vector2, font_size: int, color: Color = PAPER, outline: int = 2) -> void:
	canvas.draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(INK, color.a * 0.9))
	canvas.draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
