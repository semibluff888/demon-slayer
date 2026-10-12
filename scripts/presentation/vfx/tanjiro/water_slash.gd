extends "res://scripts/presentation/vfx/tanjiro/technique.gd"
## 水面斩 (236A/C): an overhead crescent of water strands from behind the head
## to low in front, which releases a standing crescent wave.

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var big := heavy(move)
	var hybrid: bool = actor.form_active()
	var seed: int = f.attack_instance * 131 + f.slot * 7919 + tick * 17
	var start: int = move.startup
	if tick >= 3 and tick < start:
		gather_beads(f, actor, tick, seed)
	var arc := sweep(actor, big)
	if tick == start:
		# The cut flings spray off its outer edge along the swing.
		for n in range(34 if big else 26):
			var u: float = 0.15 + 0.85 * vfx.rand(seed, n)
			var angle: float = lerpf(arc.a0, arc.a1, u)
			var local := arc.point(u, arc.width(u) * lerpf(0.1, 0.55, vfx.rand(seed, n + 20)))
			var velocity := Vector2(-sin(angle), cos(angle)) * lerpf(80.0, 230.0, vfx.rand(seed, n + 40)) + Vector2.from_angle(angle) * lerpf(30.0, 110.0, vfx.rand(seed, n + 80))
			vfx.drops.spawn(vfx.world(f, local), vfx.world_dir(f, velocity), lerpf(0.3, 0.55, vfx.rand(seed, n + 120)), lerpf(1.6, 3.6, vfx.rand(seed, n + 160)), 0, Color.WHITE,
				340.0, 0.8, 0.0, 0.0, 0.7, 0.9)
		for n in range(8 if big else 6):
			var u: float = 0.55 + 0.45 * vfx.rand(seed, n + 200)
			var angle: float = lerpf(arc.a0, arc.a1, u)
			vfx.foam.spawn(vfx.world(f, arc.point(u, arc.width(u) * 0.45)), vfx.world_dir(f, Vector2(-sin(angle), cos(angle)) * 70.0 + Vector2.from_angle(angle) * 40.0),
				lerpf(0.25, 0.4, vfx.rand(seed, n + 220)), lerpf(5.0, 8.0, vfx.rand(seed, n + 240)) * (1.2 if big else 1.0), Kit.SPRAY_CELLS[n % Kit.SPRAY_CELLS.size()], Color.WHITE,
				200.0, 1.5, vfx.rand(seed, n + 260) * TAU, vfx.rand(seed, n + 280) * 6.0 - 3.0, 0.8)
		# Spray kicked up along the ground in front of the stance.
		var reach := 74.0 if big else 58.0
		for n in range(14):
			vfx.drops.spawn(vfx.world(f, Vector2(lerpf(6.0, reach, vfx.rand(seed, n + 400)), -1.0)), vfx.world_dir(f, Vector2(lerpf(20.0, 70.0, vfx.rand(seed, n + 420)), -lerpf(40.0, 120.0, vfx.rand(seed, n + 440)))),
				lerpf(0.3, 0.5, vfx.rand(seed, n + 460)), lerpf(1.5, 3.0, vfx.rand(seed, n + 480)), 0, Color.WHITE, 380.0, 0.5, 0.0, 0.0, 0.7, 0.8)
		if hybrid:
			for n in range(24 if big else 20):
				var u: float = 0.1 + 0.9 * vfx.rand(seed, n + 500)
				var angle: float = lerpf(arc.a0, arc.a1, u)
				vfx.petals.spawn(vfx.world(f, arc.point(u, arc.width(u) * (vfx.rand(seed, n + 510) - 0.5))), vfx.world_dir(f, Vector2.from_angle(angle) * lerpf(40.0, 90.0, vfx.rand(seed, n + 520)) + Vector2(0, -30)),
					lerpf(0.45, 0.75, vfx.rand(seed, n + 540)), lerpf(5.0, 9.0, vfx.rand(seed, n + 560)), Kit.PETAL_CELLS[n % Kit.PETAL_CELLS.size()], Color.WHITE, -40.0, 1.5,
					vfx.rand(seed, n + 580) * TAU, vfx.rand(seed, n + 600) * 8.0 - 4.0, 0.7)
	if tick > start + 2 and tick <= start + 17:
		# The crescent breaks into droplets where it erodes, tail first.
		var u := clampf(float(tick - start - 3) / 14.0, 0.0, 1.0)
		var angle: float = lerpf(arc.a0, arc.a1, u)
		var outward := Vector2.from_angle(angle)
		for n in range(4):
			var local := arc.point(u, arc.width(u) * (vfx.rand(seed, n) - 0.5))
			vfx.drops.spawn(vfx.world(f, local), vfx.world_dir(f, outward * lerpf(10.0, 50.0, vfx.rand(seed, n + 10)) + Vector2(-sin(angle), cos(angle)) * 30.0),
				lerpf(0.3, 0.5, vfx.rand(seed, n + 20)), lerpf(1.3, 2.6, vfx.rand(seed, n + 30)), 0, Color.WHITE, 260.0, 0.8)
		if tick % 2 == 0:
			vfx.foam.spawn(vfx.world(f, arc.point(u, 0.0)), vfx.world_dir(f, outward * 20.0 + Vector2(0, 15)), 0.32, lerpf(4.0, 6.5, vfx.rand(seed, 40)),
				(Kit.CLOUD_CELLS + Kit.SPRAY_CELLS)[tick % 8], Color.WHITE, 120.0, 2.0, vfx.rand(seed, 41) * TAU, 0.0, 0.7)
			vfx.mist.spawn(vfx.world(f, arc.point(u, 0.0)), vfx.world_dir(f, outward * 14.0), 0.4, 8.0, 0, Kit.WATER_MIST, 0.0, 2.0, 0.0, 0.0, 1.8)
		if hybrid:
			# The flame burns off with the water, a little ahead of it.
			for n in range(2):
				var across: float = arc.width(u) * (vfx.rand(seed, 72 + n) - 0.5)
				vfx.petals.spawn(vfx.world(f, arc.point(minf(u + 0.04, 1.0), across)), vfx.world_dir(f, outward * lerpf(20.0, 45.0, vfx.rand(seed, 74 + n)) + Vector2(0, -25)),
					lerpf(0.42, 0.55, vfx.rand(seed, 76 + n)), lerpf(5.0, 7.0, vfx.rand(seed, 78 + n)), Kit.PETAL_CELLS[(tick + n * 5) % Kit.PETAL_CELLS.size()], Color.WHITE,
					-50.0, 1.5, vfx.rand(seed, 70 + n * 9) * TAU, 5.0, 0.7)
			vfx.petals.spawn(vfx.world(f, arc.point(u, 2.0)), vfx.world_dir(f, outward * 50.0 + Vector2(0, -40)), 0.38, 3.5, Kit.SPARK_CELLS[tick % Kit.SPARK_CELLS.size()], Color.WHITE,
				-80.0, 1.0, vfx.rand(seed, 71) * TAU, 0.0, 0.6)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, hybrid: bool) -> void:
	vfx.water_contact(event, attacker, 1.2 if heavy(move) else 1.0, hybrid)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var big := heavy(move)
	var hybrid: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	# Water gathers along the raised blade, then leaves with the cut.
	var gather := clampf((t - 2.0) / 5.0, 0.0, 1.0) * (1.0 - clampf(t - start, 0.0, 1.0))
	if gather > 0.0:
		vfx.blade_water(canvas, layer, actor, gather, hybrid)
	if layer == Kit.LIGHT:
		# Activation glint on the body, as each breathing form begins.
		var flash := sin(clampf((t - start + 4.0) / 5.0, 0.0, 1.0) * PI)
		if flash > 0.02:
			vfx.body_flash(canvas, f, actor, Color(0.30, 0.55, 1.0) * flash * 0.85)
	var head := clampf((t - start + 0.5) / 1.5, 0.0, 1.0)
	var tail := clampf((t - start - 3.0) / 14.0, 0.0, 1.25)
	if head <= 0.0 or tail >= 1.2:
		return
	var arc := sweep(actor, big)
	var reach := 74.0 if big else 58.0
	match layer:
		Kit.WATER:
			vfx.water_body(canvas, arc, head, tail, hybrid, f.attack_instance)
			vfx.ground_streak(canvas, layer, t - start, reach, 4.5 if big else 3.6)
		Kit.SOLID:
			vfx.foam_crest(canvas, arc, head, tail, 9 if big else 7)
		Kit.FLAME:
			# Pale sword light just outside the water, as in the reference.
			var rim := PackedVector2Array()
			var rim_widths := PackedFloat32Array()
			var rim_tint := PackedColorArray()
			for n in range(40):
				var u := head * n / 39.0
				rim.append(arc.point(u, arc.width(u) * 0.5 + 2.2))
				rim_widths.append(3.6 * sin(clampf(u, 0.02, 0.98) * PI))
				rim_tint.append(Color(0.6, 0.72, 0.9, smoothstep(tail - 0.3, tail, u)))
			Ribbon.draw(canvas, rim, rim_widths, rim_tint, vfx.band)
		Kit.LIGHT:
			# Blue light even when awakened: orange added over blue water washes it pale.
			vfx.glow_along(canvas, arc, head, tail, Color(Kit.WATER_GLOW, 0.14 if hybrid else 0.2), 2.4)
			vfx.ground_streak(canvas, layer, t - start, reach, 4.5 if big else 3.6)

