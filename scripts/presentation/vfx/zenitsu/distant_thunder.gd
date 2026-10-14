extends "res://scripts/presentation/vfx/zenitsu/thunderclap.gd"
## 雷之呼吸·肆之型 远雷 (j.214B/D): he stops dead in the air inside a crackling
## sphere of lightning, then flashes forward and down; a bolt of distant thunder
## strikes from the sky onto the head of the flash as it leaves. The beam and
## its touchdown hand-off are the air dash's (thunderclap.gd).

func thickness(move: Resource) -> float:
	return 13.0 if heavy(move) else 10.0

func handles_air(move: Resource) -> bool:
	return move.id in ["zenitsu_j214B", "zenitsu_j214D"]

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	super(f, actor, tick)
	var move: Resource = f.move
	if tick == move.startup:
		var at: Vector2 = vfx.world(f, Vector2(10.0, height(move)))
		vfx.spark_burst(at, 16, Vector2(0.0, -0.8), 80.0, 220.0, f.attack_instance * 7 + 1, Kit.CYAN)
		vfx.bursts.append({"kind": "star", "at": at, "age": 0.0, "life": 0.14, "size": 20.0, "facing": float(f.facing), "seed": f.attack_instance * 7 + 2,
			"fill": Color(0.88, 0.97, 1.0), "rim": Kit.bolt_glow(actor.form_active())})

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var seed: int = f.attack_instance * 59 + f.move_frame
	if t < start + 1.0:
		var k := clampf(t / maxf(start, 1.0), 0.0, 1.0)
		vfx.sphere(canvas, layer, Vector2(2.0, -38.0), lerpf(26.0, 40.0, k), 0.4 + 0.6 * k, awake, seed)
		if layer == Kit.LIGHT:
			vfx.body_flash(canvas, f, actor, Color(Kit.bolt_glow(awake), 0.3 * k))
	if t < start:
		return
	# The beam, speed lines and lit body of the air dash.
	_draw_dash(canvas, layer, f, actor, t)
	# Distant thunder: a sky bolt onto the head of the flash, re-struck each tick.
	var strike := 1.0 - clampf((t - start) / 7.0, 0.0, 1.0)
	if strike > 0.0:
		var target := origin_local(f, height(move)) + Vector2(14.0, 0.0)
		var trunk := Bolt.path(target + Vector2(-30.0, -300.0), target, seed, 0.1, 5)
		vfx.bolt(canvas, layer, trunk, 3.0, awake, strike)
		for branch in Bolt.forks(trunk, seed + 9, 4, 40.0):
			vfx.bolt(canvas, layer, branch, 1.4, awake, strike * 0.7)

func _draw_dash(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D, t: float) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var start := float(move.startup)
	var seed: int = f.attack_instance * 53 + f.move_frame
	var h := height(move)
	var head := Vector2(10.0, h)
	var tail := origin_local(f, h)
	var e := erosion(t, move)
	var from := tail.lerp(head, e)
	var alpha := 1.0 - smoothstep(0.8, 1.0, e)
	var dashing: bool = t < start + move.active
	vfx.beam(canvas, layer, from, head, thickness(move), alpha, awake, seed, dashing)
	if dashing and layer == Kit.FRONT:
		vfx.speed_lines(canvas, from, head, seed, 6, 1.0)
	if dashing and layer == Kit.LIGHT:
		vfx.body_flash(canvas, f, actor, Color(Kit.CYAN, 0.45))
	vfx.bolt(canvas, layer, Bolt.path(from, head, seed + 3, 0.07, 4), 1.6, awake, alpha)
