extends RefCounted
## World coordinates remain the original 640-wide fighting space. Only the
## presentation transforms into the 1280x720 viewport; HUD never uses this.
var center_x: float = 320.0
var zoom: float = 3.4
var floor_y: float = 594.0
var shake: Vector2 = Vector2.ZERO

func reset(fighters: Array) -> void:
	center_x = (fighters[0].x + fighters[1].x) * 0.5
	zoom = target_zoom(fighters)
	shake = Vector2.ZERO

func target_zoom(fighters: Array, artwork: Array[Rect2] = []) -> float:
	var distance: float = absf(fighters[0].x - fighters[1].x)
	var top: float = minf(fighters[0].y, fighters[1].y) - 104.0
	for i in range(artwork.size()):
		top = minf(top, fighters[i].y + artwork[i].position.y - 6)
	var vertical_limit := (floor_y - 150.0) / maxf(286.0 - top, 1)
	return minf(clampf(1140.0 / (distance + 100.0), 1.6, 3.4), vertical_limit)

func update(fighters: Array, delta: float, artwork: Array[Rect2] = []) -> void:
	var target: float = (fighters[0].x + fighters[1].x) * 0.5
	var desired := target_zoom(fighters, artwork)
	center_x = lerpf(center_x, target, 1.0 - exp(-10.0 * delta))
	# Zooming out is immediate to keep both fighters in frame during fast dashes.
	zoom = desired if desired < zoom else lerpf(zoom, desired, 1.0 - exp(-5.0 * delta))
	var radius: float = maxf(absf(fighters[0].x - center_x), absf(fighters[1].x - center_x)) + 36.0
	for i in range(artwork.size()):
		radius = maxf(radius, maxf(absf(fighters[i].x + artwork[i].position.x - center_x), absf(fighters[i].x + artwork[i].end.x - center_x)) + 6)
	zoom = minf(zoom, 620.0 / maxf(radius, 1.0))

func point(world: Vector2) -> Vector2:
	return Vector2(640 + (world.x - center_x) * zoom, floor_y + (world.y - 286) * zoom) + shake

func rect(world: Rect2) -> Rect2:
	return Rect2(point(world.position), world.size * zoom)
