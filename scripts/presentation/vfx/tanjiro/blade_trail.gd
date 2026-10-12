extends "res://scripts/presentation/vfx/tanjiro/technique.gd"
## Sword normals (5A/5C, 2A/2C, jA/jC): a short stroke of water strands along
## the authored cut, with a bright cut line on its outer edge and spray thrown
## off as it lands; flame is woven in while awakened.

func sweep(move: Resource) -> Paths.Sweep:
	var curve: Array = vfx.cut_curves.get(move.effect(), [Vector2(10, -45), Vector2(45, -60), Vector2(60, -30)])
	return Paths.Sweep.new(curve[0], curve[1], curve[2], 13.0 if move.kind == "heavy" else 9.0)

func head(t: float, move: Resource) -> float:
	return clampf((t - move.startup + 1.0) / (move.active * 0.6 + 0.5), 0.0, 1.0)

func tail(t: float, move: Resource) -> float:
	return clampf((t - move.startup - move.active * 0.5) / (move.active * 0.5 + 4.0), 0.0, 1.25)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var big: bool = move.kind == "heavy"
	var hybrid: bool = actor.form_active()
	var seed: int = f.attack_instance * 167 + f.slot * 7919 + tick * 37
	var path := sweep(move)
	if tick == move.startup:
		# Spray flung off the outer edge as the cut lands.
		for n in range(16 if big else 10):
			var u: float = 0.35 + 0.65 * vfx.rand(seed, n)
			var along: Vector2 = path.point(minf(u + 0.02, 1.0), 0.0) - path.point(maxf(u - 0.02, 0.0), 0.0)
			var outward: Vector2 = path.point(u, 1.0) - path.point(u, 0.0)
			var velocity: Vector2 = along.normalized() * lerpf(60.0, 160.0, vfx.rand(seed, n + 20)) + outward * lerpf(30.0, 90.0, vfx.rand(seed, n + 40))
			vfx.drops.spawn(vfx.world(f, path.point(u, path.width(u) * 0.4)), vfx.world_dir(f, velocity), lerpf(0.25, 0.45, vfx.rand(seed, n + 60)),
				lerpf(1.2, 2.6, vfx.rand(seed, n + 80)), 0, Color.WHITE, 320.0, 0.8, 0.0, 0.0, 0.7, 0.9)
		if big:
			for n in range(3):
				var u: float = 0.6 + 0.4 * vfx.rand(seed, n + 100)
				vfx.foam.spawn(vfx.world(f, path.point(u, path.width(u) * 0.45)), vfx.world_dir(f, Vector2(40.0, -40.0)), 0.28, lerpf(4.0, 6.0, vfx.rand(seed, n + 110)),
					Kit.SPRAY_CELLS[n % Kit.SPRAY_CELLS.size()], Color.WHITE, 200.0, 1.5, vfx.rand(seed, n + 120) * TAU, 4.0, 0.8)
		if hybrid:
			for n in range(8 if big else 5):
				var u: float = 0.2 + 0.8 * vfx.rand(seed, n + 140)
				vfx.petals.spawn(vfx.world(f, path.point(u, 0.0)), vfx.world_dir(f, Vector2(lerpf(-20.0, 50.0, vfx.rand(seed, n + 150)), -lerpf(20.0, 60.0, vfx.rand(seed, n + 160)))),
					lerpf(0.35, 0.55, vfx.rand(seed, n + 170)), lerpf(4.0, 7.0, vfx.rand(seed, n + 180)), Kit.PETAL_CELLS[n % Kit.PETAL_CELLS.size()], Color.WHITE,
					-40.0, 1.5, vfx.rand(seed, n + 190) * TAU, 5.0, 0.7)
	var erosion := tail(float(tick), move)
	if erosion > 0.0 and erosion <= 1.0:
		for n in range(2 if big else 1):
			vfx.drops.spawn(vfx.world(f, path.point(erosion, path.width(erosion) * (vfx.rand(seed, n) - 0.5))), vfx.world_dir(f, Vector2(lerpf(-10.0, 30.0, vfx.rand(seed, n + 10)), 20.0)),
				lerpf(0.25, 0.4, vfx.rand(seed, n + 20)), lerpf(1.2, 2.2, vfx.rand(seed, n + 30)), 0, Color.WHITE, 260.0, 0.8)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, hybrid: bool) -> void:
	var big: bool = move.kind == "heavy"
	vfx.water_contact(event, attacker, 0.85 if big else 0.62, hybrid, big)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var big: bool = move.kind == "heavy"
	var hybrid: bool = actor.form_active()
	var t := clock(f)
	var lead := head(t, move)
	var erosion := tail(t, move)
	if lead <= 0.0 or erosion >= 1.2:
		return
	var path := sweep(move)
	match layer:
		Kit.WATER:
			vfx.water_body(canvas, path, lead, erosion, hybrid, f.attack_instance, 1.6, big)
		Kit.SOLID:
			if big:
				vfx.foam_crest(canvas, path, lead, erosion, 4, 0.5, 0.42)
		Kit.FLAME:
			# The cut itself: a bright line just outside the water.
			var line := PackedVector2Array()
			var widths := PackedFloat32Array()
			var tint := PackedColorArray()
			for n in range(24):
				var u := lead * n / 23.0
				line.append(path.point(u, path.width(u) * 0.5 + 1.2))
				widths.append((2.6 if big else 2.0) * sin(clampf(u, 0.02, 0.98) * PI))
				tint.append(Color(0.85, 0.94, 1.0, 0.9 * smoothstep(erosion - 0.3, erosion, u)))
			Ribbon.draw(canvas, line, widths, tint, vfx.band)
		Kit.LIGHT:
			vfx.glow_along(canvas, path, lead, erosion, Color(Kit.WATER_GLOW, 0.16 if hybrid else 0.22), 2.4, 0.0, 24)
