extends "res://scripts/presentation/vfx/akaza/technique.gd"
## Kicks (5B/5D, 2B/2D, jB/jD): a white crescent of displaced air along the
## path of the foot, with a coloured rim on heavies; heavy ground kicks kick up
## dust at the planted foot, and the 2D sweep drags a low arc and a dust trail
## along the floor.

## Foot paths by clip (start, control, end in fighter-local units), fitted to the
## drawn active frames of the v3 art (tools/build_vfx_fit_sheet.py): the front kick
## rises to the chest, 5D's high kick to the head, the crouching kick stays low,
## the sweep skims the floor and the air kicks slant forward or stamp down.
const CURVES := {
	"body_stand_light": [Vector2(-2, -7), Vector2(19, -54), Vector2(37, -48)],
	"body_stand_heavy": [Vector2(-8, -10), Vector2(12, -68), Vector2(36, -57)],
	"body_crouch_light": [Vector2(2, -4), Vector2(17, -13), Vector2(28, -8)],
	"body_crouch_heavy": [Vector2(-26, -3), Vector2(10, -10), Vector2(32, -6)],
	"body_air_light": [Vector2(-2, -28), Vector2(18, -52), Vector2(35, -44)],
	"body_air_heavy": [Vector2(-2, -44), Vector2(20, -36), Vector2(28, -16)],
}

func path(move: Resource) -> Paths.Sweep:
	var curve: Array = CURVES.get(move.clip_id(), CURVES["body_stand_light"])
	return Paths.Sweep.new(curve[0], curve[1], curve[2], 13.0 if heavy(move) else 8.0)

func sweep(move: Resource) -> bool:
	return move.clip_id() == "body_crouch_heavy"

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	if tick != move.startup:
		return
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 181 + f.slot * 7919 + tick * 37
	var curve := path(move)
	var tip: Vector2 = vfx.world(f, curve.point(1.0, 0.0))
	vfx.spark_burst(tip, 10 if heavy(move) else 5, Vector2(float(f.facing), -0.2), 60.0, 170.0, seed)
	if heavy(move):
		vfx.flake_burst(tip, 3, 40.0, seed + 1, awake, 10.0)
		if f.grounded:
			vfx.dust_burst(vfx.world(f, Vector2(-8.0, 0.0)), 3, Vector2(-0.3, 0.0), seed + 2, 0.9)
	if sweep(move):
		for n in range(4):
			vfx.dust_burst(vfx.world(f, Vector2(lerpf(-16.0, 56.0, n / 3.0), 0.0)), 2, Vector2(0.6, 0.0), seed + 10 + n, 0.8)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var since := clock(f) - float(move.startup)
	var head := clampf((since + 1.0) / 2.2, 0.0, 1.0)
	var tail := clampf((since - 1.5) / (7.0 if heavy(move) else 5.0), 0.0, 1.25)
	if head <= 0.0 or tail >= 1.0:
		return
	vfx.crescent(canvas, layer, path(move), head, tail, 1.0 if heavy(move) else 0.8, awake)
	if sweep(move) and layer == Kit.FRONT:
		# The sweep's flat ring of air skims the floor round the planted foot.
		var k := clampf((since + 1.0) / 6.0, 0.0, 1.0)
		vfx.ring(canvas, layer, Vector2(14.0, -1.0), Vector2(lerpf(20.0, 46.0, k), lerpf(4.0, 9.0, k)), 0.0, 1.0 - tail, 2.0, awake)
