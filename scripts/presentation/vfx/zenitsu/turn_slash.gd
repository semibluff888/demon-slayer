extends "res://scripts/presentation/vfx/zenitsu/technique.gd"
## 居合·回身斩 (214B/D): he slips back, then turns with the draw. The first cut
## throws a flat ring of lightning round his waist (the far half behind both
## fighters, as the four-way slash does in the reference); the second is a wide gold sweep.

func hits(move: Resource) -> Array:
	return Array(move.hit_frames) if move.hit_frames.size() >= 2 else [move.startup, move.startup + move.active / 2]

func sweep(move: Resource) -> Paths.Sweep:
	var reach := 96.0 if heavy(move) else 86.0
	return Paths.Sweep.new(Vector2(-26.0, -48.0), Vector2(reach * 0.75, -66.0), Vector2(reach, -22.0), 14.0 if heavy(move) else 12.0)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 139 + f.slot * 7919 + tick * 17
	var list := hits(move)
	if tick == int(list[0]):
		vfx.mote_burst(vfx.world(f, Vector2(10.0, -30.0)), 8, 70.0, seed, awake)
	if tick == int(list[1]):
		vfx.spark_burst(vfx.world(f, Vector2(70.0, -40.0)), 14, Vector2(1.0, -0.3), 90.0, 220.0, seed + 1)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var list := hits(move)
	var first := float(list[0])
	var second := float(list[1])
	var seed: int = f.attack_instance * 43 + f.move_frame
	if t < first and layer == Kit.LIGHT:
		# A cold electric outline on the body as he slips back.
		vfx.body_flash(canvas, f, actor, Color(Kit.bolt_glow(awake), 0.3 * clampf(t / maxf(first, 1.0), 0.0, 1.0)))
	var ring_age := t - first
	if ring_age >= 0.0 and ring_age < 12.0:
		var k := ring_age / 12.0
		var spread := 0.6 + 0.4 * (1.0 - pow(1.0 - k, 2.0))
		var reach := 82.0 if heavy(move) else 72.0
		vfx.lightning_ring(canvas, layer, Vector2(8.0, -30.0), Vector2(reach, 15.0) * spread, 1.0 - smoothstep(0.55, 1.0, k), awake, seed)
	var lead := clampf((t - second + 1.0) / 2.5, 0.0, 1.0)
	var erosion := clampf((t - second - 2.0) / 9.0, 0.0, 1.25)
	if lead > 0.0 and erosion < 1.0:
		vfx.crescent(canvas, layer, sweep(move), lead, erosion, "gold", awake, seed)
