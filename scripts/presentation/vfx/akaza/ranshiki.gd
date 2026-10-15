extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·乱式 (214B/D): after the red start-up and its ink, a storm of blows:
## every other tick a shock pops at a seeded point in front of him with a
## flick of white air and dark smoke rolls along the floor;
## each hit segment bursts bigger at the front of the barrage (the contact burst
## when it lands, a burst of its own on a whiff), and the last one lands as a
## large shock with a dome of air. Every burst sits at the height of his fists
## (upper body), not the middle of the hit box.

## Fist height of the barrage, fighter-local (stand_light / stand_heavy fists).
const FIST_Y := -54.0

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
		var fallback := Vector2(lerpf(box.position.x + box.size.x * 0.45, box.end.x - 4.0, vfx.rand(seed, 1)), FIST_Y)
		var local := Vector2(target_local(f, fallback, box.end.x).x, FIST_Y) + Vector2((vfx.rand(seed, 2) - 0.5) * 22.0, (vfx.rand(seed, 7) - 0.5) * 18.0)
		var at: Vector2 = vfx.world(f, local)
		vfx.bursts.append({"kind": "shock", "at": at, "age": 0.0, "life": 0.16, "size": lerpf(9.0, 14.0, vfx.rand(seed, 3)), "facing": float(f.facing),
			"seed": seed, "awake": awake})
		vfx.bursts.append({"kind": "flick", "technique": self, "at": at, "age": 0.0, "life": 0.14, "size": lerpf(10.0, 16.0, vfx.rand(seed, 4)),
			"angle": lerpf(-1.2, 1.2, vfx.rand(seed, 5)), "facing": float(f.facing), "seed": seed + 1, "awake": awake})
		vfx.spark_burst(at, 4, Vector2(float(f.facing), -0.2), 60.0, 160.0, seed + 2)
	if (tick - move.startup) % 3 == 0 and f.grounded:
		vfx.dust_burst(vfx.world(f, Vector2(lerpf(-6.0, 24.0, vfx.rand(seed, 6)), 0.0)), 2, Vector2(0.5, 0.0), seed + 3, 1.1)
	if tick in Array(move.hit_frames) and not f.connected:
		var front: Vector2 = vfx.world(f, Vector2(target_local(f, Vector2(box.end.x - 20.0, FIST_Y), box.end.x).x, FIST_Y))
		vfx.bursts.append({"kind": "shock", "at": front, "age": 0.0, "life": 0.2, "size": 18.0, "facing": float(f.facing), "seed": seed + 5, "awake": awake})

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	# Lift the contact burst from the middle of the hit box to fist height.
	var raised := event.duplicate()
	raised.position = Vector2(event.position.x, minf(event.position.y, attacker.y + FIST_Y))
	vfx.strike(raised, attacker, 1.3 if last else 0.6, awakened, last)

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
