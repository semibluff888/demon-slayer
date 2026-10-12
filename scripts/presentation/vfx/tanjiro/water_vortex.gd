extends "res://scripts/presentation/vfx/tanjiro/technique.gd"
## 扭转漩涡 (214B/D): a white dry-brush whirlpool wound round Tanjiro, with a
## blue water helix spinning inside it. The far half of every coil is drawn
## behind both fighters; the whirl opens with a white splash, rises from the
## floor, and frays into white streaks from the bottom up.

const FAR_TINT := Color(0.72, 0.8, 0.93)

## Outer brush coils, inner water coils, and (awakened) flame between them.
func coils(t: float, move: Resource, big: bool) -> Array:
	var scale := 1.1 if big else 1.0
	var spin: float = -(t - move.startup) * 0.85
	var axis := Vector2(30.0 * scale, 0.0)
	var brush := Paths.Helix.new(axis, 56.0 * scale, -2.0, -92.0 * scale, 2.0, spin, 24.0 * scale)
	var water := Paths.Helix.new(axis + Vector2(-2.0, 0.0), 40.0 * scale, -6.0, -84.0 * scale, 2.3, spin * 1.2 + 2.2, 14.0 * scale)
	var flame := Paths.Helix.new(axis + Vector2(-1.0, 0.0), 52.0 * scale, -4.0, -88.0 * scale, 2.15, spin * 1.1 + PI * 0.6, 15.0 * scale)
	brush.squash = 0.26
	water.squash = 0.28
	flame.squash = 0.27
	return [brush, water, flame]

func head(t: float, move: Resource) -> float:
	return clampf((t - move.startup + 0.5) / 3.5, 0.0, 1.0)

