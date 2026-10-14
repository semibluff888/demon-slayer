extends "res://scripts/presentation/vfx/zenitsu/technique.gd"
## 霹雳一闪·六连 (super): through the super freeze a gold aura and crackling
## lightning gather round him and a ring of lightning spreads over the floor;
## then each of the six cuts is a dash beam, the six zig-zagging along his path
## with a starburst at every corner, before they erode together.

## Corner heights of the zig-zag above the feet (local units).
const HIGH := -64.0
const LOW := -14.0

func corner(f: RefCounted, move: Resource, index: int) -> Vector2:
	var span: float = move.active * move.travel
	return origin_local(f, 0.0) + Vector2(span * index / 6.0, HIGH if index % 2 == 1 else LOW)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 151 + f.slot * 7919 + tick * 29
	mark_origin(f, tick, move.startup - 1)
	if tick < move.startup:
		vfx.mote_burst(vfx.world(f, Vector2(0.0, -36.0)), 3, 50.0, seed, awake)
		return
	var cuts := Array(move.hit_frames)
	var index := cuts.find(tick)
	if index >= 0:
		var at: Vector2 = vfx.world(f, corner(f, move, index + 1))
		vfx.spark_burst(at, 10, Vector2(1.0, 0.0), 80.0, 200.0, seed + 1)

## Repeated cuts flash small so the beams stay readable; the last one lands big.
func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.25 if last else 0.5, awakened, last)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var seed: int = f.attack_instance * 61 + f.move_frame
	var age := charge_age(f)
	var charging := t < start + 1.0
	if charging:
		var k := clampf(age / float(move.freeze_frames + move.startup), 0.0, 1.0)
		vfx.sphere(canvas, layer, Vector2(2.0, -38.0), lerpf(34.0, 48.0, k), k, awake, seed)
		vfx.lightning_ring(canvas, layer, Vector2(4.0, -2.0), Vector2(lerpf(30.0, 78.0, k), lerpf(6.0, 13.0, k)), k, awake, seed + 7)
		if layer == Kit.LIGHT:
			vfx.body_flash(canvas, f, actor, Color(Kit.GOLD_HOT, 0.45 * k))
		if t < start:
			return
	var cuts := Array(move.hit_frames)
	var last := float(cuts[cuts.size() - 1])
	var fade := 1.0 - clampf((t - last - 6.0) / 12.0, 0.0, 1.0)
	for index in range(cuts.size()):
		var hit := float(cuts[index])
		var reach := clampf((t - hit + 1.0) / 2.0, 0.0, 1.0)
		if reach <= 0.0:
			continue
		# Each beam holds a few frames after its cut, then erodes from its tail.
		var erosion := clampf((t - hit - 8.0) / 8.0, 0.0, 1.0)
		var from := corner(f, move, index)
		var to := corner(f, move, index + 1)
		var head := from.lerp(to, reach)
		var alpha := fade * (1.0 - smoothstep(0.75, 1.0, erosion))
		vfx.beam(canvas, layer, from.lerp(head, erosion), head, 11.0, alpha, awake, seed + index * 13, reach < 1.0)
		vfx.bolt(canvas, layer, Bolt.path(from.lerp(head, erosion), head, seed + index * 7, 0.08, 4), 1.4, awake, alpha)
		var flash := 1.0 - clampf((t - hit) / 5.0, 0.0, 1.0)
		if flash > 0.0 and reach >= 1.0:
			vfx.star(canvas, layer, to, 16.0 + 6.0 * flash, 10, seed + index, flash, Kit.WHITE, Kit.bolt_glow(awake))
	if layer == Kit.FRONT and t < start + move.active:
		vfx.speed_lines(canvas, corner(f, move, 0), Vector2(10.0, -38.0), seed, 8, 1.0)
	if layer == Kit.LIGHT and t < start + move.active:
		vfx.body_flash(canvas, f, actor, Color(Kit.GOLD_HOT, 0.5))
