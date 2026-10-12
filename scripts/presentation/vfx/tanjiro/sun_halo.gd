extends "res://scripts/presentation/vfx/tanjiro/technique.gd"
## 碧罗之天 (MAX): pure Hinokami Kagura in either form. Sun heat gathers through
## the super freeze, a gold flare marks the release, and the backflip draws
## concentric tilted rings of flame (white-yellow core, orange body, red rim)
## that stay where they were drawn, cool to thin crimson bands and break into
## crimson flame pieces and embers.

## Rings: centre, radius, squash, tilt, thickness, start angle, loop length (in
## turns) and how many frames after the first ring each one starts.
const RINGS := [
	{"centre": Vector2(40, -46), "radius": 60.0, "squash": 0.62, "tilt": -0.22, "thick": 21.0, "from": 0.9, "turns": 1.05, "delay": 0.0},
	{"centre": Vector2(44, -48), "radius": 78.0, "squash": 0.58, "tilt": -0.3, "thick": 12.0, "from": 1.3, "turns": 1.0, "delay": 1.0},
	{"centre": Vector2(36, -45), "radius": 44.0, "squash": 0.66, "tilt": -0.14, "thick": 9.0, "from": 0.6, "turns": 0.8, "delay": 0.5},
]
const CRIMSON := Color(0.86, 0.22, 0.18)

func ring(spec: Dictionary) -> Paths.Arc:
	var a0: float = spec.from
	var path := Paths.Arc.new(spec.centre, a0, a0 - TAU * float(spec.turns), spec.radius, spec.radius, spec.thick)
	path.squash = spec.squash
	path.tilt = spec.tilt
	return path

func head(t: float, move: Resource, spec: Dictionary) -> float:
	return clampf((t - move.startup - float(spec.delay) + 0.6) / 3.0, 0.0, 1.0)

## 0 burning, 1 cooled to a thin crimson band.
func cool(t: float, move: Resource) -> float:
	return clampf((t - move.startup - 6.0) / 8.0, 0.0, 1.0)

func tail(t: float, move: Resource) -> float:
	return clampf((t - move.startup - 10.0) / 16.0, 0.0, 1.25)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var seed: int = f.attack_instance * 163 + f.slot * 7919 + tick * 31
	var start: int = move.startup
	anchor(f, tick)
	var at := frame(f, tick)
	if tick < start:
		# Embers drawn in toward the blade.
		var held: PackedVector2Array = vfx.blade(actor, actor.move_clip_frame(tick) if actor.clip == move.clip_id() else actor.frame_index)
		var target := held[1] if held.size() == 2 else Vector2(10, -50)
		for n in range(2):
			var offset := Vector2.from_angle(vfx.rand(seed, n) * TAU) * lerpf(16.0, 30.0, vfx.rand(seed, n + 3))
			vfx.embers.spawn(vfx.world(f, target + offset), vfx.world_dir(f, -offset) / 0.3, 0.3, lerpf(3.0, 5.0, vfx.rand(seed, n + 5)), Kit.SUN_SPARK_CELLS[n % 4], Color.WHITE)
		return
	var t := float(tick)
	if tick == start:
		var centre: Vector2 = vfx.world(at, Vector2(40, -46))
		vfx.ember_burst(centre, 30, 160.0, seed + 1)
		vfx.petal_burst(centre, 10, 110.0, seed + 2)
	var heat := cool(t, move)
	var erosion := tail(t, move)
	for k in range(RINGS.size()):
		var spec: Dictionary = RINGS[k]
		var path := ring(spec)
		var lead := head(t, move, spec)
		if lead > 0.0 and lead < 1.0:
			# Flame thrown off the head of each ring as it is drawn.
			var tip: Vector2 = path.point(lead, path.width(lead) * 0.3)
			for n in range(3):
				var velocity := Vector2.from_angle(path.angle(lead) + (vfx.rand(seed, n + k * 10) - 0.5) * 1.2) * lerpf(60.0, 160.0, vfx.rand(seed, n + k * 10 + 4))
				vfx.embers.spawn(vfx.world(at, tip), vfx.world_dir(at, velocity), lerpf(0.3, 0.5, vfx.rand(seed, n + k * 10 + 6)), lerpf(4.0, 8.0, vfx.rand(seed, n + k * 10 + 8)),
					Kit.SUN_TONGUE_CELLS[(tick + n + k) % Kit.SUN_TONGUE_CELLS.size()], Color.WHITE, -60.0, 1.5, vfx.rand(seed, n + k * 10 + 9) * TAU, 6.0, 0.6)
		if heat > 0.3 and erosion < 1.0 and k < 2:
			# Cooling rings shed crimson flame pieces, densest where they erode.
			for n in range(2):
				var u := clampf(erosion + 0.25 * vfx.rand(seed, n + k * 7 + 40), 0.0, 1.0)
				var spot: Vector2 = path.point(u, path.width(u) * (vfx.rand(seed, n + k * 7 + 41) - 0.5))
				vfx.petals.spawn(vfx.world(at, spot), vfx.world_dir(at, Vector2(lerpf(-30.0, 30.0, vfx.rand(seed, n + k * 7 + 42)), -lerpf(20.0, 60.0, vfx.rand(seed, n + k * 7 + 43)))),
					lerpf(0.45, 0.7, vfx.rand(seed, n + k * 7 + 44)), lerpf(4.0, 7.0, vfx.rand(seed, n + k * 7 + 45)), Kit.FLAME_CELLS[(tick + n) % Kit.FLAME_CELLS.size()], Color.WHITE,
					-30.0, 1.4, vfx.rand(seed, n + k * 7 + 46) * TAU, 4.0, 0.7)

