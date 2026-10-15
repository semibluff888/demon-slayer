extends "res://scripts/presentation/vfx/zenitsu/technique.gd"
## 霹雳一闪 (236A/C), 低身斩 (3C) and 霹雳一闪·空 (j.236A/C): lightning crackles
## at his feet through the startup (a blue pillar while he hangs in the air),
## then the dash leaves a thick yellow-white beam from where it began to well
## past Zenitsu's body: its spiked head and a pointed lance of light lead him,
## so the flash lands before he does. His body is lit gold, dark speed lines
## trail behind and a scorch marks the floor; the beam erodes from the tail while
## its head drifts on. An air dash ends on touchdown, so its beam is handed to
## `draw_lingering` and finishes eroding there.

## Beam height above the feet (local units); the air dash poses dive with the
## body higher above the feet.
const CHEST := -34.0
const LOW := -12.0
const AIR := -42.0
## Seconds a beam keeps eroding once its move has ended.
const LINGER := 0.22
## How far the head drifts on while the tail erodes (local units).
const DRIFT := 16.0
## Spearhead length, in beam thicknesses.
const LANCE := 1.9

## Beams whose move ended before they finished: {tail, head, born, awake, seed}.
var _beams: Array[Dictionary] = []
## Last drawn beam per slot while its move is running, in world units.
var _live: Dictionary = {}
var _landed: Dictionary = {}

func height(move: Resource) -> float:
	if move.id.ends_with("3C"):
		return LOW
	return AIR if move.stance == "air" else CHEST

func thickness(move: Resource) -> float:
	return 15.0 if heavy(move) else (10.0 if move.id.ends_with("3C") else 12.0)

## How far along the dash the beam's head leads his feet. The front of his body
## is about 24 units ahead in the dash poses, so the head star clears it.
func reach(move: Resource) -> float:
	if move.id.ends_with("3C"):
		return 48.0
	return 52.0 if heavy(move) else 44.0

## Shortest beam: 低身斩 barely travels, so its streak starts behind him.
func span(move: Resource) -> float:
	return 84.0 if move.id.ends_with("3C") else 0.0

## Unit direction of the dash in local units: along the floor, or the air
## dash's velocity once it launches.
func direction(move: Resource) -> Vector2:
	if move.stance != "air":
		return Vector2.RIGHT
	var heading := Vector2.RIGHT
	for n in range(mini(move.air_velocity_frames.size(), move.air_velocities.size())):
		if move.air_velocity_frames[n] <= move.startup:
			heading = move.air_velocities[n]
	return heading.normalized() if heading.length() > 0.1 else Vector2.RIGHT

## Tail erosion 0..1 once the active frames are over.
func erosion(t: float, move: Resource) -> float:
	return clampf((t - move.startup - move.active + 2.0) / 12.0, 0.0, 1.0)