## Overhead cut from the raised drawing to the low finish, centred between the
## two hilt positions so the water hugs the drawn sword in both forms.
func sweep(actor: Node2D, big: bool) -> Paths.Arc:
	var raised: PackedVector2Array = vfx.blade_pose(actor, "water_slash", 2)
	var low: PackedVector2Array = vfx.blade_pose(actor, "water_slash", 3)
	var tip0 := Vector2(-27.5, -58.7)
	var tip1 := Vector2(39.6, -17.3)
	var pivot := Vector2(3.0, -44.0)
	if raised.size() == 2 and low.size() == 2:
		tip0 = actor.canvas_to_local(raised[1])
		tip1 = actor.canvas_to_local(low[1])
		pivot = (actor.canvas_to_local(raised[0]) + actor.canvas_to_local(low[0])) * 0.5
	var a0 := (tip0 - pivot).angle()
	var a1 := (tip1 - pivot).angle()
	while a1 <= a0:
		a1 += TAU
	var scale := 1.18 if big else 1.0
	var path := Paths.Arc.new(pivot, a0, a1, (tip0 - pivot).length() * scale, (tip1 - pivot).length() * scale, 26.0 if big else 21.0)
	path.bulge = 0.1
	path.profile = "crescent"
	return path

# --- Released crescent wave --------------------------------------------------------

