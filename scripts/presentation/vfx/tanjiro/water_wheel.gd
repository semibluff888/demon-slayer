extends "res://scripts/presentation/vfx/tanjiro/technique.gd"
## 水车 (623A/C): an upright ring of water strands traced by the blade through
## the rising somersault. The leading edge runs up the front, back over the top
## and round underneath; once the active frames end the ring stays where it was
## drawn and breaks up from its tail while Tanjiro drops away.

## Where each fighter left the floor, for the splash under the take-off.
var _takeoff: Dictionary = {}

func reset() -> void:
	super()
	_takeoff.clear()

func ring(big: bool) -> Paths.Arc:
	var scale := 1.12 if big else 1.0
	var a0 := 0.55
	var path := Paths.Arc.new(Vector2(22.0, -50.0) * scale, a0, a0 - TAU * 1.03, 37.0 * scale, 37.0 * scale, 16.0 * scale)
	path.squash = 1.16
	return path

func head(t: float, move: Resource) -> float:
	return clampf((t - move.startup + 0.4) / (move.active * 0.62), 0.0, 1.0)

func tail(t: float, move: Resource) -> float:
	return clampf((t - move.startup - move.active * 0.5) / 13.0, 0.0, 1.25)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var big := heavy(move)
	var hybrid: bool = actor.form_active()
	var seed: int = f.attack_instance * 137 + f.slot * 7919 + tick * 19
	var start: int = move.startup
	if tick >= 2 and tick < start:
		gather_beads(f, actor, tick, seed)
	anchor(f, tick)
	var at := frame(f, tick)
	var path := ring(big)
	if tick == start:
		# Spray thrown up off the floor by the take-off.
		_takeoff[f.slot] = {"instance": f.attack_instance, "x": f.x, "y": f.y, "facing": f.facing}
		for n in range(18 if big else 14):
			var side := -1.0 if n % 3 == 0 else 1.0
			vfx.drops.spawn(vfx.world(at, Vector2(lerpf(-14.0, 30.0, vfx.rand(seed, n)), -1.0)),
				vfx.world_dir(at, Vector2(side * lerpf(10.0, 60.0, vfx.rand(seed, n + 20)), -lerpf(90.0, 200.0, vfx.rand(seed, n + 40)))),
				lerpf(0.3, 0.5, vfx.rand(seed, n + 60)), lerpf(1.6, 3.2, vfx.rand(seed, n + 80)), 0, Color.WHITE, 420.0, 0.5, 0.0, 0.0, 0.7, 0.8)
		vfx.foam_burst(vfx.world(at, Vector2(8, -2)), 5 if big else 4, Vector2(0, -1.2), 40.0, 90.0, seed + 3)
		vfx.mist_burst(vfx.world(at, Vector2(8, -4)), 4, 22.0, seed + 5)
	if tick >= start and tick < start + move.active:
		# Spray flung off the leading edge as it travels round.
		var u := head(float(tick), move)
		if u > 0.0:
			var angle: float = lerpf(path.a0, path.a1, u)
			var edge: Vector2 = path.point(u, path.width(u) * 0.4)
			var forward := Vector2(sin(angle), -cos(angle))
			for n in range(6 if big else 5):
				var velocity := forward * lerpf(70.0, 170.0, vfx.rand(seed, n + 100)) + Vector2.from_angle(angle) * lerpf(30.0, 110.0, vfx.rand(seed, n + 120))
				vfx.drops.spawn(vfx.world(at, edge), vfx.world_dir(at, velocity), lerpf(0.3, 0.5, vfx.rand(seed, n + 140)), lerpf(1.5, 3.2, vfx.rand(seed, n + 160)), 0, Color.WHITE,
					320.0, 0.8, 0.0, 0.0, 0.7, 0.9)
			if tick % 2 == 0:
				vfx.foam.spawn(vfx.world(at, edge), vfx.world_dir(at, forward * 60.0 + Vector2.from_angle(angle) * 50.0), 0.32, lerpf(5.0, 7.5, vfx.rand(seed, 180)) * (1.15 if big else 1.0),
					Kit.SPRAY_CELLS[tick % Kit.SPRAY_CELLS.size()], Color.WHITE, 200.0, 1.5, vfx.rand(seed, 181) * TAU, 4.0, 0.8)
			if hybrid:
				for n in range(2):
					vfx.petals.spawn(vfx.world(at, path.point(u, path.width(u) * (vfx.rand(seed, n + 190) - 0.5))),
						vfx.world_dir(at, forward * lerpf(30.0, 70.0, vfx.rand(seed, n + 192)) + Vector2(0, -30)), lerpf(0.4, 0.6, vfx.rand(seed, n + 194)),
						lerpf(5.0, 8.0, vfx.rand(seed, n + 196)), Kit.PETAL_CELLS[(tick + n * 4) % Kit.PETAL_CELLS.size()], Color.WHITE, -40.0, 1.5, vfx.rand(seed, n + 198) * TAU, 5.0, 0.7)
	var erosion := tail(float(tick), move)
	if erosion > 0.0 and erosion <= 1.0:
		# The ring breaks into droplets where it erodes, tail first.
		var angle: float = lerpf(path.a0, path.a1, erosion)
		var outward := Vector2.from_angle(angle)
		for n in range(4):
			vfx.drops.spawn(vfx.world(at, path.point(erosion, path.width(erosion) * (vfx.rand(seed, n) - 0.5))),
				vfx.world_dir(at, outward * lerpf(10.0, 50.0, vfx.rand(seed, n + 10)) + Vector2(0, 20)), lerpf(0.3, 0.5, vfx.rand(seed, n + 20)), lerpf(1.3, 2.6, vfx.rand(seed, n + 30)),
				0, Color.WHITE, 260.0, 0.8)
		if tick % 2 == 0:
			vfx.foam.spawn(vfx.world(at, path.point(erosion, 0.0)), vfx.world_dir(at, outward * 20.0 + Vector2(0, 15)), 0.32, lerpf(4.0, 6.5, vfx.rand(seed, 40)),
				(Kit.CLOUD_CELLS + Kit.SPRAY_CELLS)[tick % 8], Color.WHITE, 120.0, 2.0, vfx.rand(seed, 41) * TAU, 0.0, 0.7)
			vfx.mist.spawn(vfx.world(at, path.point(erosion, 0.0)), vfx.world_dir(at, outward * 14.0), 0.4, 8.0, 0, Kit.WATER_MIST, 0.0, 2.0, 0.0, 0.0, 1.8)
		if hybrid:
			vfx.petals.spawn(vfx.world(at, path.point(minf(erosion + 0.04, 1.0), 0.0)), vfx.world_dir(at, outward * 35.0 + Vector2(0, -30)), 0.48, 6.0,
				Kit.PETAL_CELLS[tick % Kit.PETAL_CELLS.size()], Color.WHITE, -50.0, 1.5, vfx.rand(seed, 70) * TAU, 5.0, 0.7)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, hybrid: bool) -> void:
	vfx.water_contact(event, attacker, 1.15 if heavy(move) else 1.0, hybrid)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var big := heavy(move)
	var hybrid: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var gather := clampf((t - 1.0) / 4.0, 0.0, 1.0) * (1.0 - clampf(t - start, 0.0, 1.0))
	if gather > 0.0:
		vfx.blade_water(canvas, layer, actor, gather, hybrid)
	if layer == Kit.LIGHT:
		var flash := sin(clampf((t - start + 4.0) / 5.0, 0.0, 1.0) * PI)
		if flash > 0.02:
			vfx.body_flash(canvas, f, actor, Color(0.30, 0.55, 1.0) * flash * 0.85)
	_draw_takeoff(canvas, layer, f, t - start, big)
	var lead := head(t, move)
	var erosion := tail(t, move)
	if lead <= 0.0 or erosion >= 1.2:
		return
	var at := frame(f, t)
	vfx.set_base(canvas, vfx.frame_transform(at.x, at.y, at.facing))
	var path := ring(big)
	match layer:
		Kit.WATER:
			vfx.water_body(canvas, path, lead, erosion, hybrid, f.attack_instance, 1.4)
		Kit.SOLID:
			vfx.foam_crest(canvas, path, lead, erosion, 11 if big else 9, 0.28, 0.44)
		Kit.FLAME:
			# Pale sword light just outside the water.
			var rim := PackedVector2Array()
			var widths := PackedFloat32Array()
			var tint := PackedColorArray()
			for n in range(48):
				var u := lead * n / 47.0
				rim.append(path.point(u, path.width(u) * 0.5 + 2.4))
				widths.append(3.4 * sin(clampf(u, 0.02, 0.98) * PI))
				tint.append(Color(0.6, 0.72, 0.9, smoothstep(erosion - 0.3, erosion, u)))
			Ribbon.draw(canvas, rim, widths, tint, vfx.band)
		Kit.LIGHT:
			vfx.glow_along(canvas, path, lead, erosion, Color(Kit.WATER_GLOW, 0.14 if hybrid else 0.2), 2.4)
			if lead < 1.0:
				# Bright bead of light riding the leading edge.
				var tip: Vector2 = path.point(lead, path.width(lead) * 0.2)
				canvas.draw_texture_rect(vfx.glow, Rect2(tip - Vector2.ONE * 14.0, Vector2.ONE * 28.0), false, Color(0.75, 0.9, 1.0, 0.55))

## Water washed across the floor under the take-off.
func _draw_takeoff(canvas: Node2D, layer: int, f: RefCounted, age: float, big: bool) -> void:
	var spot: Dictionary = _takeoff.get(f.slot, {})
	if layer not in [Kit.WATER, Kit.LIGHT] or int(spot.get("instance", -1)) != f.attack_instance:
		return
	vfx.set_base(canvas, vfx.frame_transform(spot.x, spot.y, spot.facing))
	vfx.ground_streak(canvas, layer, age, 54.0 if big else 46.0, 4.2 if big else 3.6, -26.0)
