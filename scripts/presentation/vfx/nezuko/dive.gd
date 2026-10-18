extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 爆血飞踢·落 (j.236A/C), after 爆血突 (air): blood gathers in the air, then she
## dives feet first in a comet of pink fire slanting down, its head running ahead
## of her foot; where she lands the floor breaks: a blood-flame burst, slabs of
## stone tipping up lit pink from below, rock and dust flying, a crater still
## glowing pink inside. Only a real landing breaks the floor, once per dive.

## The diving foot (v3 air_dive frames; DEMON_FOOT on the kept demon-form drawing,
## body_air_heavy) and how far ahead of it, along the dive, the fire's head runs
## (fighter-local).
const FOOT := Vector2(20, -17)
const DEMON_FOOT := Vector2(32, -16)
const LEAD := 18.0
const ERUPTION := 0.55
const CRATER := 1.5

var _landed: Dictionary = {}

func reset() -> void:
	super()
	_landed.clear()

## Unit direction of the dive in fighter-local units (forward, down).
func heading(move: Resource) -> Vector2:
	var index: int = move.air_velocities.size() - 1
	return move.air_velocities[index].normalized() if index >= 0 else Vector2(0.6, 0.8)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 239 + f.slot * 7919 + tick * 61
	emit_activation(f, tick, awake, Vector2(0.0, -34.0))
	mark_origin(f, tick, move.startup)
	if tick >= move.startup:
		var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
		vfx.ember_burst(vfx.world(f, foot), 3, Vector2(-heading(move).x, -heading(move).y), 40.0, 140.0, seed, awake)
		if tick % 2 == 0:
			vfx.flake_burst(vfx.world(f, foot - heading(move) * 14.0), 1, 30.0, seed + 1, awake, 10.0)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.1 if heavy(move) else 1.0, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var gather := activation_strength(t)
	if gather > 0.0:
		vfx.activation(canvas, layer, f, actor, gather * 0.8, f.attack_instance * 19, awake, Vector2(0.0, -34.0))
	var since := t - float(move.startup)
	if since < -1.0:
		return
	var out := clampf((since + 1.0) / 2.0, 0.0, 1.0)
	var aim := heading(move)
	var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
	var head: Vector2 = foot + aim * LEAD * vfx.drawn(f) * out
	var from: Vector2 = origin_local(f, foot.y)
	from.x += foot.x
	if from.distance_to(head) < 24.0:
		from = head - aim * 24.0
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	var thick := 20.0 if heavy(move) else 16.0
	for n in range(14):
		var u := n / 13.0
		points.append(from.lerp(head, u))
		widths.append(thick * lerpf(0.25, 1.0, pow(u, 0.6)) * (1.0 - 0.7 * smoothstep(0.9, 1.0, u)))
		alphas.append(out * smoothstep(0.0, 0.3, u))
	vfx.flame(canvas, layer, points, widths, alphas, awake, f.attack_instance)
	vfx.needle(canvas, layer, foot - aim * 30.0 + aim.orthogonal() * 8.0, head + aim * 6.0, 3.0, out * 0.7, awake)

## The landing: once per dive, when she lands out of it.
func linger(fighters: Array, actors: Array) -> void:
	for f in fighters:
		if f.move != null or not f.grounded or not str(f.landing_move) in ["nezuko_j236A", "nezuko_j236C"]:
			continue
		if int(_landed.get(f.slot, -1)) == f.attack_instance:
			continue
		_landed[f.slot] = f.attack_instance
		var awake: bool = f.slot < actors.size() and actors[f.slot] != null and actors[f.slot].form_active()
		var seed: int = f.attack_instance * 251 + 7
		vfx.focus = f.slot
		var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
		var at: Vector2 = vfx.world(f, Vector2(foot.x * 0.6, 0.0))
		vfx.focus = -1
		var facing := float(f.facing)
		vfx.bursts.append({"kind": "eruption", "technique": self, "at": at, "age": 0.0, "life": ERUPTION, "size": 24.0, "facing": facing, "seed": seed, "awake": awake})
		vfx.bursts.append({"kind": "crater", "technique": self, "at": at, "age": 0.0, "life": CRATER, "size": 20.0, "facing": 1.0, "seed": seed + 1, "awake": awake})
		vfx.bursts.append({"kind": "blaze", "at": at + Vector2(0.0, -10.0), "age": 0.0, "life": 0.24, "size": 20.0, "facing": facing, "seed": seed + 2, "awake": awake})
		vfx.debris_burst(at, 7, Vector2(0.0, -0.3), seed + 3, true, 1.2)
		vfx.flake_burst(at + Vector2(0.0, -10.0), 6, 90.0, seed + 4, awake, 50.0)
		vfx.dust_burst(at, 6, Vector2.ZERO, seed + 5, 1.1)
		vfx.ember_burst(at + Vector2(0.0, -6.0), 14, Vector2(0.0, -1.0), 100.0, 250.0, seed + 6, awake)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	var awake: bool = burst.get("awake", false)
	match burst.kind:
		"eruption":
			var rise := 1.0 - pow(1.0 - clampf(k / 0.14, 0.0, 1.0), 3.0)
			var sink := 1.0 - smoothstep(0.55, 1.0, k)
			vfx.rubble(canvas, layer, Vector2.ZERO, float(burst.size), rise * sink, int(burst.seed), awake, 7)
		"crater":
			vfx.crater(canvas, layer, Vector2.ZERO, float(burst.size), 1.0 - smoothstep(0.65, 1.0, k), int(burst.seed), 1.0 - smoothstep(0.0, 0.6, k), awake)