func tail(t: float, move: Resource) -> float:
	return clampf((t - move.startup - move.active + 4.0) / 9.0, 0.0, 1.25)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var big := heavy(move)
	var hybrid: bool = actor.form_active()
	var seed: int = f.attack_instance * 149 + f.slot * 7919 + tick * 23
	var start: int = move.startup
	if tick >= 3 and tick < start:
		gather_beads(f, actor, tick, seed)
	var centre: Vector2 = vfx.world(f, Vector2(18.0, -34.0))
	if tick == start:
		# The whirl opens with a white splash around the body.
		vfx.bursts.append({"kind": "splash", "at": centre, "age": 0.0, "life": 0.3, "size": 80.0 if big else 70.0, "facing": float(f.facing), "spin": 0.0})
		vfx.foam_burst(centre, 12 if big else 10, Vector2.ZERO, 70.0, 170.0, seed + 1)
		vfx.droplets(centre, 34 if big else 28, Vector2(0, -0.3), 80.0, 230.0, seed + 2)
		vfx.mist_burst(centre, 8, 40.0, seed + 3)
		if hybrid:
			vfx.petal_burst(centre, 18, 120.0, seed + 4)
	var t := float(tick)
	var lead := head(t, move)
	var erosion := tail(t, move)
	if lead <= 0.0 or erosion >= 1.0:
		return
	var brush: Paths.Helix = coils(t, move, big)[0]
	# Spray whipped off the near side of the coils, tangent to the spin.
	for n in range(5):
		var u := lerpf(maxf(erosion, 0.05), lead, vfx.rand(seed, n + 10))
		var a: float = brush.theta(u)
		if sin(a) < 0.0:
			continue
		var velocity := Vector2(-sin(a), 0.0) * lerpf(140.0, 260.0, vfx.rand(seed, n + 20)) + Vector2(0, -lerpf(10.0, 60.0, vfx.rand(seed, n + 30)))
		vfx.drops.spawn(vfx.world(f, brush.point(u, 0.0)), vfx.world_dir(f, velocity), lerpf(0.25, 0.45, vfx.rand(seed, n + 40)), lerpf(1.6, 3.0, vfx.rand(seed, n + 50)), 0,
			Color.WHITE, 120.0, 1.2, 0.0, 0.0, 0.7, 2.5)
	if tick % 2 == 0:
		var u := lerpf(maxf(erosion, 0.1), lead, vfx.rand(seed, 60))
		vfx.foam.spawn(vfx.world(f, brush.point(u, 0.0)), vfx.world_dir(f, Vector2(-sin(brush.theta(u)) * 90.0, -20.0)), 0.3, lerpf(5.0, 8.0, vfx.rand(seed, 61)),
			Kit.SPRAY_CELLS[tick % Kit.SPRAY_CELLS.size()], Color.WHITE, 60.0, 2.0, vfx.rand(seed, 62) * TAU, 6.0, 0.8)
	if hybrid:
		var u := lerpf(maxf(erosion, 0.05), lead, vfx.rand(seed, 70))
		vfx.petals.spawn(vfx.world(f, brush.point(u, 0.0)), vfx.world_dir(f, Vector2(-sin(brush.theta(u)) * 80.0, -40.0)), 0.45, lerpf(5.0, 8.0, vfx.rand(seed, 71)),
			Kit.PETAL_CELLS[tick % Kit.PETAL_CELLS.size()], Color.WHITE, -50.0, 1.5, vfx.rand(seed, 72) * TAU, 6.0, 0.7)
	if erosion > 0.0:
		# Where the whirl unravels it flies apart in long white streaks.
		for n in range(6):
			var u := clampf(erosion + 0.08 * vfx.rand(seed, n + 80), 0.0, 1.0)
			var a: float = brush.theta(u)
			var velocity := Vector2(-sin(a) * lerpf(160.0, 300.0, vfx.rand(seed, n + 90)), -lerpf(0.0, 40.0, vfx.rand(seed, n + 100)))
			vfx.drops.spawn(vfx.world(f, brush.point(u, 0.0)), vfx.world_dir(f, velocity), lerpf(0.25, 0.4, vfx.rand(seed, n + 110)), lerpf(2.0, 3.4, vfx.rand(seed, n + 120)), 0,
				Color(1, 1, 1, 0.9), 40.0, 2.5, 0.0, 0.0, 0.8, 4.0)
		vfx.mist.spawn(vfx.world(f, brush.point(erosion, 0.0)), vfx.world_dir(f, Vector2(-sin(brush.theta(erosion)) * 40.0, 0.0)), 0.4, 10.0, 0, Kit.WATER_MIST, 0.0, 2.0, 0.0, 0.0, 1.8)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, hybrid: bool) -> void:
	var first := int(event.get("segment", 0)) == 0
	vfx.water_contact(event, attacker, (0.85 if first else 1.1) + (0.1 if heavy(move) else 0.0), hybrid)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var big := heavy(move)
	var hybrid: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var gather := clampf((t - 2.0) / 5.0, 0.0, 1.0) * (1.0 - clampf(t - start, 0.0, 1.0))
	if gather > 0.0:
		vfx.blade_water(canvas, layer, actor, gather, hybrid)
	if layer == Kit.LIGHT:
		var flash := sin(clampf((t - start + 4.0) / 5.0, 0.0, 1.0) * PI)
		if flash > 0.02:
			vfx.body_flash(canvas, f, actor, Color(0.45, 0.65, 1.0) * flash)
	var lead := head(t, move)
	var erosion := tail(t, move)
	if lead <= 0.0 or erosion >= 1.2:
		return
	var helices := coils(t, move, big)
	var brush: Paths.Helix = helices[0]
	var water: Paths.Helix = helices[1]
	var flame: Paths.Helix = helices[2]
	var paint: Texture2D = vfx.textures.get("white-brush-strands")
	var fire: Texture2D = vfx.textures.get("hybrid-fire-strands")
	match layer:
		Kit.BACK, Kit.WATER:
			var side := -1 if layer == Kit.BACK else 1
			var shade := FAR_TINT if side < 0 else Color.WHITE
			# Texture row 0 is the top of the band; on the near side travel runs
			# leftward, so the rows flip to keep it on top.
			var rows := [0.08, 0.92] if side < 0 else [0.92, 0.08]
			var flow: float = -vfx.time * 2.4
			vfx.strand(canvas, water, lead, erosion - 0.05, 0.0, 1.0, 0.0, 1.0, shade, rows, water.length / 3.0, flow * 1.3, null, side, 72)
			vfx.strand(canvas, brush, lead, erosion, 0.0, 1.0, 0.0, 1.0, shade, rows, brush.length / 2.5, flow, paint, side, 72)
			if hybrid:
				# Flame wound over the white, opaque so it reads as fire on water.
				vfx.strand(canvas, flame, lead, erosion + 0.04, 0.0, 1.0, 0.04, 1.0, shade, rows, flame.length / 3.5, flow * 1.2, fire, side, 72)
			vfx.strand(canvas, brush, lead, erosion, -0.28, 0.42, 0.08, 0.96, Color(shade * Color(0.82, 0.94, 1.0), 0.85), rows, brush.length / 3.2, flow * 1.4 + 0.4, paint, side, 72)
		Kit.LIGHT:
			vfx.glow_along(canvas, brush, lead, erosion, Color(0.55, 0.8, 1.0, 0.16), 2.6)