func contact(event: Dictionary, _move: Resource, attacker: RefCounted, _hybrid: bool) -> void:
	vfx.sun_contact(event, attacker, 1.25)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var t := clock(f)
	var start := float(move.startup)
	if t < start + 1.5:
		_draw_charge(canvas, layer, f, actor, t - start)
	var heat := cool(t, move)
	var erosion := tail(t, move)
	if t < start or erosion >= 1.2:
		return
	var at := frame(f, t)
	vfx.set_base(canvas, vfx.frame_transform(at.x, at.y, at.facing))
	var flame: Texture2D = vfx.textures.get("fire-strands")
	var ember: Texture2D = vfx.textures.get("hybrid-fire-strands")
	for k in range(RINGS.size()):
		var spec: Dictionary = RINGS[k]
		var path := ring(spec)
		var lead := head(t, move, spec)
		if lead <= 0.0:
			continue
		match layer:
			Kit.SOLID:
				# Burning band, then a thinner crimson band as it cools.
				if heat < 1.0:
					vfx.strand(canvas, path, lead, erosion, 0.0, 1.0, 0.0, 1.0, Color(1, 1, 1, 1.0 - heat), [0.06, 0.94], path.length / 2.2, -vfx.time * 2.6, flame, 0, 48)
				if heat > 0.0:
					vfx.strand(canvas, path, lead, erosion, 0.05, lerpf(0.9, 0.42, heat), 0.0, 1.0, Color(CRIMSON, heat), [0.15, 0.85], path.length / 2.6, -vfx.time * 1.6, ember, 0, 48)
				if k == 0 and heat < 0.8:
					_tongues(canvas, path, lead, erosion, 1.0 - heat / 0.8, f.attack_instance)
			Kit.LIGHT:
				vfx.glow_along(canvas, path, lead, erosion, Color(Kit.SUN_GLOW, (0.34 if k == 0 else 0.2) * (1.0 - heat * 0.8)), 2.8, 0.0, 48)
				if lead < 1.0:
					var tip: Vector2 = path.point(lead, 0.0)
					canvas.draw_texture_rect(vfx.glow, Rect2(tip - Vector2.ONE * 16.0, Vector2.ONE * 32.0), false, Color(1, 0.86, 0.5, 0.7))

## Flame tongues licking off the outer edge of the main ring.
func _tongues(canvas: Node2D, path: Paths.Arc, lead: float, erosion: float, amount: float, instance: int) -> void:
	var sheet: Texture2D = vfx.textures.get("fire-petals")
	if sheet == null:
		return
	var cell := sheet.get_size() / 4.0
	for n in range(14):
		var u := 0.04 + 0.92 * n / 13.0
		if u > lead:
			break
		var presence := smoothstep(erosion - 0.1, erosion + 0.1, u) * amount
		if presence <= 0.02:
			continue
		var size := path.width(u) * lerpf(0.9, 1.3, vfx.rand(instance, n)) + 4.0
		var at: Vector2 = path.point(u, path.width(u) * 0.55 + size * 0.25)
		var index: int = Kit.SUN_TONGUE_CELLS[(n + instance) % Kit.SUN_TONGUE_CELLS.size()]
		var origin := Vector2(index % 4, index / 4) * cell
		# Tongues lean back along the ring, away from its travel.
		canvas.draw_set_transform_matrix(vfx.base * Transform2D(path.angle(u) + PI * 0.75, at))
		canvas.draw_texture_rect_region(sheet, Rect2(-size * 0.5, -size * 0.5, size, size), Rect2(origin, cell), Color(1, 1, 1, presence))
	canvas.draw_set_transform_matrix(vfx.base)

## Sun heat gathering round the body through the super freeze and startup,
## and the gold flare that marks the release. `since_release` is negative
## until the rings are drawn.
func _draw_charge(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D, since_release: float) -> void:
	var age := charge_age(f)
	var total := float(f.move.freeze_frames + f.move.startup)
	var k := clampf(age / total, 0.0, 1.0)
	var amount := clampf(age / 3.0, 0.0, 1.0) * (1.0 - clampf(since_release / 1.5, 0.0, 1.0))
	if amount <= 0.0:
		return
	match layer:
		Kit.SOLID:
			for n in range(2):
				var spin := age * (0.35 + 0.25 * n) + n * 2.4
				var radius := lerpf(44.0 - n * 8.0, 26.0 - n * 4.0, k)
				var halo := Paths.Arc.new(Vector2(4, -42), spin, spin - TAU * lerpf(0.55, 0.9, k), radius, radius, lerpf(4.0, 7.0, k) - n)
				halo.squash = 0.34
				halo.tilt = -0.15 + 0.3 * n
				vfx.strand(canvas, halo, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, Color(1, 1, 1, amount), [0.1, 0.9], 30.0, -age * 0.15, vfx.textures.get("fire-strands"), 0, 40)
		Kit.LIGHT:
			var release := 1.0 - clampf(absf(since_release + 0.5) / 1.5, 0.0, 1.0)
			vfx.body_flash(canvas, f, actor, Color(1.0, 0.6, 0.2) * ((0.2 + 0.3 * k) * amount + 0.6 * release))
			var size := lerpf(76.0, 120.0, k)
			canvas.draw_texture_rect(vfx.glow, Rect2(Vector2(4, -42) - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, Color(Kit.SUN_GLOW, (0.3 + 0.35 * k) * amount))
			if release > 0.0:
				vfx.lens_streak(canvas, Vector2(10, -46), 130.0, 5.0, Color(1.0, 0.92, 0.7, release))
