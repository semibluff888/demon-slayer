extends "res://scripts/presentation/vfx/tanjiro/technique.gd"
## 生生流转 (super): water gathers round Tanjiro through the super freeze, then
## a water dragon pours forward from his blade, its body a bundle of brush
## strands that keeps undulating through all four cuts before it unravels from
## the tail and the head bursts into spray.

## Head sprite size in local units; the neck is cut off at the sprite's left.
const HEAD_HEIGHT := 46.0
## Flame pieces in the mane while awakened: position on the head sprite (0..1)
## and size relative to the head height.
const MANE_FLAMES := [[0.22, 0.3, 0.42], [0.4, 0.18, 0.36], [0.55, 0.32, 0.3], [0.3, 0.62, 0.34], [0.12, 0.5, 0.4]]

func body(t: float, move: Resource) -> Paths.Wave:
	var age: float = t - move.startup
	var reach := 1.0 - pow(1.0 - clampf(age / 5.0, 0.0, 1.0), 3.0)
	var head_x := lerpf(16.0, 112.0, reach) + 4.0 * sin(age * 0.8)
	return Paths.Wave.new(-26.0, head_x, -42.0, 19.0, 1.25, -age * 0.55, 25.0)

func lead(t: float, move: Resource) -> float:
	return clampf((t - move.startup + 0.5) / 2.0, 0.0, 1.0)

func tail(t: float, move: Resource) -> float:
	return clampf((t - move.startup - move.active + 6.0) / 12.0, 0.0, 1.25)

