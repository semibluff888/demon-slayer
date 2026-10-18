extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 血鬼术·爆血 (super): through the super freeze her blood gathers in a ring of
## black-red ink while tongues of pink fire spiral in round her; then four kicks,
## each tearing a crescent of fire (the middle ones small, the last the largest),
## and the last sets the floor alight after 爆炎裂: a line of fire races along
## the ground to her target and a whirl of flame rises there, leaving a
## scorched streak. The super draws its own charge, so SuperView skips the shared
## energy sphere.

## Kick crescents (start, control, end): a front kick, a roundhouse, a high kick and
## the big rising finisher. KICKS on the v3 blood_burst frames (the feet near (28, -43),
## (29, -48), (30, -53), then straight up to (13, -70)); DEMON_KICKS on the kept
## demon-form drawing (the feet near (41..49, -55)).
const KICKS := [
	[Vector2(-8, -8), Vector2(6, -49), Vector2(29, -44)],
	[Vector2(-9, -12), Vector2(10, -45), Vector2(30, -48)],
	[Vector2(-10, -12), Vector2(2, -62), Vector2(31, -54)],
	[Vector2(-6, -5), Vector2(28, -22), Vector2(16, -72)],
]
const DEMON_KICKS := [
	[Vector2(-4, -10), Vector2(16, -62), Vector2(44, -56)],
	[Vector2(-2, -8), Vector2(22, -40), Vector2(46, -44)],
	[Vector2(-4, -12), Vector2(14, -68), Vector2(48, -58)],
	[Vector2(-10, -6), Vector2(30, -20), Vector2(50, -76)],
]
const FIRE_LINE := 0.55
const WHIRL := 0.7
const SCORCH := 1.6
## Ticks before the last kick that the floor catches: the fire races to the target and
## reaches it as that kick lands (user review, 2026-10-18: the line and the whirl used to
## start at the last hit and peak half a second later, after everything else had ended).
const LINE_LEAD := 4

## Attack instance whose fire line already runs, by slot.
var _lines: Dictionary = {}

func reset() -> void:
	super()
	_lines.clear()

## 爆炎裂: the line of fire from her feet to `target_x` and the scorch it leaves.
func ignite(f: RefCounted, target_x: float, awakened: bool) -> void:
	if int(_lines.get(f.slot, -1)) == f.attack_instance:
		return
	_lines[f.slot] = f.attack_instance
	var seed: int = f.attack_instance * 263 + 3
	var feet := Vector2(f.x, Arena.FLOOR_Y)
	var reach: float = absf(target_x - feet.x)
	vfx.bursts.append({"kind": "fire_line", "technique": self, "at": feet, "age": 0.0, "life": FIRE_LINE, "size": 1.0, "facing": float(f.facing),
		"seed": seed, "awake": awakened, "to": reach + 16.0})
	vfx.bursts.append({"kind": "scorch", "technique": self, "at": feet, "age": 0.0, "life": SCORCH, "size": 1.0, "facing": float(f.facing), "seed": seed + 2,
		"awake": awakened, "to": reach + 24.0})

