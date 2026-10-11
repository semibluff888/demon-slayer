extends Control
## One-shot ink-brush wipe that uncovers a freshly built screen from left to
## right, then frees itself. Input passes straight through.
const Kit = preload("res://scripts/ui/kit.gd")
const DURATION := 0.3
var time: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(1280, 720)
	z_index = 5

func _process(delta: float) -> void:
	time += delta
	queue_redraw()
	if time >= DURATION:
		queue_free()

func _edge(front: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(26):
		var y := -20.0 + i * 30.4
		var jag := sin(i * 1.73) * 16.0 + sin(i * 4.31 + 0.6) * 7.0
		points.append(Vector2(front + jag + (y - 360.0) * 0.2, y))
	return points

func _draw() -> void:
	var progress := Kit.ease_in(clampf(time / DURATION, 0, 1)) * 0.35 + Kit.ease_out(clampf(time / DURATION, 0, 1)) * 0.65
	var front := lerpf(-200.0, 1500.0, progress)
	var edge := _edge(front)
	var ordered := PackedVector2Array()
	ordered.append(Vector2(1700, -40))
	for point in edge:
		ordered.append(point)
	ordered.append(Vector2(1700, 760))
	draw_colored_polygon(ordered, Kit.INK_900)
	var trail := PackedVector2Array()
	for point in edge:
		trail.append(point + Vector2(-10, 0))
	draw_polyline(trail, Color(Kit.CRIMSON, 0.9), 9.0, true)
	draw_polyline(edge, Color(Kit.GOLD, 0.8), 2.0, true)
