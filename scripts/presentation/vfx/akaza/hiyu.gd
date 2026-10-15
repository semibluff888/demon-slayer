extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·脚式 飞游星千轮 (j.214B/D): after a short red start-up in the air, the
## flip kick spins three thin white rings of air round his body (the "thousand
## rings"), shedding sparks along them; each kick lands with a big heel arc,
## and the landing throws up a ring of dust and a small burst.

## Ring radii round the body centre and its height above the feet.
const RADII := [30.0, 38.0, 46.0]
const CENTRE := Vector2(2.0, -34.0)

var _landed: Dictionary = {}

func spin(t: float, move: Resource) -> float:
	return (t - move.startup) * 0.55

func heel(_move: Resource) -> Paths.Arc:
	var path := Paths.Arc.new(Vector2(10.0, -30.0), -1.6, 0.9, 44.0, 52.0, 16.0)
	path.profile = "crescent"
	return path

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 241 + f.slot * 7919 + tick * 23
	emit_activation(f, tick, Vector2(0.0, -34.0))
	if tick < move.startup or tick >= move.startup + move.active:
		return
	var a: float = spin(float(tick), move) + vfx.rand(seed, 1) * TAU
	var r: float = RADII[tick % 3]
	var on := CENTRE + Vector2(cos(a) * r, sin(a) * r)
	var along := Vector2(-sin(a), cos(a))
	vfx.sparks.spawn(vfx.world(f, on), vfx.world_dir(f, along * lerpf(80.0, 160.0, vfx.rand(seed, 2))), lerpf(0.14, 0.26, vfx.rand(seed, 3)),
		lerpf(1.4, 2.4, vfx.rand(seed, 4)), 0, Kit.tone(awake).lerp(Kit.WHITE, 0.4), 120.0, 1.6, 0.0, 0.0, 0.6, 2.0)
	if tick in starts(move):
		vfx.flake_burst(vfx.world(f, heel(move).point(1.0, 0.0)), 4, 50.0, seed + 5, awake, 10.0)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.1 if last else 0.7, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var red := activation_strength(t)
	if red > 0.0:
		vfx.activation(canvas, layer, f, actor, red * 0.8, f.attack_instance * 17, Vector2(0.0, -34.0))
	var since := t - float(move.startup)
	if since < -1.0:
		return
	var fade := 1.0 - clampf((since - move.active) / 5.0, 0.0, 1.0)
	if fade <= 0.0:
		return
	var grow := clampf((since + 1.0) / 3.0, 0.0, 1.0)
	for n in range(3):
		var a0 := spin(t, move) * (1.0 + 0.2 * n) + n * 2.1
		var path := Paths.Arc.new(CENTRE, a0, a0 + 2.2, RADII[n] * lerpf(0.6, 1.0, grow), RADII[n] * lerpf(0.6, 1.0, grow), 5.0 - n)
		path.profile = "crescent"
		vfx.crescent(canvas, layer, path, 1.0, 0.0, fade * (0.9 - 0.15 * n), awake, 16)
	for index in range(starts(move).size()):
		var hit := float(starts(move)[index])
		var b := t - hit
		vfx.crescent(canvas, layer, heel(move), clampf((b + 1.0) / 2.0, 0.0, 1.0), clampf((b - 1.0) / 5.0, 0.0, 1.25), 1.0, awake)

func linger(fighters: Array, actors: Array) -> void:
	for f in fighters:
		if f.move != null or not f.grounded or not str(f.landing_move) in ["akaza_j214B", "akaza_j214D"]:
			continue
		if int(_landed.get(f.slot, -1)) == f.attack_instance:
			continue
		_landed[f.slot] = f.attack_instance
		var awake: bool = f.slot < actors.size() and actors[f.slot] != null and actors[f.slot].form_active()
		var seed: int = f.attack_instance * 251 + 7
		var feet: Vector2 = vfx.world(f, Vector2(0.0, 0.0))
		vfx.dust_burst(feet, 6, Vector2.ZERO, seed, 1.0)
		vfx.bursts.append({"kind": "ring", "at": feet + Vector2(0.0, -2.0), "age": 0.0, "life": 0.24, "size": 26.0, "squash": 0.45, "facing": float(f.facing),
			"seed": seed + 1, "awake": awake})
		vfx.spark_burst(feet, 8, Vector2(0.0, -0.6), 60.0, 150.0, seed + 2)

func reset() -> void:
	super()
	_landed.clear()