## The kick's crescent, stretched out to the super's long hit box (80 percent of it) except
## the rising finisher, which stays up over her head.
func kick_keys(f: RefCounted, move: Resource, index: int) -> Array:
	var kicks: Array = fit(f, KICKS, DEMON_KICKS)
	var keys: Array = kicks[mini(index, kicks.size() - 1)]
	return keys if index >= kicks.size() - 1 else reaching(move, keys, 0.8)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 257 + f.slot * 7919 + tick * 29
	emit_activation(f, tick, awake)
	if tick < move.startup:
		if tick % 2 == 0:
			vfx.flake_burst(vfx.world(f, Vector2(10.0, -40.0) * vfx.drawn(f)), 2, 40.0, seed, awake, 10.0)
		return
	var list := starts(move)
	var other = vfx.combat.fighters[1 - f.slot]
	if tick == int(list[-1]) - LINE_LEAD and not f.hit_registry.is_empty() and str(other.state) in ["hit", "knockdown"]:
		# The super has connected: the floor catches now and the fire meets the last kick.
		ignite(f, float(other.x), awake)
	if tick in list:
		var index := list.find(tick)
		var keys: Array = kick_keys(f, move, index)
		vfx.ember_burst(vfx.world(f, keys[2]), 10 + 4 * index, Vector2(float(f.facing), -0.3), 80.0, 220.0, seed + index, awake)
		vfx.dust_burst(vfx.world(f, Vector2(-6.0, 0.0)), 3, Vector2(-0.4, 0.0), seed + 10 + index, 1.0)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.5 if last else 0.8, awakened, last)
	if not last or event.type != "hit":
		return
	# 爆炎裂: the floor caught just before this kick (or catches now, if only the last kick
	# connected), and the whirl of flame erupts on the impact itself.
	var seed: int = attacker.attack_instance * 263 + 3
	var target := Vector2(float(event.position.x), Arena.FLOOR_Y)
	ignite(attacker, target.x, awakened)
	vfx.bursts.append({"kind": "whirl", "technique": self, "at": target, "age": 0.0, "life": WHIRL, "size": 1.0, "facing": float(attacker.facing), "seed": seed + 1,
		"awake": awakened})
	vfx.flake_burst(target + Vector2(0.0, -30.0), 12, 120.0, seed + 3, awakened, 80.0)
	vfx.dust_burst(target, 6, Vector2.ZERO, seed + 4, 1.3)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var age := charge_age(f)
	if t < start + 1.0:
		# The charge: blood gathering, fire spiralling in.
		var k := clampf(age / float(move.freeze_frames + move.startup), 0.0, 1.0)
		vfx.activation(canvas, layer, f, actor, minf(1.0, 0.4 + k), f.attack_instance * 19, awake)
		var size: float = vfx.drawn(f)
		for n in range(3):
			var a0 := age * 0.32 + n * TAU / 3.0
			var path := Paths.Arc.new(Vector2(0.0, -40.0) * size, a0, a0 + 2.0, (46.0 - 18.0 * k) * size, (26.0 - 10.0 * k) * size, 12.0)
			path.squash = 0.8
			path.profile = "crescent"
			vfx.flame_along(canvas, layer, path, 1.0, 0.0, 0.85 * k, awake, 1.0, f.attack_instance + n, 16)
		if t < start:
			return
	var list := starts(move)
	for index in range(list.size()):
		var since := t - float(list[index])
		var head := clampf((since + 1.0) / 2.0, 0.0, 1.0)
		var tail := clampf((since - 1.0) / 6.0, 0.0, 1.25)
		if head <= 0.0 or tail >= 1.0:
			continue
		var keys: Array = kick_keys(f, move, index)
		var big := index == list.size() - 1
		var curve := Paths.Sweep.new(keys[0], keys[1], keys[2], 20.0 if big else 13.0)
		vfx.flame_along(canvas, layer, curve, head, tail, 1.0, awake, 1.7 if big else 1.2, f.attack_instance + index)
		vfx.crescent(canvas, layer, curve, head, clampf(tail + 0.15, 0.0, 1.0), 0.8, awake)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	var awake: bool = burst.get("awake", false)
	var seed: int = burst.seed
	match burst.kind:
		"fire_line":
			# A tongue of fire racing along the floor, its head reaching the target in the
			# LINE_LEAD ticks before the last kick lands.
			var run := 1.0 - pow(1.0 - clampf(k / 0.12, 0.0, 1.0), 2.0)
			var fade := 1.0 - smoothstep(0.5, 1.0, k)
			var reach: float = float(burst.to) * run
			if reach < 6.0:
				return
			var points := PackedVector2Array()
			var widths := PackedFloat32Array()
			var alphas := PackedFloat32Array()
			for n in range(16):
				var u := n / 15.0
				points.append(Vector2(reach * u, -3.0 - sin(u * PI) * 2.0))
				widths.append(lerpf(6.0, 16.0, u) * (1.0 - 0.5 * smoothstep(0.9, 1.0, u)))
				alphas.append(fade * smoothstep(0.0, 0.2, u))
			vfx.flame(canvas, layer, points, widths, alphas, awake, seed)
			vfx.pillar(canvas, layer, Vector2(reach, 0.0), 26.0 * fade, 18.0, fade, awake, seed + 1, k)
		"whirl":
			# The whirl of flame bursting up where the fire reaches her target: already a third
			# up while the hit stops, full a few frames later, burnt out as she recovers.
			var grow := clampf(0.35 + k / 0.15, 0.0, 1.0)
			var fade := 1.0 - smoothstep(0.6, 1.0, k)
			if grow <= 0.0:
				return
			vfx.tornado(canvas, layer, Vector2.ZERO, 120.0 * (0.45 + 0.55 * grow), 22.0 + 8.0 * grow, k * 9.0, fade * grow, awake, seed)
		"scorch":
			var reach: float = float(burst.to) * clampf(k / 0.25, 0.0, 1.0)
			vfx.scorch(canvas, layer, -6.0, reach, 1.0 - smoothstep(0.6, 1.0, k), seed, 0.8 * (1.0 - smoothstep(0.2, 0.6, k)), awake)