## The beam at move time `t` (from the startup on), fighter-local:
## {"from", "head", "tip", "dir", "width", "alpha", "point"}. The head shoots out
## ahead of him over the first two frames of the dash and drifts on while the
## tail erodes and the beam thins; `point` fades the head star and shock lines
## once the dash is over, and the lance shrinks to the pointed end of the beam.
func shape(f: RefCounted, t: float) -> Dictionary:
	var move: Resource = f.move
	var h := height(move)
	var dir := direction(move)
	var start := float(move.startup)
	var e := erosion(t, move)
	var lunge := 1.0 - clampf((t - start + 1.0) / 2.0, 0.0, 1.0)
	var lead := lerpf(10.0, reach(move), 1.0 - lunge * lunge) + DRIFT * (1.0 - (1.0 - e) * (1.0 - e))
	var head := Vector2(0.0, h) + dir * lead
	var tail := origin_local(f, h)
	if tail.distance_to(head) < span(move):
		tail = head - dir * span(move)
	var point := 1.0 - clampf((t - start - move.active) / 4.0, 0.0, 1.0)
	var width := thickness(move) * lerpf(1.0, 0.55, e)
	return {"from": tail.lerp(head, e), "head": head, "tip": head + dir * width * lerpf(0.8, LANCE, point), "dir": dir, "width": width,
		"alpha": 1.0 - smoothstep(0.8, 1.0, e), "point": point}

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 149 + f.slot * 7919 + tick * 23
	mark_origin(f, tick, move.startup - 1)
	var feet: Vector2 = vfx.world(f, Vector2(4.0, -2.0))
	if tick < move.startup and tick % 2 == 0:
		vfx.mote_burst(vfx.world(f, Vector2(0.0, -30.0 if move.stance == "air" else -6.0)), 2, 30.0, seed, awake)
	if tick == move.startup:
		vfx.spark_burst(feet, 14, Vector2(-1.0, -0.4) * float(f.facing), 80.0, 200.0, seed + 1)
		if move.stance != "air":
			vfx.debris_burst(feet, 4, Vector2(-float(f.facing) * 0.5, 0.0), seed + 2)
	if tick < move.startup:
		return
	var beam := shape(f, float(tick))
	if move.stance == "air":
		# Where the beam is now, in case the dash ends on touchdown mid-erosion.
		_live[f.slot] = {"instance": f.attack_instance, "tail": vfx.world(f, beam.from), "head": vfx.world(f, beam.head), "awake": awake,
			"seed": f.attack_instance * 53 + tick, "thickness": thickness(move), "alpha": beam.alpha}
	if tick < move.startup + move.active:
		# Sparks streaming back off the head of the beam.
		var at: Vector2 = vfx.world(f, beam.head)
		for n in range(2):
			vfx.sparks.spawn(at, vfx.world_dir(f, Vector2(-lerpf(60.0, 160.0, vfx.rand(seed, n)), lerpf(-50.0, 30.0, vfx.rand(seed, n + 5)))),
				lerpf(0.15, 0.3, vfx.rand(seed, n + 10)), lerpf(1.4, 2.4, vfx.rand(seed, n + 15)), 0, Kit.GOLD_HOT, 180.0, 1.5, 0.0, 0.0, 0.6, 2.5)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.15 if heavy(move) else 1.0, awakened, true)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var seed: int = f.attack_instance * 53 + f.move_frame
	var air: bool = move.stance == "air"
	if t < start + 1.0:
		var k := clampf(t / maxf(start, 1.0), 0.0, 1.0)
		if air:
			vfx.pillar(canvas, layer, Vector2(0.0, -36.0), 130.0, 50.0, k, awake, seed)
		else:
			# Lightning crackling round his feet as he crouches into the draw.
			for n in range(2):
				var x := lerpf(-14.0, 22.0, vfx.rand(seed, n))
				vfx.bolt(canvas, layer, Bolt.path(Vector2(x, -1.0), Vector2(x + lerpf(-8.0, 8.0, vfx.rand(seed, n + 3)), -lerpf(14.0, 30.0, vfx.rand(seed, n + 6))),
					seed + n * 11, 0.35, 3), 1.4, awake, k)
		if layer == Kit.LIGHT:
			vfx.body_flash(canvas, f, actor, Color(Kit.GOLD, 0.35 * k))
	if t < start:
		return
	var beam := shape(f, t)
	var from: Vector2 = beam.from
	var head: Vector2 = beam.head
	var alpha: float = beam.alpha
	var dashing: bool = t < start + move.active
	draw_beam(canvas, layer, beam, awake, seed)
	if dashing:
		if layer == Kit.FRONT:
			vfx.speed_lines(canvas, from, head, seed, 7, 1.0)
		if layer == Kit.LIGHT:
			vfx.body_flash(canvas, f, actor, Color(Kit.GOLD_HOT, 0.55))
	# Two bolts racing along the beam and out along the lance.
	for n in range(2):
		var offset := Vector2(0.0, (n - 0.5) * thickness(move) * 0.9)
		vfx.bolt(canvas, layer, Bolt.path(from + offset, beam.tip + offset * 0.3, seed + n * 29, 0.06, 4), 1.4, awake, alpha * 0.9)
	if layer == Kit.BACK and not air:
		vfx.scorch(canvas, from.x, head.x, 1.0 - clampf((t - start - move.active) / 24.0, 0.0, 1.0))

