extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## Kicks (5B/5D, 2B/2D, jB/jD): a white crescent of displaced air along the path
## of the foot; heavies drag a tongue of pink fire along it and kick up dust at
## the planted foot, and the 2D sweep skims a flat ring and a dust trail along
## the floor.

## Foot paths by clip (start, control, end in fighter-local units), fitted to the
## drawn active frames: the front kick rises to the chest, 5D's high kick to the
## head, the crouching kick stays low, the sweep skims the floor, the air kicks
## slant forward or stamp down. CURVES fits the v3 drawing (the foot tips measured
## on the packed atlas), DEMON_CURVES the kept demon-form drawing.
const CURVES := {
	"body_stand_light": [Vector2(-3, -12), Vector2(13, -51), Vector2(29, -46)],
	"body_stand_heavy": [Vector2(-8, -10), Vector2(6, -68), Vector2(31, -57)],
	"body_crouch_light": [Vector2(5, -2), Vector2(18, -13), Vector2(33, -12)],
	"body_crouch_heavy": [Vector2(-25, -2), Vector2(0, -3), Vector2(32, -3)],
	"body_air_light": [Vector2(1, -23), Vector2(17, -45), Vector2(32, -41)],
	"body_air_heavy": [Vector2(-7, -38), Vector2(20, -34), Vector2(25, -13)],
}
const DEMON_CURVES := {
	"body_stand_light": [Vector2(-2, -8), Vector2(16, -52), Vector2(36, -48)],
	"body_stand_heavy": [Vector2(-8, -10), Vector2(10, -70), Vector2(40, -54)],
	"body_crouch_light": [Vector2(2, -4), Vector2(18, -18), Vector2(35, -17)],
	"body_crouch_heavy": [Vector2(-26, -3), Vector2(10, -8), Vector2(42, -9)],
	"body_air_light": [Vector2(-2, -28), Vector2(18, -54), Vector2(35, -49)],
	"body_air_heavy": [Vector2(-2, -48), Vector2(30, -42), Vector2(36, -18)],
}

func path(f: RefCounted, move: Resource) -> Paths.Sweep:
	var table: Dictionary = fit(f, CURVES, DEMON_CURVES)
	var curve: Array = reaching(move, table.get(move.clip_id(), table["body_stand_light"]))
	return Paths.Sweep.new(curve[0], curve[1], curve[2], 13.0 if heavy(move) else 8.0)

func sweep(move: Resource) -> bool:
	return move.clip_id() == "body_crouch_heavy"

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	if tick != move.startup:
		return
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 181 + f.slot * 7919 + tick * 37
	var curve := path(f, move)
	var tip: Vector2 = vfx.world(f, curve.point(1.0, 0.0))
	vfx.ember_burst(tip, 10 if heavy(move) else 5, Vector2(float(f.facing), -0.2), 60.0, 170.0, seed, awake)
	if heavy(move):
		vfx.flake_burst(tip, 3, 40.0, seed + 1, awake, 10.0)
		if f.grounded:
			vfx.dust_burst(vfx.world(f, Vector2(-8.0, 0.0)), 3, Vector2(-0.3, 0.0), seed + 2, 0.9)
	if sweep(move):
		for n in range(4):
			vfx.dust_burst(vfx.world(f, Vector2(lerpf(-16.0, 56.0, n / 3.0) * vfx.drawn(f), 0.0)), 2, Vector2(0.6, 0.0), seed + 10 + n, 0.8)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var since := clock(f) - float(move.startup)
	var head := clampf((since + 1.0) / 2.2, 0.0, 1.0)
	var tail := clampf((since - 1.5) / (7.0 if heavy(move) else 5.0), 0.0, 1.25)
	if head <= 0.0 or tail >= 1.0:
		return
	var curve := path(f, move)
	vfx.crescent(canvas, layer, curve, head, tail, 1.0 if heavy(move) else 0.8, awake)
	if heavy(move):
		vfx.flame_along(canvas, layer, curve, head, clampf(tail + 0.15, 0.0, 1.0), 0.9, awake, 1.0, f.attack_instance)
	if sweep(move) and layer == Kit.FRONT:
		# The sweep's flat ring of air skims the floor round the planted foot.
		var k := clampf((since + 1.0) / 6.0, 0.0, 1.0)
		var size: float = vfx.drawn(f)
		vfx.ring(canvas, layer, Vector2(14.0, -1.0) * size, Vector2(lerpf(20.0, 46.0, k), lerpf(4.0, 9.0, k)) * size, 0.0, 1.0 - tail, 2.0, awake)