static func wave_height(big: bool) -> float:
	return 64.0 if big else 54.0

func emit_projectile(p: Dictionary, move: Resource, tick: int, age: int) -> void:
	var big := heavy(move)
	var hybrid: bool = vfx.awakened(int(p.owner))
	var seed: int = int(p.instance) * 613 + tick * 29
	var facing := float(p.facing)
	var height := wave_height(big)
	var at := Vector2(float(p.x) - float(p.vx) * (age - tick), float(p.y))
	# Spray off the crest and droplets falling from the base as it travels.
	for n in range(3):
		var y: float = (vfx.rand(seed, n) - 0.5) * height * 0.85
		vfx.drops.spawn(at + Vector2(facing * height * 0.05, y), Vector2(facing * lerpf(-40.0, 30.0, vfx.rand(seed, n + 3)), -lerpf(0.0, 70.0, vfx.rand(seed, n + 6))),
			lerpf(0.25, 0.45, vfx.rand(seed, n + 9)), lerpf(1.3, 2.8, vfx.rand(seed, n + 12)), 0, Color.WHITE, 360.0, 0.6, 0.0, 0.0, 0.7, 0.6)
	vfx.mist.spawn(at + Vector2(-facing * height * 0.2, (vfx.rand(seed, 20) - 0.5) * height * 0.7), Vector2(-facing * lerpf(10.0, 30.0, vfx.rand(seed, 21)), 0.0),
		0.3, lerpf(6.0, 10.0, vfx.rand(seed, 22)), 0, Kit.WATER_MIST, 0.0, 1.5, 0.0, 0.0, 1.6)
	if tick % 4 == 0:
		vfx.foam.spawn(at + Vector2(-facing * 3.0, height * 0.32), Vector2(facing * lerpf(-10.0, 20.0, vfx.rand(seed, 30)), -lerpf(10.0, 40.0, vfx.rand(seed, 31))),
			0.35, lerpf(4.0, 6.0, vfx.rand(seed, 32)) * (1.2 if big else 1.0), Kit.SPRAY_CELLS[tick % Kit.SPRAY_CELLS.size()], Color.WHITE, 300.0, 0.5, vfx.rand(seed, 33) * TAU, 2.0, 0.8)
	if hybrid:
		for n in range(2 if tick % 2 == 0 else 1):
			vfx.petals.spawn(at + Vector2(-facing * height * lerpf(0.1, 0.35, vfx.rand(seed, 45 + n)), (vfx.rand(seed, 40 + n * 7) - 0.5) * height * 0.7),
				Vector2(-facing * lerpf(20.0, 50.0, vfx.rand(seed, 41 + n * 7)), -lerpf(10.0, 40.0, vfx.rand(seed, 42 + n * 7))), 0.4, lerpf(4.5, 7.5, vfx.rand(seed, 43 + n * 7)),
				Kit.FLAME_CELLS[(tick + n * 7) % Kit.FLAME_CELLS.size()], Color.WHITE, -60.0, 1.2, vfx.rand(seed, 44 + n * 7) * TAU, 4.0, 0.7)

