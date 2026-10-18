extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 连续踢 (5B > B > D), after 连续踢: the second kick snaps a white crescent and
## yellow sparks; the two-kick finisher drags pink fire along both kicks, and its
## last kick bursts in a great spray of burning blood across the target.

## Foot paths (start, control, end), fighter-local: the second kick (renzoku_2, the
## near leg snapped to the chest) and the finisher's high roundhouse then spinning back
## kick (renzoku_3), fitted to the v3 drawing; the DEMON_ ones fit the kept demon-form
## drawing, which plays body_stand_light / body_stand_heavy for these moves.
const SECOND := [Vector2(-7, -12), Vector2(9, -53), Vector2(28, -48)]
const FINISH := [[Vector2(-10, -14), Vector2(4, -72), Vector2(32, -60)], [Vector2(-12, -18), Vector2(9, -56), Vector2(30, -50)]]
const DEMON_SECOND := [Vector2(-2, -8), Vector2(16, -54), Vector2(38, -50)]
const DEMON_FINISH := [[Vector2(-8, -10), Vector2(10, -72), Vector2(42, -56)], [Vector2(-6, -8), Vector2(20, -50), Vector2(44, -40)]]

func finisher(move: Resource) -> bool:
	return move.id.ends_with("D")

func kick_path(f: RefCounted, move: Resource, index: int) -> Paths.Sweep:
	var finish: Array = fit(f, FINISH, DEMON_FINISH)
	var keys: Array = reaching(move, finish[mini(index, 1)] if finisher(move) else fit(f, SECOND, DEMON_SECOND))
	return Paths.Sweep.new(keys[0], keys[1], keys[2], 14.0 if finisher(move) else 9.0)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 191 + f.slot * 7919 + tick * 41
	var list := starts(move)
	if not tick in list:
		return
	var index := list.find(tick)
	var tip: Vector2 = vfx.world(f, kick_path(f, move, index).point(1.0, 0.0))
	vfx.ember_burst(tip, 12 if finisher(move) else 6, Vector2(float(f.facing), -0.2), 70.0, 200.0, seed, awake)
	if finisher(move):
		vfx.flake_burst(tip, 4, 50.0, seed + 1, awake, 10.0)
		vfx.dust_burst(vfx.world(f, Vector2(-8.0, 0.0)), 3, Vector2(-0.3, 0.0), seed + 2, 0.9)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	if not finisher(move):
		vfx.strike(event, attacker, 0.55, awakened)
		return
	vfx.strike(event, attacker, 1.0 if last else 0.65, awakened)
	if last and event.type == "hit":
		# The spray of burning blood the reference's last kick throws.
		var at: Vector2 = event.position
		var seed: int = attacker.attack_instance * 37 + 5
		var push := Vector2(float(attacker.facing), -0.15)
		vfx.flake_burst(at, 14, 150.0, seed, awakened, 10.0)
		vfx.ember_burst(at, 22, push, 140.0, 320.0, seed + 1, awakened)
		vfx.bursts.append({"kind": "blaze", "at": at + push * 14.0, "age": 0.0, "life": 0.22, "size": 18.0, "facing": float(attacker.facing), "seed": seed + 2,
			"awake": awakened})

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var list := starts(move)
	for index in range(list.size()):
		var since := t - float(list[index])
		var head := clampf((since + 1.0) / 2.0, 0.0, 1.0)
		var tail := clampf((since - 1.5) / 6.0, 0.0, 1.25)
		if head <= 0.0 or tail >= 1.0:
			continue
		var curve := kick_path(f, move, index)
		vfx.crescent(canvas, layer, curve, head, tail, 1.0, awake)
		if finisher(move):
			vfx.flame_along(canvas, layer, curve, head, clampf(tail + 0.1, 0.0, 1.0), 1.0, awake, 1.1, f.attack_instance + index)
