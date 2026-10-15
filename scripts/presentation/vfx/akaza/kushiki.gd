extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·空式 (236A/C) and 空式·下 (j.236A/C): after the red start-up the punch
## twists the air in front of the fist into a swirl and a white ring, and the
## blow flies on as a comet of compressed air: a white-hot head in a cyan body
## (blue-violet when awakened), swirling rings and a tapering tail shedding
## glints. The air version flies down at a slant; where it meets the floor it
## breaks it: a few slabs of stone tip up, rocks fly, dust rings out and a
## shallow crater stays.

## The punching fist (drawn air_type frames, roster-v1 art); combat spawns the
## shot lower and behind it, at (27, -32).
const RELEASE := Vector2(43.0, -46.0)
## The ground comet is drawn this much above the shot's centre (still inside its
## box) so it leaves the fist at chest height.
const LIFT := -12.0
## Seconds a floor crater stays.
const CRATER := 1.2

func size(move: Resource) -> float:
	return 16.0 if heavy(move) else 13.0

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	emit_activation(f, tick)
	if tick != move.startup:
		return
	var seed: int = f.attack_instance * 191 + f.slot * 7919
	var at: Vector2 = vfx.world(f, RELEASE)
	vfx.spark_burst(at, 12, Vector2(float(f.facing), 0.0), 80.0, 200.0, seed, Kit.tone(awake).lerp(Kit.WHITE, 0.4))
	vfx.flake_burst(at, 4, 40.0, seed + 1, awake, 6.0)
	vfx.bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.2, "size": 14.0, "squash": 1.6, "facing": float(f.facing), "seed": seed + 2, "awake": awake})
	if f.grounded:
		vfx.dust_burst(vfx.world(f, Vector2(-10.0, 0.0)), 4, Vector2(-0.6, 0.0), seed + 3, 0.9)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var since := t - float(move.startup)
	var red := activation_strength(t)
	if red > 0.0:
		vfx.activation(canvas, layer, f, actor, red, f.attack_instance * 7)
	# The swirl twisting round the fist as the blow leaves it.
	var swirl := 1.0 - clampf((since - 1.0) / 6.0, 0.0, 1.0)
	if since >= -2.0 and swirl > 0.0:
		var grow := clampf((since + 2.0) / 3.0, 0.0, 1.0)
		vfx.vortex(canvas, layer, RELEASE, lerpf(6.0, 13.0, grow), since * 0.8, swirl * grow, awake)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.15 if heavy(move) else 1.0, awakened)
	if event.type == "hit":
		vfx.bursts.append({"kind": "ring", "at": event.position, "age": 0.0, "life": 0.22, "size": 20.0, "squash": 0.7,
			"facing": float(attacker.facing), "seed": attacker.attack_instance * 5 + 1, "awake": awakened})

func emit_shot(shot: Dictionary, awakened: bool) -> void:
	var seed: int = int(shot.instance) * 97 + int(shot.life) * 13
	var move: Resource = vfx.combat.moves[shot.move]
	# Trail from where the comet is drawn (the ground one sits LIFT above its box).
	var at := Vector2(float(shot.x), float(shot.y) + (0.0 if move.stance == "air" else LIFT))
	var back := -Vector2(float(shot.vx), float(shot.vy)).normalized()
	for n in range(2):
		vfx.sparks.spawn(at + back * 6.0, back * lerpf(40.0, 110.0, vfx.rand(seed, n)) + Vector2(0.0, lerpf(-30.0, 30.0, vfx.rand(seed, n + 5))),
			lerpf(0.12, 0.24, vfx.rand(seed, n + 10)), lerpf(1.4, 2.4, vfx.rand(seed, n + 15)), 0, Kit.tone(awakened).lerp(Kit.WHITE, 0.3), 0.0, 3.0, 0.0, 0.0, 0.5, 2.0)
	if int(shot.life) % 3 == 0:
		vfx.flake_burst(at + back * 8.0, 1, 20.0, seed + 3, awakened, 10.0)

