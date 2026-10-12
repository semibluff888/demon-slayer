extends RefCounted
## Centrelines that brush strands are laid along, in fighter-local units (+x
## forward). `u` runs 0..1 from the tail of a stroke to its head. Each path
## gives the point at `u` displaced `offset` across the body, the body's
## thickness, the direction of travel, and (for wrapped shapes) whether `u`
## lies on the near or far side of the fighter.

class Path extends RefCounted:
	var thick := 20.0
	## Arc length, for tiling textures along the stroke.
	var length := 100.0
	## True when travel runs clockwise on screen, so the left of travel (texture
	## row 0) faces inward and rows must be swapped to keep foam on the outside.
	var mirrored := false

	func point(_u: float, _offset: float) -> Vector2:
		return Vector2.ZERO

	func width(_u: float) -> float:
		return thick

	## > 0 in front of the fighter, < 0 behind.
	func depth(_u: float) -> float:
		return 1.0

	func angle(u: float) -> float:
		return (point(minf(u + 0.01, 1.0), 0.0) - point(maxf(u - 0.01, 0.0), 0.0)).angle()

## Elliptical sweep around `pivot`, offsets pushed out along the radius.
class Arc extends Path:
	var pivot := Vector2.ZERO
	var a0 := 0.0
	var a1 := 1.0
	var r0 := 40.0
	var r1 := 40.0
	## Outward swell mid-stroke, as a fraction of the radius.
	var bulge := 0.0
	## Vertical squash of the ellipse, then its rotation.
	var squash := 1.0
	var tilt := 0.0
	## "crescent": thin tail, heavy leading edge; "ring": pointed tail, full
	## body; "even": constant thickness.
	var profile := "ring"

	func _init(centre: Vector2, from_angle: float, to_angle: float, from_radius: float, to_radius: float, thickness: float) -> void:
		pivot = centre
		a0 = from_angle
		a1 = to_angle
		r0 = from_radius
		r1 = to_radius
		thick = thickness
		mirrored = to_angle < from_angle
		length = absf(to_angle - from_angle) * (from_radius + to_radius) * 0.5 * 1.05

	func point(u: float, offset: float) -> Vector2:
		var a := lerpf(a0, a1, u)
		var radius := lerpf(r0, r1, u) * (1.0 + bulge * sin(u * PI)) + offset
		return pivot + Vector2(cos(a) * radius, sin(a) * radius * squash).rotated(tilt)

	func angle(u: float) -> float:
		if is_equal_approx(squash, 1.0) and is_zero_approx(tilt):
			return lerpf(a0, a1, u) + PI * 0.5 * signf(a1 - a0)
		return super(u)

	func width(u: float) -> float:
		if profile == "crescent":
			return thick * pow(sin(clampf(u * 0.92 + 0.04, 0.0, 1.0) * PI), 0.5) * (0.35 + 0.65 * u)
		if profile == "even":
			return thick
		return thick * (0.3 + 0.7 * smoothstep(0.0, 0.3, u)) * (1.0 - 0.2 * smoothstep(0.92, 1.0, u))

## Coils wound around a vertical axis and seen from the side and slightly
## above: the near half of each turn hangs lower and is drawn thicker.
class Helix extends Path:
	var centre := Vector2.ZERO
	var radius := 50.0
	var squash := 0.2
	var bottom := 0.0
	var top := -60.0
	var turns := 2.0
	var phase := 0.0

	func _init(axis: Vector2, coil_radius: float, from_y: float, to_y: float, coil_turns: float, spin: float, thickness: float) -> void:
		centre = axis
		radius = coil_radius
		bottom = from_y
		top = to_y
		turns = coil_turns
		phase = spin
		thick = thickness
		length = TAU * coil_radius * coil_turns

	func theta(u: float) -> float:
		return phase + u * turns * TAU

	func point(u: float, offset: float) -> Vector2:
		var a := theta(u)
		return Vector2(centre.x + cos(a) * radius, lerpf(bottom, top, u) + sin(a) * radius * squash + offset)

	func depth(u: float) -> float:
		return sin(theta(u))

	func width(u: float) -> float:
		var taper := smoothstep(0.0, 0.12, u) * (1.0 - 0.4 * smoothstep(0.88, 1.0, u))
		return thick * (0.72 + 0.28 * depth(u)) * taper

## A sinuous body running forward from `tail_x` to `head_x`, offsets taken
## along its normal; thin at the tail, full at the head.
class Wave extends Path:
	var tail_x := -30.0
	var head_x := 100.0
	var y := -44.0
	var amplitude := 20.0
	var periods := 1.4
	var phase := 0.0

	func _init(from_x: float, to_x: float, mid_y: float, swing: float, waves: float, shift: float, thickness: float) -> void:
		tail_x = from_x
		head_x = to_x
		y = mid_y
		amplitude = swing
		periods = waves
		phase = shift
		thick = thickness
		length = absf(to_x - from_x) * (1.0 + amplitude * periods * 0.02)

	func centre(u: float) -> Vector2:
		var envelope := 0.35 + 0.65 * sin(clampf(u, 0.0, 1.0) * PI * 0.85 + 0.25)
		return Vector2(lerpf(tail_x, head_x, u), y + sin(u * periods * TAU + phase) * amplitude * envelope)

	func point(u: float, offset: float) -> Vector2:
		var along := centre(minf(u + 0.01, 1.0)) - centre(maxf(u - 0.01, 0.0))
		var normal := Vector2(along.y, -along.x).normalized()
		return centre(u) + normal * offset

	func width(u: float) -> float:
		return thick * (0.22 + 0.78 * pow(clampf(u, 0.0, 1.0), 0.55))

## A quadratic curve through a sword cut (authored per normal attack), offsets
## taken along its normal; thin where the swing starts, full near its end.
class Sweep extends Path:
	var p0 := Vector2.ZERO
	var p1 := Vector2.ZERO
	var p2 := Vector2.ZERO

	func _init(start: Vector2, control: Vector2, end: Vector2, thickness: float) -> void:
		p0 = start
		p1 = control
		p2 = end
		thick = thickness
		length = (start.distance_to(control) + control.distance_to(end) + start.distance_to(end)) * 0.5

	func centre(u: float) -> Vector2:
		return p0.lerp(p1, u).lerp(p1.lerp(p2, u), u)

	func point(u: float, offset: float) -> Vector2:
		var along := (p1 - p0).lerp(p2 - p1, clampf(u, 0.0, 1.0))
		return centre(u) + Vector2(along.y, -along.x).normalized() * offset

	func width(u: float) -> float:
		return thick * pow(sin(clampf(u * 0.9 + 0.05, 0.0, 1.0) * PI), 0.6) * (0.45 + 0.55 * u)