## The swirl gathering round the body before the dragon is released, tightening
## as the charge `k` (0..1) fills.
func swirl(age: float, k: float, radius: float = 40.0) -> Paths.Helix:
	var coil := Paths.Helix.new(Vector2(4.0, 0.0), lerpf(radius, radius * 0.55, k), -8.0, -64.0, 1.7, age * 0.55, lerpf(4.0, 8.0, k))
	coil.squash = 0.32
	return coil

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var hybrid: bool = actor.form_active()
	var seed: int = f.attack_instance * 157 + f.slot * 7919 + tick * 29
	var start: int = move.startup
	if tick < start:
		gather_beads(f, actor, tick, seed)
		return
	if tick == start:
		# The gathered water lets go.
		var centre: Vector2 = vfx.world(f, Vector2(6.0, -40.0))
		vfx.bursts.append({"kind": "ring", "at": centre, "age": 0.0, "life": 0.16, "size": 30.0, "tone": Color(0.7, 0.9, 1.0)})
		vfx.droplets(centre, 26, Vector2(0.6, -0.2), 90.0, 220.0, seed + 9)
		vfx.mist_burst(centre, 6, 40.0, seed + 10)
	var t := float(tick)
	var path := body(t, move)
	var erosion := tail(t, move)
	var head_at: Vector2 = path.point(1.0, 0.0)
	if tick in Array(move.hit_frames):
		# Each cut surges through the head.
		vfx.foam_burst(vfx.world(f, head_at), 6, Vector2(1, -0.2), 60.0, 140.0, seed + 1)
		vfx.droplets(vfx.world(f, head_at), 16, Vector2(1, -0.3), 80.0, 200.0, seed + 2)
		if hybrid:
			vfx.petal_burst(vfx.world(f, head_at), 10, 100.0, seed + 3)
	if erosion < 1.0:
		for n in range(4):
			var u := lerpf(maxf(erosion, 0.1), 1.0, vfx.rand(seed, n + 10))
			var spot: Vector2 = path.point(u, path.width(u) * (vfx.rand(seed, n + 20) - 0.5))
			vfx.drops.spawn(vfx.world(f, spot), vfx.world_dir(f, Vector2(lerpf(-40.0, 60.0, vfx.rand(seed, n + 30)), -lerpf(30.0, 120.0, vfx.rand(seed, n + 40)))),
				lerpf(0.3, 0.5, vfx.rand(seed, n + 50)), lerpf(1.4, 3.0, vfx.rand(seed, n + 60)), 0, Color.WHITE, 360.0, 0.6, 0.0, 0.0, 0.7, 0.8)
		vfx.mist.spawn(vfx.world(f, path.point(maxf(erosion, 0.05), 0.0)), vfx.world_dir(f, Vector2(-30.0, -6.0)), 0.45, 11.0, 0, Kit.WATER_MIST, 0.0, 1.5, 0.0, 0.0, 1.8)
		vfx.foam.spawn(vfx.world(f, head_at + Vector2(-6.0, -HEAD_HEIGHT * 0.3)), vfx.world_dir(f, Vector2(-50.0, -30.0)), 0.3, lerpf(5.0, 7.0, vfx.rand(seed, 70)),
			Kit.SPRAY_CELLS[tick % Kit.SPRAY_CELLS.size()], Color.WHITE, 180.0, 1.5, vfx.rand(seed, 71) * TAU, 4.0, 0.8)
		if hybrid:
			var u := lerpf(maxf(erosion, 0.1), 1.0, vfx.rand(seed, 80))
			vfx.petals.spawn(vfx.world(f, path.point(u, 0.0)), vfx.world_dir(f, Vector2(-20.0, -50.0)), 0.5, lerpf(5.0, 8.0, vfx.rand(seed, 81)),
				Kit.PETAL_CELLS[tick % Kit.PETAL_CELLS.size()], Color.WHITE, -50.0, 1.5, vfx.rand(seed, 82) * TAU, 5.0, 0.7)
	if tick == start + move.active + 4:
		# The head bursts as the body runs out.
		vfx.foam_burst(vfx.world(f, head_at), 10, Vector2(0.6, -0.4), 50.0, 150.0, seed + 5)
		vfx.droplets(vfx.world(f, head_at), 30, Vector2(0.5, -0.4), 70.0, 220.0, seed + 6)
		vfx.mist_burst(vfx.world(f, head_at), 7, 34.0, seed + 7)
		if hybrid:
			vfx.petal_burst(vfx.world(f, head_at), 14, 110.0, seed + 8)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, hybrid: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.water_contact(event, attacker, 1.3 if last else 0.9, hybrid)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var hybrid: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	if t < start + 1.0:
		_draw_charge(canvas, layer, f, actor, t - start, hybrid)
	var reveal := lead(t, move)
	var erosion := tail(t, move)
	if reveal <= 0.0 or erosion >= 1.2:
		return
	var path := body(t, move)
	var head_fade := 1.0 - smoothstep(0.6, 0.95, erosion)
	match layer:
		Kit.WATER:
			vfx.water_body(canvas, path, reveal, erosion, hybrid, f.attack_instance, 1.6)
		Kit.SOLID:
			vfx.foam_crest(canvas, path, reveal, erosion, 13, 0.2, 0.46)
			if reveal >= 1.0 and head_fade > 0.0:
				_draw_head(canvas, path, head_fade, hybrid, f.attack_instance)
		Kit.FLAME:
			var rim := PackedVector2Array()
			var widths := PackedFloat32Array()
			var tint := PackedColorArray()
			for n in range(40):
				var u := reveal * n / 39.0
				rim.append(path.point(u, path.width(u) * 0.52 + 2.0))
				widths.append(3.2 * sin(clampf(u, 0.02, 0.98) * PI))
				tint.append(Color(0.6, 0.72, 0.9, smoothstep(erosion - 0.3, erosion, u)))
			Ribbon.draw(canvas, rim, widths, tint, vfx.band)
		Kit.LIGHT:
			vfx.glow_along(canvas, path, reveal, erosion, Color(Kit.WATER_GLOW, 0.14 if hybrid else 0.2), 2.4)
			var head_at: Vector2 = path.point(1.0, 0.0)
			canvas.draw_texture_rect(vfx.glow, Rect2(head_at - Vector2(10, 30), Vector2(56, 56)), false, Color(Kit.WATER_GLOW, 0.3 * head_fade))

