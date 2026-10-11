extends RefCounted
## Textured triangle strips for blade trails and elemental bands, pushed straight
## to the canvas item. No polygon triangulation is involved, so curls, loops and
## self-overlapping arcs are safe. U runs along the centreline (by arc length),
## V across it: 0 on the left of travel, 1 on the right.

## Draws a strip through `points` with per-point `widths` and `colors`.
## `u_scale` > 0 maps that many units of arc length to one texture repeat;
## otherwise U spans u_offset..u_offset+1 over the whole strip. `v_from` and
## `v_to` pick the texture rows laid across the strip (left to right of travel).
static func draw(canvas: CanvasItem, points: PackedVector2Array, widths: PackedFloat32Array, colors: PackedColorArray,
		texture: Texture2D = null, u_scale: float = 0.0, u_offset: float = 0.0, v_from: float = 0.0, v_to: float = 1.0) -> void:
	var count := points.size()
	if count < 2 or widths.size() < count or colors.size() < count:
		return
	var lengths := PackedFloat32Array()
	lengths.resize(count)
	for i in range(1, count):
		lengths[i] = lengths[i - 1] + points[i].distance_to(points[i - 1])
	var total := maxf(lengths[count - 1], 0.0001)
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var tints := PackedColorArray()
	vertices.resize(count * 2)
	uvs.resize(count * 2)
	tints.resize(count * 2)
	var tangent := (points[1] - points[0]).normalized()
	for i in range(count):
		var ahead := points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]
		if ahead.length_squared() > 0.000001:
			tangent = ahead.normalized()
		var normal := Vector2(-tangent.y, tangent.x) * widths[i] * 0.5
		var u := u_offset + (lengths[i] / u_scale if u_scale > 0.0 else lengths[i] / total)
		vertices[i * 2] = points[i] - normal
		vertices[i * 2 + 1] = points[i] + normal
		uvs[i * 2] = Vector2(u, v_from)
		uvs[i * 2 + 1] = Vector2(u, v_to)
		tints[i * 2] = colors[i]
		tints[i * 2 + 1] = colors[i]
	var indices := PackedInt32Array()
	indices.resize((count - 1) * 6)
	for i in range(count - 1):
		var a := i * 2
		indices[i * 6] = a
		indices[i * 6 + 1] = a + 1
		indices[i * 6 + 2] = a + 2
		indices[i * 6 + 3] = a + 1
		indices[i * 6 + 4] = a + 3
		indices[i * 6 + 5] = a + 2
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, tints, uvs,
		PackedInt32Array(), PackedFloat32Array(), texture.get_rid() if texture != null else RID())

## Samples a poly-line at `count` evenly spaced arc-length positions between
## fractions `from` and `to` (0..1). Used to reveal or erode a trail smoothly.
static func resample(points: PackedVector2Array, count: int, from: float = 0.0, to: float = 1.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.size() < 2 or count < 2:
		return result
	var lengths := PackedFloat32Array()
	lengths.resize(points.size())
	for i in range(1, points.size()):
		lengths[i] = lengths[i - 1] + points[i].distance_to(points[i - 1])
	var total := lengths[points.size() - 1]
	var segment := 1
	for n in range(count):
		var target := lerpf(from, to, float(n) / (count - 1)) * total
		while segment < points.size() - 1 and lengths[segment] < target:
			segment += 1
		var span := maxf(lengths[segment] - lengths[segment - 1], 0.0001)
		var t := clampf((target - lengths[segment - 1]) / span, 0.0, 1.0)
		result.append(points[segment - 1].lerp(points[segment], t))
	return result

## Points on an ellipse arc around `center` (radii in local axes, then rotated).
static func arc(center: Vector2, radii: Vector2, from_angle: float, to_angle: float, count: int, rotation: float = 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for n in range(count):
		var a := lerpf(from_angle, to_angle, float(n) / maxi(1, count - 1))
		result.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(rotation))
	return result

## Catmull-Rom smoothing through key points; `per_span` samples per segment.
static func smooth(keys: PackedVector2Array, per_span: int = 8) -> PackedVector2Array:
	var result := PackedVector2Array()
	if keys.size() < 2:
		return keys
	for i in range(keys.size() - 1):
		var p0 := keys[maxi(i - 1, 0)]
		var p1 := keys[i]
		var p2 := keys[i + 1]
		var p3 := keys[mini(i + 2, keys.size() - 1)]
		for s in range(per_span):
			var t := float(s) / per_span
			var t2 := t * t
			var t3 := t2 * t
			result.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	result.append(keys[keys.size() - 1])
	return result

## Splits indices 0..count-1 into contiguous runs where `depths` keeps its sign.
## Returns [start, end, front] triples so ring effects can wrap behind a body.
static func depth_runs(depths: PackedFloat32Array) -> Array:
	var runs := []
	if depths.is_empty():
		return runs
	var start := 0
	for i in range(1, depths.size() + 1):
		if i == depths.size() or (depths[i] >= 0.0) != (depths[start] >= 0.0):
			# Overlap one point so the halves meet without a gap.
			runs.append([start, mini(i, depths.size() - 1), depths[start] >= 0.0])
			start = i
	return runs
