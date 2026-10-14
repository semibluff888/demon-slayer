extends RefCounted
## Deterministic lightning geometry: a jagged line between two points by
## midpoint displacement, plus forked branches. The same seed always gives the
## same bolt, so a strike only flickers when its seed changes (once per combat
## tick), never with the render rate.

static func path(a: Vector2, b: Vector2, seed: int, roughness: float = 0.22, depth: int = 4) -> PackedVector2Array:
	var points := PackedVector2Array([a, b])
	var spread := a.distance_to(b) * roughness
	for level in range(depth):
		var next := PackedVector2Array()
		for i in range(points.size() - 1):
			var p := points[i]
			var q := points[i + 1]
			var normal := (q - p).orthogonal().normalized()
			next.append(p)
			next.append((p + q) * 0.5 + normal * spread * (rand(seed, level * 97 + i) * 2.0 - 1.0))
		next.append(points[points.size() - 1])
		points = next
		spread *= 0.5
	return points

## Short branches leaving `trunk`, each a smaller bolt of up to `reach` units.
static func forks(trunk: PackedVector2Array, seed: int, count: int, reach: float) -> Array:
	var result := []
	if trunk.size() < 3:
		return result
	for n in range(count):
		var at := 1 + int(rand(seed, 300 + n) * (trunk.size() - 2))
		var along := (trunk[mini(at + 1, trunk.size() - 1)] - trunk[at - 1]).normalized()
		var direction := along.rotated((rand(seed, 310 + n) - 0.5) * 1.8)
		var end := trunk[at] + direction * reach * lerpf(0.4, 1.0, rand(seed, 320 + n))
		result.append(path(trunk[at], end, seed + 31 * (n + 1), 0.3, 3))
	return result

## A closed jagged loop around an ellipse (lightning ring), `count` corners.
static func ring(center: Vector2, radii: Vector2, seed: int, count: int = 28, jitter: float = 0.18) -> PackedVector2Array:
	var points := PackedVector2Array()
	for n in range(count + 1):
		var a := TAU * float(n % count) / count
		var r := 1.0 + (rand(seed, n % count) - 0.5) * 2.0 * jitter
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y) * r)
	return points

## Deterministic 0..1 noise (the same hash as TanjiroVfx.rand).
static func rand(seed: int, n: int) -> float:
	var h := (seed * 73856093) ^ (n * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