func _draw_head(canvas: Node2D, path: Paths.Wave, fade: float, hybrid: bool, instance: int) -> void:
	var sprite: Texture2D = vfx.textures.get("water-dragon-head")
	if sprite == null:
		return
	var width := HEAD_HEIGHT * sprite.get_width() / sprite.get_height()
	var at: Vector2 = path.point(1.0, 0.0)
	# Sit the neck a little inside the body so the two read as one.
	var head: Transform2D = vfx.base * Transform2D(path.angle(0.98) * 0.6, at)
	var rect := Rect2(-width * 0.16, -HEAD_HEIGHT * 0.56, width, HEAD_HEIGHT)
	canvas.draw_set_transform_matrix(head)
	canvas.draw_texture_rect(sprite, rect, false, Color(1, 1, 1, fade))
	var sheet: Texture2D = vfx.textures.get("hybrid-fire-chips")
	if hybrid and sheet != null:
		var cell := sheet.get_size() / 4.0
		for n in range(MANE_FLAMES.size()):
			var spec: Array = MANE_FLAMES[n]
			var size: float = HEAD_HEIGHT * float(spec[2])
			var spot := rect.position + rect.size * Vector2(spec[0], spec[1])
			var index: int = Kit.PETAL_CELLS[(n * 3 + instance) % Kit.PETAL_CELLS.size()]
			canvas.draw_set_transform_matrix(head * Transform2D(PI + (vfx.rand(instance, n) - 0.5) * 0.8, spot))
			canvas.draw_texture_rect_region(sheet, Rect2(-size * 0.5, -size * 0.5, size, size), Rect2(Vector2(index % 4, index / 4) * cell, cell), Color(1, 1, 1, fade))
	canvas.draw_set_transform_matrix(vfx.base)

## Water gathering round the body through the super freeze and startup.
## `since_release` is negative until the dragon is released.
func _draw_charge(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D, since_release: float, hybrid: bool) -> void:
	var age := charge_age(f)
	var total := float(f.move.freeze_frames + f.move.startup)
	var k := clampf(age / total, 0.0, 1.0)
	var amount := clampf(age / 3.0, 0.0, 1.0) * (1.0 - clampf(since_release, 0.0, 1.0))
	if amount <= 0.0:
		return
	var tint := Color(1, 1, 1, amount)
	match layer:
		Kit.BACK, Kit.WATER:
			var side := -1 if layer == Kit.BACK else 1
			var rows := [0.2, 0.9] if side < 0 else [0.9, 0.2]
			vfx.strand(canvas, swirl(age, k), 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, tint, rows, 30.0, -age * 0.12, null, side, 64)
			vfx.strand(canvas, swirl(age * 1.3 + 2.0, k, 52.0), 1.0, 0.0, 0.0, 0.7, 0.2, 0.9, Color(0.85, 0.92, 1.0, amount * 0.8), rows, 34.0, -age * 0.15, null, side, 64)
			if hybrid:
				vfx.strand(canvas, swirl(age * 1.15 + 3.6, k, 46.0), 1.0, 0.0, 0.0, 0.9, 0.1, 1.0, tint, [0.1, 0.9], 26.0, -age * 0.14, vfx.textures.get("hybrid-fire-strands"), side, 64)
			if layer == Kit.WATER:
				_ripple(canvas, age, k, amount)
		Kit.LIGHT:
			vfx.body_flash(canvas, f, actor, Color(0.25, 0.5, 1.0) * (0.25 + 0.45 * k) * amount)
			var size := lerpf(70.0, 110.0, k)
			canvas.draw_texture_rect(vfx.glow, Rect2(Vector2(6, -40) - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, Color(Kit.WATER_GLOW, (0.25 + 0.35 * k) * amount))
			vfx.lens_streak(canvas, Vector2(14, -40), lerpf(40.0, 90.0, k), 3.0, Color(0.7, 0.88, 1.0, (0.3 + 0.5 * k) * amount))

## Rings of water spreading over the floor under the stance.
func _ripple(canvas: Node2D, age: float, k: float, amount: float) -> void:
	for n in range(2):
		var grow := fposmod(age / 12.0 + n * 0.5, 1.0)
		var ring := Paths.Arc.new(Vector2(4.0, -1.0), 0.0, TAU, lerpf(14.0, 56.0, grow), lerpf(14.0, 56.0, grow), 3.0)
		ring.squash = 0.16
		ring.profile = "even"
		vfx.strand(canvas, ring, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, Color(0.9, 0.97, 1.0, amount * (1.0 - grow) * (0.5 + 0.5 * k)), [0.3, 0.8], 40.0, n * 0.37, null, 0, 40)
