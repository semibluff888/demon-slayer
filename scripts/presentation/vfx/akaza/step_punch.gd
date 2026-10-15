extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 踏进冲拳 (6C): the step plants with a puff of dust, and the straight punch
## shoots a needle of light out well past his fist (the blow arrives before he
## does), with three rings of air opening along it like a cone and a swirl
## round the fist.

## How far the needle's head leads the front of the hit box (local units).
const LEAD := 40.0

## The drawn fist (6C borrows the air_type frames, roster-v1 art).
func fist(_move: Resource) -> Vector2:
	return Vector2(43.0, -46.0)

## The needle at move time `t`: {"from", "head", "alpha"} in fighter-local units.
func shape(f: RefCounted, t: float) -> Dictionary:
	var move: Resource = f.move
	var box: Rect2 = move.box
	var since := t - float(move.startup)
	var y := box.get_center().y
	var out := 1.0 - pow(1.0 - clampf((since + 1.0) / 2.0, 0.0, 1.0), 2.0)
	var head := Vector2(lerpf(fist(move).x, box.end.x + LEAD, out), y)
	var erosion := clampf((since - move.active + 1.0) / 6.0, 0.0, 1.0)
	var from := Vector2(box.position.x + 6.0, y).lerp(head, erosion)
	return {"from": from, "head": head, "alpha": 1.0 - smoothstep(0.7, 1.0, erosion)}

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 233 + f.slot * 7919 + tick * 11
	if tick == move.startup - 8 and f.grounded:
		vfx.dust_burst(vfx.world(f, Vector2(14.0, 0.0)), 4, Vector2(-0.4, 0.0), seed, 0.9)
	if tick == move.startup:
		var at: Vector2 = vfx.world(f, fist(move))
		vfx.spark_burst(at, 12, Vector2(float(f.facing), 0.0), 100.0, 240.0, seed + 1)
		vfx.flake_burst(at, 3, 50.0, seed + 2, awake, 8.0)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 0.9, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var since := t - float(move.startup)
	if since < -1.0 or since > move.active + 8.0:
		return
	var needle := shape(f, t)
	var alpha: float = needle.alpha
	vfx.needle(canvas, layer, needle.from, needle.head, 5.0, alpha, awake)
	var at := fist(move)
	for n in range(3):
		var k := clampf((since + 1.0 - n * 0.7) / 5.0, 0.0, 1.0)
		if k <= 0.0:
			continue
		var x: float = lerpf(at.x, needle.head.x, (n + 1) / 4.0)
		vfx.ring(canvas, layer, Vector2(x + 6.0 * k, at.y), Vector2(lerpf(3.0, 6.0, k), lerpf(8.0, 16.0, k) + 3.0 * n), 0.0, alpha * (1.0 - 0.5 * k), 2.0, awake)
	vfx.vortex(canvas, layer, at, 9.0, since * 0.9, alpha * (1.0 - clampf(since / 8.0, 0.0, 1.0)), awake)
