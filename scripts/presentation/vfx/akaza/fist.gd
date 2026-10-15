extends "res://scripts/presentation/vfx/akaza/technique.gd"
## Punches (5A/5C, 2A/2C, jA/jC and 碎式·贰): the air in front of the fist is
## pushed into white pressure rings. A jab leaves one ring and a few speed lines
## along the arm; a heavy straight drives a cone of rings, a streak along the arm
## and a swirl round the fist; the swinging heavies (2C's uppercut, jC's downward
## hammer) leave a white crescent along the swing instead of the cone.

## Shoulder and fist in fighter-local units, by clip, measured on the drawn
## active frames (roster-v1 art; refit after the v3 redraw). "swing" (start,
## control, end) marks a swinging punch.
const POSES := {
	"stand_light": {"shoulder": Vector2(10, -58), "fist": Vector2(43, -56)},
	"stand_heavy": {"shoulder": Vector2(8, -57), "fist": Vector2(43, -53)},
	"crouch_light": {"shoulder": Vector2(6, -42), "fist": Vector2(34, -39)},
	"crouch_heavy": {"shoulder": Vector2(8, -42), "fist": Vector2(25, -62), "swing": [Vector2(30, -18), Vector2(40, -48), Vector2(22, -68)]},
	"air_light": {"shoulder": Vector2(12, -62), "fist": Vector2(49, -61)},
	"air_heavy": {"shoulder": Vector2(8, -46), "fist": Vector2(41, -11), "swing": [Vector2(22, -58), Vector2(48, -42), Vector2(42, -8)]},
}

func pose(move: Resource) -> Dictionary:
	return POSES.get(move.clip_id(), POSES["stand_light"])

func big(move: Resource) -> bool:
	return move.kind == "heavy"

func swing(move: Resource) -> Paths.Sweep:
	var keys: Array = pose(move).swing
	return Paths.Sweep.new(keys[0], keys[1], keys[2], 13.0)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	if tick != move.startup:
		return
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 173 + f.slot * 7919 + tick * 31
	var shape := pose(move)
	var fist: Vector2 = shape.fist
	var shoulder: Vector2 = shape.shoulder
	var at: Vector2 = vfx.world(f, fist)
	var aim: Vector2 = (fist - shoulder).normalized()
	vfx.spark_burst(at, 12 if big(move) else 6, vfx.world_dir(f, aim) * 0.8, 70.0, 190.0, seed)
	if big(move):
		vfx.flake_burst(at, 3, 50.0, seed + 1, awake, 10.0)
		if f.grounded:
			vfx.dust_burst(vfx.world(f, Vector2(-6.0, 0.0)), 3, Vector2(-0.4, 0.0), seed + 2, 0.8)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var since := clock(f) - float(move.startup)
	if since < -1.0 or since > move.active + 8.0:
		return
	var shape := pose(move)
	var fist: Vector2 = shape.fist
	var shoulder: Vector2 = shape.shoulder
	var aim: Vector2 = (fist - shoulder).normalized()
	var fade := 1.0 - clampf((since - move.active + 1.0) / 7.0, 0.0, 1.0)
	if shape.has("swing"):
		var head := clampf((since + 1.0) / 2.0, 0.0, 1.0)
		var tail := clampf((since - 1.0) / 6.0, 0.0, 1.25)
		var path := swing(move)
		vfx.crescent(canvas, layer, path, head, tail, 1.0, awake)
		var k := clampf((since + 1.0) / 5.0, 0.0, 1.0)
		var along: Vector2 = (path.point(1.0, 0.0) - path.point(0.9, 0.0)).normalized()
		vfx.ring(canvas, layer, fist + along * (4.0 + 8.0 * k), Vector2(lerpf(3.0, 6.0, k), lerpf(8.0, 15.0, k)), along.angle(), fade * (1.0 - 0.4 * k), 2.0, awake)
		return
	if big(move):
		# A cone of rings opening ahead of the fist, a streak along the arm, a swirl.
		for n in range(2):
			var k := clampf((since + 1.0 - n) / 5.0, 0.0, 1.0)
			if k <= 0.0:
				continue
			var center: Vector2 = fist + aim * (6.0 + 10.0 * n + 8.0 * k)
			vfx.ring(canvas, layer, center, Vector2(lerpf(3.0, 6.0, k), lerpf(9.0, 16.0, k) + 4.0 * n), aim.angle(), fade * (1.0 - 0.4 * k), 2.2, awake)
		vfx.needle(canvas, layer, shoulder + aim * 6.0, fist + aim * lerpf(6.0, 20.0, clampf((since + 1.0) / 3.0, 0.0, 1.0)), 4.0, fade * 0.8, awake)
		vfx.vortex(canvas, layer, fist, 9.0, since * 0.9, fade * 0.9, awake)
		if layer == Kit.LIGHT and vfx.glow != null:
			canvas.draw_texture_rect(vfx.glow, Rect2(fist - Vector2.ONE * 12.0, Vector2.ONE * 24.0), false, Color(Kit.tone(awake), 0.5 * fade))
		return
	var push := clampf((since + 1.0) / 6.0, 0.0, 1.0)
	vfx.ring(canvas, layer, fist + aim * (4.0 + 8.0 * push), Vector2(lerpf(2.5, 4.5, push), lerpf(7.0, 13.0, push)), aim.angle(), fade * (1.0 - 0.3 * push), 1.6, awake)
	if layer == Kit.FRONT:
		var across := aim.orthogonal()
		for n in range(3):
			var off := across * (n - 1) * 3.5
			canvas.draw_line(shoulder + aim * 4.0 + off, fist - aim * 5.0 + off * 0.6, Color(Kit.WHITE, 0.35 * fade * (1.0 - 0.25 * absf(n - 1))), 0.8, true)