func release_projectile(record: Dictionary) -> void:
	var at := Vector2(float(record.x), float(record.y))
	var seed: int = int(record.instance) * 389
	var big: bool = String(record.move).ends_with("C")
	vfx.droplets(at, 22 if big else 16, Vector2(record.facing, 0), 50.0, 140.0, seed)
	vfx.foam_burst(at, 5 if big else 4, Vector2(record.facing, 0), 30.0, 70.0, seed + 1)
	vfx.mist_burst(at, 6, 30.0, seed + 3)
	if vfx.awakened(int(record.owner)):
		vfx.petal_burst(at, 9, 60.0, seed + 7)

## The released crescent wave, in projectile-local units (+x forward).
func draw_projectile(canvas: Node2D, layer: int, p: Dictionary, move: Resource) -> void:
	var big := heavy(move)
	var hybrid: bool = vfx.awakened(int(p.owner))
	var age: float = float(move.projectile_lifetime - int(p.life)) + vfx.frac
	var remaining: float = float(p.life) - vfx.frac
	var grow := 1.0 - pow(1.0 - clampf(age / 3.0, 0.0, 1.0), 3.0)
	var fade := clampf(remaining / 8.0, 0.0, 1.0)
	var height := wave_height(big) * lerpf(0.55, 1.0, grow) * (1.0 + 0.04 * sin(vfx.time * 28.0)) * (1.0 + (1.0 - fade) * 0.2)
	var texture: Texture2D = vfx.textures.get("water-crescent-heavy" if big else "water-crescent")
	if texture == null:
		return
	var width := height * texture.get_width() / texture.get_height()
	var traveled: float = absf(float(p.vx)) * age
	var floor_y: float = vfx.combat.FLOOR_Y - float(p.y)
	match layer:
		Kit.WATER:
			# Strands streaming off the back of the wave.
			for k in range(4):
				var y := (-0.36 + 0.24 * k) * height
				var length := minf(12.0 + age * 3.0, 36.0) * (0.7 + 0.15 * k)
				var points := PackedVector2Array([Vector2(-width * 0.25, y), Vector2(-width * 0.25 - length * 0.5, y + 1.5), Vector2(-width * 0.25 - length, y + 3.0)])
				Ribbon.draw(canvas, points, PackedFloat32Array([3.4, 2.2, 0.2]), PackedColorArray([Color(1, 1, 1, fade), Color(1, 1, 1, fade), Color(1, 1, 1, fade * 0.4)]),
					vfx.textures.get("water-strands"), 22.0, -vfx.time * 3.0 + k * 0.3, 0.3, 0.9)
			_wave_trail(canvas, layer, traveled, floor_y, fade)
		Kit.SOLID:
			canvas.draw_texture_rect(texture, Rect2(-width * 0.62, -height * 0.5, width, height), false, Color(1, 1, 1, fade))
		Kit.FRONT:
			if hybrid:
				# Flame braided through the wave, opaque so it reads as fire on water.
				for k in range(3):
					var core := Ribbon.arc(Vector2(-height * (0.52 + 0.08 * k), 0.0), Vector2(height * (0.5 + 0.06 * k), height * 0.44), -0.9 + 0.1 * k, 0.9 - 0.05 * k, 18)
					var widths := PackedFloat32Array()
					var tint := PackedColorArray()
					for n in range(core.size()):
						widths.append(height * (0.15 - 0.035 * k) * sin(clampf(n / 17.0, 0.05, 0.95) * PI))
						tint.append(Color(1, 1, 1, fade))
					Ribbon.draw(canvas, core, widths, tint, vfx.textures.get("hybrid-fire-strands"), height * 0.9, -vfx.time * (2.0 + k), 0.1, 0.9)
		Kit.LIGHT:
			canvas.draw_texture_rect(vfx.glow, Rect2(-height * 0.7, -height * 0.65, height * 1.3, height * 1.3), false, Color(Kit.FIRE_GLOW if hybrid else Kit.WATER_GLOW, 0.3 * fade))
			_wave_trail(canvas, layer, traveled, floor_y, fade)

func _wave_trail(canvas: Node2D, layer: int, traveled: float, floor_y: float, fade: float) -> void:
	var span := minf(traveled + 6.0, 70.0)
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(12):
		var u := n / 11.0
		points.append(Vector2(lerpf(-span, 4.0, u), floor_y - 0.6))
		widths.append(3.2 * sin(clampf(u, 0.04, 0.96) * PI))
		tint.append(Color(1, 1, 1, smoothstep(0.0, 0.5, u) * fade))
	if layer == Kit.WATER:
		Ribbon.draw(canvas, points, widths, tint, vfx.textures.get("water-strands"), 26.0, -vfx.time * 2.0, 0.2, 0.9)
	else:
		var wide := PackedFloat32Array()
		var soft := PackedColorArray()
		for n in range(points.size()):
			wide.append(widths[n] * 2.8)
			soft.append(Color(0.45, 0.85, 1.0, 0.35 * tint[n].a))
		Ribbon.draw(canvas, points, wide, soft, vfx.band)