func draw_shot(canvas: Node2D, layer: int, shot: Dictionary, awakened: bool) -> void:
	var move: Resource = vfx.combat.moves[shot.move]
	var r := size(move)
	var heading := Vector2(absf(float(shot.vx)), float(shot.get("vy", 0.0))).normalized()
	# Grow in over the first ticks, and lift the ground comet to chest height.
	var age: float = float(move.projectile_lifetime - int(shot.life)) + vfx.frac
	r *= clampf(0.35 + age / 3.0, 0.35, 1.0)
	if move.stance != "air":
		vfx.set_base(canvas, vfx.base * Transform2D(0.0, Vector2(0.0, LIFT)))
	var spin: float = float(shot.life) * 0.55
	var tail := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(8):
		var u := n / 7.0
		tail.append(-heading * r * lerpf(3.4, 0.0, u))
		widths.append(r * lerpf(0.1, 1.15, pow(u, 0.6)))
		tint.append(Color(1, 1, 1, smoothstep(0.0, 0.6, u)))
	match layer:
		Kit.GLOW:
			Ribbon.draw(canvas, tail, vfx._scaled(widths, 2.2), vfx._tinted(tint, Color(Kit.deep(awakened), 0.4)), vfx.band)
			if vfx.glow != null:
				canvas.draw_texture_rect(vfx.glow, Rect2(-Vector2.ONE * r * 2.2, Vector2.ONE * r * 4.4), false, Color(Kit.deep(awakened), 0.5))
		Kit.FRONT:
			Ribbon.draw(canvas, tail, widths, vfx._tinted(tint, Color(Kit.tone(awakened), 0.9)), vfx.band)
			# The head: the fluffy shock ball, turning as it flies.
			vfx.burst_sprite(canvas, Vector2.ZERO, r * 0.95, int(shot.instance) * 3, 0.0, 0.95, awakened, spin * 0.4)
		Kit.LIGHT:
			if vfx.glow != null:
				canvas.draw_texture_rect(vfx.glow, Rect2(-Vector2.ONE * r * 1.2, Vector2.ONE * r * 2.4), false, Color(Kit.ICE, 0.7))
	# Swirling rings of air round the head, turning as it flies.
	for k in range(2):
		vfx.ring(canvas, layer, -heading * r * (0.4 + 0.9 * k), Vector2(r * (0.45 + 0.25 * k), r * (1.05 + 0.35 * k)), heading.angle() + spin * (1.0 if k == 0 else -0.7) * 0.15,
			0.75 - 0.25 * k, 1.8, awakened)

func shot_ended(shot: Dictionary, awakened: bool) -> void:
	var at := Vector2(float(shot.x), float(shot.y))
	var seed: int = int(shot.instance) * 211 + 17
	if float(shot.vy) > 0.0 and at.y >= Arena.FLOOR_Y - 14.0:
		# 空式·下 meets the floor: slabs of stone, flying rock, a ring of dust and a crater.
		var floor_at := Vector2(at.x, Arena.FLOOR_Y)
		var facing := 1.0 if float(shot.vx) >= 0.0 else -1.0
		vfx.bursts.append({"kind": "shock", "at": floor_at + Vector2(0.0, -6.0), "age": 0.0, "life": 0.2, "size": 15.0, "facing": facing, "seed": seed, "awake": awakened})
		vfx.bursts.append({"kind": "rubble", "technique": self, "at": floor_at, "age": 0.0, "life": 0.5, "size": 18.0, "facing": facing, "seed": seed + 1, "awake": awakened})
		vfx.bursts.append({"kind": "crater", "technique": self, "at": floor_at, "age": 0.0, "life": CRATER, "size": 14.0, "facing": 1.0, "seed": seed + 2})
		vfx.dust_burst(floor_at, 5, Vector2(facing * 0.3, 0.0), seed + 3, 0.9)
		vfx.debris_burst(floor_at, 6, Vector2(facing * 0.3, 0.0), seed + 4, true)
		vfx.flake_burst(floor_at + Vector2(0.0, -6.0), 3, 60.0, seed + 5, awakened)
	else:
		# Spent at the end of its range (or cancelled by a clash): the air disperses.
		vfx.bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.2, "size": 12.0, "squash": 1.3, "facing": 1.0, "seed": seed, "awake": awakened})
		vfx.flake_burst(at, 3, 40.0, seed + 1, awakened, 6.0)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	match burst.kind:
		"rubble":
			var rise := 1.0 - pow(1.0 - clampf(k / 0.18, 0.0, 1.0), 3.0)
			var sink := 1.0 - smoothstep(0.55, 1.0, k)
			vfx.rubble(canvas, layer, Vector2.ZERO, float(burst.size), rise * sink, int(burst.seed), bool(burst.awake), 5)
		"crater":
			if layer == Kit.FLOOR:
				vfx.crater(canvas, Vector2.ZERO, float(burst.size), 1.0 - smoothstep(0.6, 1.0, k), int(burst.seed))
