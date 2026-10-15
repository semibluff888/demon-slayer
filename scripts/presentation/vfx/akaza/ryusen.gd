extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·脚式 流闪群光 (6B): the first kick bursts a shock off his foot with a
## short arc of air; the second sends a long needle of light streaking along the
## kick and well past it, a big rising crescent and a puff of dust at his feet.

const LEAD := 40.0

## The two kicks, fitted to the borrowed body_stand_heavy frames (roster-v1 art):
## a high front kick, then a bigger rising one.
func first(_move: Resource) -> Paths.Sweep:
	return Paths.Sweep.new(Vector2(-4.0, -10.0), Vector2(20.0, -74.0), Vector2(42.0, -58.0), 11.0)

func second(_move: Resource) -> Paths.Arc:
	var path := Paths.Arc.new(Vector2(14.0, -38.0), 0.95, -1.35, 38.0, 50.0, 16.0)
	path.profile = "crescent"
	return path

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 239 + f.slot * 7919 + tick * 17
	var cuts := starts(move)
	if tick == int(cuts[0]):
		var foot: Vector2 = vfx.world(f, target_local(f, Vector2(48.0, -56.0), 60.0))
		vfx.bursts.append({"kind": "shock", "at": foot, "age": 0.0, "life": 0.18, "size": 14.0, "facing": float(f.facing), "seed": seed, "awake": awake})
		vfx.spark_burst(foot, 8, Vector2(float(f.facing), -0.3), 70.0, 180.0, seed + 1)
	if cuts.size() > 1 and tick == int(cuts[1]):
		vfx.flake_burst(vfx.world(f, Vector2(48.0, -56.0)), 6, 70.0, seed + 2, awake, 20.0)
		if f.grounded:
			vfx.dust_burst(vfx.world(f, Vector2(10.0, 0.0)), 4, Vector2(0.6, 0.0) * float(f.facing), seed + 4, 1.1)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 0.95 if last else 0.7, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var cuts := starts(move)
	var a := t - float(cuts[0])
	vfx.crescent(canvas, layer, first(move), clampf((a + 1.0) / 2.0, 0.0, 1.0), clampf((a - 1.5) / 5.0, 0.0, 1.25), 0.9, awake)
	if cuts.size() < 2:
		return
	var b := t - float(cuts[1])
	if b < -1.0:
		return
	var box: Rect2 = move.box
	var out := 1.0 - pow(1.0 - clampf((b + 1.0) / 2.0, 0.0, 1.0), 2.0)
	var head := Vector2(lerpf(42.0, box.end.x + LEAD, out), -50.0)
	var erosion := clampf((b - 3.0) / 7.0, 0.0, 1.0)
	vfx.needle(canvas, layer, Vector2(-6.0, -46.0).lerp(head, erosion), head, 6.0, 1.0 - smoothstep(0.7, 1.0, erosion), awake)
	vfx.crescent(canvas, layer, second(move), clampf((b + 1.0) / 3.0, 0.0, 1.0), clampf((b - 2.0) / 7.0, 0.0, 1.25), 1.0, awake, 26)

