extends "res://scripts/presentation/vfx/zenitsu/technique.gd"
## 霹雳一闪·神速 (MAX): through the super freeze a white-gold pillar and a dense
## sphere of lightning build round him; the release is one massive beam that
## runs on past him, its head a huge starburst, thick bolts racing along it; the
## beam erodes slowly behind a fan of gold rays.

const HEIGHT := -36.0
## The light runs this far ahead of Zenitsu.
const OVERSHOOT := 80.0

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 163 + f.slot * 7919 + tick * 31
	mark_origin(f, tick, move.startup - 1)
	if tick < move.startup:
		vfx.mote_burst(vfx.world(f, Vector2(0.0, -40.0)), 4, 70.0, seed, awake)
		return
	if tick == move.startup:
		var feet: Vector2 = vfx.world(f, Vector2(0.0, -2.0))
		vfx.spark_burst(feet, 26, Vector2(-1.0, -0.4) * float(f.facing), 100.0, 280.0, seed + 1)
		vfx.debris_burst(feet, 8, Vector2(-float(f.facing) * 0.6, 0.0), seed + 2)
	if tick == move.startup + move.active:
		var head: Vector2 = vfx.world(f, Vector2(OVERSHOOT, HEIGHT))
		vfx.bursts.append({"kind": "rays", "at": head, "age": 0.0, "life": 0.35, "size": 220.0, "facing": float(f.facing), "seed": seed})
		vfx.spark_burst(head, 24, Vector2(1.0, -0.2), 100.0, 260.0, seed + 3)

## Repeated cuts flash small so the beams stay readable; the last one lands big.
func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.5 if last else 0.5, awakened, last)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var seed: int = f.attack_instance * 67 + f.move_frame
	if t < start + 1.0:
		var k := clampf(charge_age(f) / float(move.freeze_frames + move.startup), 0.0, 1.0)
		vfx.pillar(canvas, layer, Vector2(0.0, -60.0), 220.0, 70.0, k, awake, seed)
		vfx.sphere(canvas, layer, Vector2(2.0, -38.0), lerpf(30.0, 52.0, k), k, awake, seed + 3)
		if layer == Kit.LIGHT:
			vfx.body_flash(canvas, f, actor, Color(Kit.WHITE, 0.5 * k))
		if t < start:
			return
	var tail := origin_local(f, HEIGHT)
	var reach := clampf((t - start + 1.0) / 3.0, 0.0, 1.0)
	var head := Vector2(lerpf(10.0, OVERSHOOT, reach), HEIGHT)
	var erosion := clampf((t - start - move.active) / 18.0, 0.0, 1.0)
	var from := tail.lerp(head, erosion)
	var alpha := 1.0 - smoothstep(0.7, 1.0, erosion)
	var running: bool = t < start + move.active
	vfx.beam(canvas, layer, from, head, 26.0, alpha, awake, seed, running)
	for n in range(3):
		var offset := Vector2(0.0, (n - 1) * 9.0)
		vfx.bolt(canvas, layer, Bolt.path(from + offset, head + offset, seed + n * 17, 0.07, 5), 2.2, awake, alpha)
	if running and layer == Kit.FRONT:
		vfx.speed_lines(canvas, from, head, seed, 12, 1.0)
	if running and layer == Kit.LIGHT:
		vfx.body_flash(canvas, f, actor, Color(Kit.WHITE, 0.6))
