extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 滑踢 (3D): she skims along the floor feet first; a low tongue of pink fire runs
## ahead of her foot (the effect leads the body, as every dash does), smoke rolls
## up behind and a scorched streak stays on the floor where she slid.

## The sliding foot (v3 slide_kick frames; DEMON_FOOT on the kept demon-form
## drawing, body_crouch_heavy) and how far past the front of the hit box the fire's
## head runs.
const FOOT := Vector2(30, -8)
const DEMON_FOOT := Vector2(40, -9)
const LEAD := 4.0
const SCORCH := 1.2

## The fire's head at move time `t`: from the foot to just past the hit box.
func head(f: RefCounted, t: float) -> Vector2:
	var move: Resource = f.move
	var on := clampf((t - float(move.startup) + 4.0) / 4.0, 0.0, 1.0)
	var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
	return Vector2(lerpf(foot.x, move.box.end.x / vfx.body_scale() + LEAD, on), foot.y)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 199 + f.slot * 7919 + tick * 47
	mark_origin(f, tick)
	if tick < move.startup - 4 or tick >= move.startup + move.active:
		return
	var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
	vfx.dust_burst(vfx.world(f, Vector2(-6.0, 0.0)), 2, Vector2(-0.5, 0.0), seed, 0.9)
	vfx.ember_burst(vfx.world(f, foot), 3, Vector2(0.6, -0.3), 50.0, 140.0, seed + 1, awake)
	if tick == move.startup + move.active - 1:
		var from: Vector2 = origin_local(f, 0.0)
		vfx.bursts.append({"kind": "scorch", "technique": self, "at": vfx.world(f, Vector2.ZERO), "age": 0.0, "life": SCORCH, "size": 1.0,
			"facing": float(f.facing), "seed": seed + 2, "awake": awake, "from": (from.x - 6.0) * vfx.body_scale(), "to": (foot.x + 6.0) * vfx.body_scale()})

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var on := clampf((t - move.startup + 4.0) / 4.0, 0.0, 1.0)
	var fade := 1.0 - clampf((t - move.startup - move.active) / 5.0, 0.0, 1.0)
	if on <= 0.0 or fade <= 0.0:
		return
	var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
	var from: Vector2 = origin_local(f, foot.y)
	var tip := head(f, t)
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	for n in range(12):
		var u := n / 11.0
		points.append(from.lerp(tip, u) + Vector2(0.0, -sin(u * PI) * 3.0))
		widths.append(lerpf(4.0, 13.0, u) * (1.0 - 0.6 * smoothstep(0.85, 1.0, u)))
		alphas.append(fade * on * smoothstep(0.0, 0.35, u))
	vfx.flame(canvas, layer, points, widths, alphas, awake, f.attack_instance)
	vfx.needle(canvas, layer, foot + Vector2(-20.0, 2.0), tip + Vector2(6.0, 0.0), 3.0, fade * on * 0.8, awake)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	if burst.kind == "scorch":
		vfx.scorch(canvas, layer, float(burst.from), float(burst.to), 1.0 - smoothstep(0.6, 1.0, k), int(burst.seed), 0.6 * (1.0 - smoothstep(0.0, 0.5, k)),
			burst.get("awake", false))
