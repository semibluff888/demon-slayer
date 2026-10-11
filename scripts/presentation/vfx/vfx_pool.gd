extends RefCounted
## Deterministic sprite particles in world units. They advance only with the
## presentation delta the owner passes in (so hitstop, pause and KO freezes
## hold them) and draw as one textured triangle batch per sheet.

var capacity: int = 160
## Sheet layout: cells are read left to right, top to bottom.
var columns: int = 1
var rows: int = 1
## Fraction of life spent fading in / out.
var fade_in: float = 0.08
var fade_out: float = 0.45
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var life := PackedFloat32Array()
var duration := PackedFloat32Array()
var size := PackedFloat32Array()
var grow := PackedFloat32Array()
var angle := PackedFloat32Array()
var spin := PackedFloat32Array()
var gravity := PackedFloat32Array()
var drag := PackedFloat32Array()
var stretch := PackedFloat32Array()
var cell := PackedInt32Array()
var color := PackedColorArray()

func _init(sheet_columns: int = 1, sheet_rows: int = 1, max_count: int = 160) -> void:
	columns = sheet_columns
	rows = sheet_rows
	capacity = max_count

func count() -> int:
	return life.size()

func clear() -> void:
	for array in [pos, vel, life, duration, size, grow, angle, spin, gravity, drag, stretch, cell, color]:
		array.clear()

## `stretch_amount` > 0 elongates the sprite along its velocity (spray streaks).
func spawn(at: Vector2, velocity: Vector2, lifetime: float, sprite_size: float, sheet_cell: int, tint: Color,
		gravity_amount: float = 0.0, drag_amount: float = 0.0, rotation: float = 0.0, spin_speed: float = 0.0,
		growth: float = 1.0, stretch_amount: float = 0.0) -> void:
	if life.size() >= capacity:
		_remove(0)
	pos.append(at)
	vel.append(velocity)
	life.append(lifetime)
	duration.append(maxf(lifetime, 0.001))
	size.append(sprite_size)
	grow.append(growth)
	angle.append(rotation)
	spin.append(spin_speed)
	gravity.append(gravity_amount)
	drag.append(drag_amount)
	stretch.append(stretch_amount)
	cell.append(sheet_cell % maxi(1, columns * rows))
	color.append(tint)

func _remove(index: int) -> void:
	for array in [pos, vel, life, duration, size, grow, angle, spin, gravity, drag, stretch, cell, color]:
		array.remove_at(index)

func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var i := 0
	while i < life.size():
		life[i] -= delta
		if life[i] <= 0.0:
			_remove(i)
			continue
		var v := vel[i]
		v.y += gravity[i] * delta
		v *= maxf(0.0, 1.0 - drag[i] * delta)
		vel[i] = v
		pos[i] += v * delta
		angle[i] += spin[i] * delta
		i += 1

## Draws every particle through `to_screen` (world -> canvas point) and `zoom`.
func draw(canvas: CanvasItem, texture: Texture2D, to_screen: Callable, zoom: float, alpha_scale: float = 1.0) -> void:
	var n := life.size()
	if n == 0 or texture == null:
		return
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var tints := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(n * 4)
	uvs.resize(n * 4)
	tints.resize(n * 4)
	indices.resize(n * 6)
	var cell_size := Vector2(1.0 / columns, 1.0 / rows)
	for i in range(n):
		var t := 1.0 - life[i] / duration[i]
		var alpha := color[i].a * alpha_scale * smoothstep(0.0, maxf(fade_in, 0.001), t) * (1.0 - smoothstep(1.0 - fade_out, 1.0, t))
		var center: Vector2 = to_screen.call(pos[i])
		var half := size[i] * lerpf(1.0, grow[i], t) * zoom * 0.5
		var along := Vector2.from_angle(angle[i])
		var extent := Vector2(half, half)
		if stretch[i] > 0.0 and vel[i].length_squared() > 1.0:
			along = vel[i].normalized()
			extent.x *= 1.0 + stretch[i]
		var side := Vector2(-along.y, along.x)
		var base := i * 4
		vertices[base] = center - along * extent.x - side * extent.y
		vertices[base + 1] = center + along * extent.x - side * extent.y
		vertices[base + 2] = center + along * extent.x + side * extent.y
		vertices[base + 3] = center - along * extent.x + side * extent.y
		var corner := Vector2(cell[i] % columns, cell[i] / columns) * cell_size
		uvs[base] = corner
		uvs[base + 1] = corner + Vector2(cell_size.x, 0)
		uvs[base + 2] = corner + cell_size
		uvs[base + 3] = corner + Vector2(0, cell_size.y)
		var tint := Color(color[i], alpha)
		for k in range(4):
			tints[base + k] = tint
		indices[i * 6] = base
		indices[i * 6 + 1] = base + 1
		indices[i * 6 + 2] = base + 2
		indices[i * 6 + 3] = base
		indices[i * 6 + 4] = base + 2
		indices[i * 6 + 5] = base + 3
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, tints, uvs,
		PackedInt32Array(), PackedFloat32Array(), texture.get_rid())
