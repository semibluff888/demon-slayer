extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 终式·青银乱残光 (MAX): through the super freeze the compass is cast under his
## feet, first in red, then in silver-blue, with shafts of light rising from
## its rim, flakes floating up and his body lit silver. Each of the six blows
## leaves two crossing needles of silver-blue afterglow over the target with a
## shock where they meet (the middle blows small, the last one large with a
## ring of rays); the compass fades a second after the move ends.

const RADIUS := 64.0
## Frames the compass takes to fade after the last blow, and the seconds it
## keeps fading should the move end first (interrupted, or landing).
const FADE := 30.0
const LINGER := 0.4
## Where the blows land on a whiff, fighter-local (otherwise on the target).
const STRIKE := Vector2(46.0, -46.0)

## Compasses whose move ended, still fading: {"at", "born", "spin", "awake"}.
var _fading: Array[Dictionary] = []
var _live: Dictionary = {}
## World points where each blow landed, by slot: {"instance", "points": {index: Vector2}}.
var _strikes: Dictionary = {}

## The compass holds through the blows, then fades over the recovery.
func compass_alpha(move: Resource, t: float) -> float:
	return 1.0 - smoothstep(float(move.startup + move.active), float(move.startup + move.active) + FADE, t)

func charge(f: RefCounted) -> float:
	return clampf(charge_age(f) / float(f.move.freeze_frames + f.move.startup), 0.0, 1.0)

## Compass colour through the charge: red while it is cast, then silver-blue.
func compass_color(age: float, awake: bool) -> Color:
	return Kit.RED.lerp(Kit.SILVER.lerp(Kit.tone(awake), 0.35), smoothstep(9.0, 16.0, age))

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 263 + f.slot * 7919 + tick * 31
	emit_activation(f, tick)
	# Where the compass lies, should the move end and leave it fading.
	var age := float(move.freeze_frames + tick)
	_live[f.slot] = {"instance": f.attack_instance, "at": Vector2(f.x, Arena.FLOOR_Y), "spin": age * 0.02, "color": compass_color(age, awake),
		"alpha": compass_alpha(move, float(tick))}
	if tick < move.startup:
		vfx.flake_burst(vfx.world(f, Vector2(lerpf(-RADIUS, RADIUS, vfx.rand(seed, 1)) * 0.8, -4.0)), 2, 20.0, seed + 1, awake, 60.0)
		return
	var cuts := starts(move)
	var index := cuts.find(tick)
	if index < 0:
		return
	var last := index == cuts.size() - 1
	var at: Vector2 = vfx.world(f, target_local(f, STRIKE, move.box.end.x) + Vector2(0.0, (vfx.rand(seed, 2) - 0.5) * 16.0))
	var held: Dictionary = _strikes.get(f.slot, {})
	if int(held.get("instance", -1)) != f.attack_instance:
		held = {"instance": f.attack_instance, "points": {}}
		_strikes[f.slot] = held
	held.points[index] = at
	vfx.bursts.append({"kind": "shock", "at": at, "age": 0.0, "life": 0.22 if last else 0.16, "size": 26.0 if last else 13.0, "facing": float(f.facing),
		"seed": seed + 3, "awake": awake})
	vfx.spark_burst(at, 14 if last else 6, Vector2(float(f.facing), -0.2), 90.0, 240.0, seed + 4, Kit.SILVER)
	if last:
		vfx.bursts.append({"kind": "rays", "at": at, "age": 0.0, "life": 0.3, "size": 120.0, "facing": float(f.facing), "seed": seed + 5, "awake": awake})
		vfx.flake_burst(at, 12, 110.0, seed + 6, awake)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.7 if last else 0.55, awakened, last)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var age := charge_age(f)
	var red := activation_strength(age)
	if red > 0.0:
		vfx.activation(canvas, layer, f, actor, red, f.attack_instance * 23)
	var k := charge(f)
	var spin := age * 0.02
	var color := compass_color(age, awake)
	var lift: float = Arena.FLOOR_Y - f.y
	vfx.compass_shape(canvas, layer, Vector2(0.0, lift), RADIUS, clampf(age / 14.0, 0.0, 1.0), spin, color, compass_alpha(move, t))
	if t < start + 1.0:
		# Shafts of light rising from the rim while the compass is cast.
		if layer == Kit.LIGHT and k > 0.3:
			for n in range(6):
				var a := TAU * n / 6.0 + spin
				var foot := Vector2(cos(a) * RADIUS * 0.9, lift + sin(a) * RADIUS * 0.9 * Kit.FLOOR_SQUASH)
				var height := lerpf(20.0, 90.0, (k - 0.3) / 0.7) * lerpf(0.7, 1.0, vfx.rand(f.attack_instance, n))
				Ribbon.draw(canvas, PackedVector2Array([foot, foot + Vector2(0.0, -height)]), PackedFloat32Array([4.0, 0.0]),
					PackedColorArray([Color(color, 0.7 * k), Color(color, 0.0)]), vfx.band)
			vfx.body_flash(canvas, f, actor, Color(Kit.SILVER, 0.35 * k))
		if t < start:
			return
	# Two crossing needles of afterglow over each blow, where it landed.
	var cuts := starts(move)
	var held: Dictionary = _strikes.get(f.slot, {})
	var points: Dictionary = held.get("points", {}) if int(held.get("instance", -1)) == f.attack_instance else {}
	for index in range(cuts.size()):
		var since := t - float(cuts[index])
		if since < 0.0 or since > 7.0 or not points.has(index):
			continue
		var at: Vector2 = local_of(f, points[index])
		var fade := 1.0 - clampf(since / 7.0, 0.0, 1.0)
		var reach := clampf((since + 1.0) / 1.5, 0.0, 1.0)
		var tilt := 0.5 if index % 2 == 0 else -0.5
		for s: float in [-1.0, 1.0]:
			var axis := Vector2.from_angle(tilt * s)
			var from: Vector2 = at - axis * 46.0 * s
			vfx.needle(canvas, layer, from, from.lerp(at + axis * 46.0 * s, reach), 4.0, fade, awake)

func linger(fighters: Array, _actors: Array) -> void:
	for f in fighters:
		var held: Dictionary = _live.get(f.slot, {})
		if held.is_empty():
			continue
		if f.move != null and f.move.id == "akaza_max" and f.attack_instance == int(held.instance):
			continue
		if float(held.alpha) > 0.01:
			_fading.append({"at": held.at, "born": vfx.time, "spin": held.spin, "color": held.color, "alpha": held.alpha})
		_live.erase(f.slot)
	_fading = _fading.filter(func(c: Dictionary) -> bool: return vfx.time - float(c.born) < LINGER)

func draw_lingering(canvas: Node2D, layer: int) -> void:
	for held: Dictionary in _fading:
		var k := clampf((vfx.time - float(held.born)) / LINGER, 0.0, 1.0)
		vfx.set_base(canvas, vfx.world_transform(held.at))
		vfx.compass_shape(canvas, layer, Vector2.ZERO, RADIUS, 1.0, float(held.spin), held.color, float(held.alpha) * (1.0 - k))

func reset() -> void:
	super()
	_fading.clear()
	_live.clear()
	_strikes.clear()