## The beam (from `shape`) with its spiked head and the lance of light leading it.
func draw_beam(canvas: Node2D, layer: int, beam: Dictionary, awake: bool, seed: int) -> void:
	var head: Vector2 = beam.head
	var size: float = beam.width
	var alpha: float = beam.alpha
	var point: float = float(beam.point) * alpha
	vfx.beam(canvas, layer, beam.from, head, size, alpha, awake, seed, false)
	vfx.spearhead(canvas, layer, head, beam.tip, size, alpha, point, awake)
	vfx.star(canvas, layer, head, size * lerpf(0.7, 1.25, point), 9, seed, point, Color(0.9, 0.98, 1.0), Kit.bolt_glow(awake))

func linger(fighters: Array, _actors: Array) -> void:
	for f in fighters:
		var held: Dictionary = _live.get(f.slot, {})
		if held.is_empty():
			continue
		var running: bool = f.move != null and handles_air(f.move) and f.attack_instance == int(held.instance)
		if running:
			continue
		# The air dash ended (touchdown or interruption): keep eroding its beam.
		_beams.append({"tail": held.tail, "head": held.head, "born": vfx.time, "awake": held.awake, "seed": held.seed,
			"thickness": held.thickness, "alpha": held.alpha})
		_live.erase(f.slot)
		if f.grounded and int(_landed.get(f.slot, -1)) != f.attack_instance:
			_landed[f.slot] = f.attack_instance
			var feet: Vector2 = vfx.world(f, Vector2(0.0, -2.0))
			vfx.spark_burst(feet, 18, Vector2(0.0, -0.6), 90.0, 220.0, f.attack_instance * 7 + 3)
			vfx.debris_burst(feet, 5, Vector2.ZERO, f.attack_instance * 7 + 5)
			vfx.bursts.append({"kind": "star", "at": feet + Vector2(0.0, -8.0), "age": 0.0, "life": 0.16, "size": 22.0, "facing": float(f.facing),
				"seed": f.attack_instance * 7 + 9, "fill": Kit.GOLD_HOT, "rim": Kit.EMBER})
	_beams = _beams.filter(func(b: Dictionary) -> bool: return vfx.time - float(b.born) < LINGER)

func handles_air(move: Resource) -> bool:
	return move.id in ["zenitsu_j236A", "zenitsu_j236C"]

func draw_lingering(canvas: Node2D, layer: int) -> void:
	for held: Dictionary in _beams:
		var k := clampf((vfx.time - float(held.born)) / LINGER, 0.0, 1.0)
		vfx.set_base(canvas, Transform2D(0.0, Vector2(vfx.camera.zoom, vfx.camera.zoom), 0.0, Vector2.ZERO))
		var tail: Vector2 = vfx.camera.point(held.tail) / vfx.camera.zoom
		var head: Vector2 = vfx.camera.point(held.head) / vfx.camera.zoom
		var size: float = float(held.thickness) * lerpf(0.55, 0.4, k)
		var alpha: float = float(held.alpha) * (1.0 - k)
		vfx.beam(canvas, layer, tail.lerp(head, k), head, size, alpha, bool(held.awake), int(held.seed), false)
		vfx.spearhead(canvas, layer, head, head + (head - tail).normalized() * size * 0.8, size, alpha, 0.0, bool(held.awake))

func reset() -> void:
	super()
	_beams.clear()
	_live.clear()
	_landed.clear()
