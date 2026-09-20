extends RefCounted
const Arena = preload("res://scripts/arena_rules.gd")
# The panorama already has 48 world units of painted overscan per side.
# Keep horizontal throw victims inside the viewport at the actual arena boundary.
const EDGE_OVERSCAN: float = 16.0
var center_x: float = Arena.CENTER
var zoom: float = Arena.ZOOM
var floor_y: float = Arena.FLOOR_SCREEN_Y
var shake: Vector2 = Vector2.ZERO

func reset(fighters: Array) -> void:
	center_x = clampf((fighters[0].x + fighters[1].x) * 0.5, Arena.HALF_VIEW - EDGE_OVERSCAN, Arena.WIDTH - Arena.HALF_VIEW + EDGE_OVERSCAN)
	zoom = Arena.ZOOM
	shake = Vector2.ZERO

func target_zoom(_fighters: Array, _artwork: Array[Rect2] = []) -> float:
	return Arena.ZOOM

func update(fighters: Array, delta: float, _artwork: Array[Rect2] = []) -> void:
	zoom = Arena.ZOOM
	var left: float = minf(fighters[0].x, fighters[1].x)
	var right: float = maxf(fighters[0].x, fighters[1].x)
	var target := clampf((left + right) * 0.5, Arena.HALF_VIEW - EDGE_OVERSCAN, Arena.WIDTH - Arena.HALF_VIEW + EDGE_OVERSCAN)
	center_x = lerpf(center_x, target, 1.0 - exp(-10.0 * delta))
	# Smooth only within the interval that keeps both bodies visible. Weapons and
	# cloth may extend beyond the viewport; they never alter physical scale.
	var minimum := maxf(Arena.HALF_VIEW - EDGE_OVERSCAN, right - Arena.HALF_VIEW + Arena.BODY_MARGIN)
	var maximum := minf(Arena.WIDTH - Arena.HALF_VIEW + EDGE_OVERSCAN, left + Arena.HALF_VIEW - Arena.BODY_MARGIN)
	center_x = clampf(center_x, minimum, maximum) if minimum <= maximum else target

func point(world: Vector2) -> Vector2:
	return Vector2(640 + (world.x - center_x) * zoom, floor_y + (world.y - Arena.FLOOR_Y) * zoom) + shake

func rect(world: Rect2) -> Rect2:
	return Rect2(point(world.position), world.size * zoom)
