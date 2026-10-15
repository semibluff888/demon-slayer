extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·乱式 (214B/D): after the red start-up and its ink, a storm of blows:
## every other tick a spiky shock pops at a seeded point in front of him with a
## flick of white air, dark smoke rolls along the floor and black rock flies;
## each hit segment bursts bigger at the front of the barrage, and the last one
## lands as a large shock with a dome of air.

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 223 + f.slot * 7919 + tick * 41
	emit_activation(f, tick)
	if tick < move.startup or tick >= move.startup + move.active:
		return
	var box: Rect2 = move.box
	if (tick - move.startup) % 2 == 0:
		# A blow landing on the target (or in the front half of the barrage on a whiff).
		var fallback := Vector2(lerpf(box.position.x + box.size.x * 0.45, box.end.x - 4.0, vfx.rand(seed, 1)), box.get_center().y)
		var local := target_local(f, fallback, box.end.x) + Vector2((vfx.rand(seed, 2) - 0.5) * 22.0, (vfx.rand(seed, 7) - 0.5) * 30.0)
		var at: Vector2 = vfx.world(f, local)
		vfx.bursts.append({"kind": "shock", "at": at, "age": 0.0, "life": 0.12, "size": lerpf(9.0, 14.0, vfx.rand(seed, 3)), "facing": float(f.facing),
			"seed": seed, "awake": awake})
		vfx.bursts.append({"kind": "flick", "technique": self, "at": at, "age": 0.0, "life": 0.14, "size": lerpf(10.0, 16.0, vfx.rand(seed, 4)),
			"angle": lerpf(-1.2, 1.2, vfx.rand(seed, 5)), "facing": float(f.facing), "seed": seed + 1, "awake": awake})
		vfx.spark_burst(at, 4, Vector2(float(f.facing), -0.2), 60.0, 160.0, seed + 2)
	if (tick - move.startup) % 3 == 0 and f.grounded:
		vfx.dust_burst(vfx.world(f, Vector2(lerpf(-6.0, 24.0, vfx.rand(seed, 6)), 0.0)), 2, Vector2(0.5, 0.0), seed + 3, 1.1)
	if (tick - move.startup) % 4 == 1:
		vfx.debris_burst(vfx.world(f, Vector2(box.end.x * 0.6, -8.0)), 2, Vector2(0.4, 0.0) * float(f.facing), seed + 4)
	if tick in Array(move.hit_frames):
		var front: Vector2 = vfx.world(f, target_local(f, Vector2(box.end.x - 20.0, box.get_center().y), box.end.x))
		vfx.bursts.append({"kind": "shock", "at": front, "age": 0.0, "life": 0.15, "size": 18.0, "facing": float(f.facing), "seed": seed + 5, "awake": awake})

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.3 if last else 0.6, awakened, last)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var t := clock(f)
	var red := activation_strength(t)
	if red > 0.0:
		vfx.activation(canvas, layer, f, actor, red, f.attack_instance * 13)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	if burst.kind != "flick":
		return
	# A short white arc of displaced air beside a blow.
	var path := Paths.Arc.new(Vector2.ZERO, float(burst.angle) - 0.9, float(burst.angle) + 0.9, float(burst.size), float(burst.size) * 1.25, 4.0)
	path.profile = "crescent"
	vfx.crescent(canvas, layer, path, clampf(k * 3.0, 0.0, 1.0), clampf((k - 0.3) / 0.7, 0.0, 1.25), 0.9, bool(burst.awake), 12)
