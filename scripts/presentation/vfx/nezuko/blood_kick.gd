extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 爆血飞踢 (236A/C), after 飞扑踢: blood gathers in a ring of black-red
## ink, then she flies feet first in a comet of pink fire whose head runs ahead
## of her foot (the effect leads the body), a white whirl of air round the foot
## and embers shed along the way; a hit bursts with the yellow-white cross.

## The kicking foot on the drawn blood_kick active frames, how far past the
## front of the hit box the fire's head runs, and the flight height (fighter-local);
## the v3 drawing kicks lower and shorter than the kept demon-form one (DEMON_).
const FOOT := Vector2(34, -28)
const DEMON_FOOT := Vector2(48, -38)
const LEAD := 6.0
const HEIGHT := -28.0
const DEMON_HEIGHT := -34.0

## The comet's head at move time `t`: it shoots out from the foot to just past the
## front of the hit box in the first frames of the flight.
func head(f: RefCounted, t: float) -> Vector2:
	var move: Resource = f.move
	var out := 1.0 - pow(1.0 - clampf((t - float(move.startup) + 1.0) / 2.0, 0.0, 1.0), 2.0)
	var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
	return Vector2(lerpf(foot.x, move.box.end.x / vfx.body_scale() + LEAD, out), fit(f, HEIGHT, DEMON_HEIGHT))

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 223 + f.slot * 7919 + tick * 53
	emit_activation(f, tick, awake)
	mark_origin(f, tick, move.startup)
	if tick == move.startup:
		vfx.dust_burst(vfx.world(f, Vector2(-6.0, 0.0)), 5, Vector2(-0.8, 0.0), seed, 1.1)
	if tick >= move.startup and tick < move.startup + move.active:
		var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
		vfx.ember_burst(vfx.world(f, foot), 3, Vector2(-1.0, 0.0), 40.0, 140.0, seed + 1, awake)
		if tick % 2 == 0:
			vfx.flake_burst(vfx.world(f, foot + Vector2(-16.0, 0.0)), 1, 30.0, seed + 2, awake, 10.0)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.15 if heavy(move) else 1.0, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var gather := activation_strength(t)
	if gather > 0.0:
		vfx.activation(canvas, layer, f, actor, gather, f.attack_instance * 11, awake)
	var since := t - float(move.startup)
	var fade := 1.0 - clampf((since - move.active) / 6.0, 0.0, 1.0)
	if since < -1.0 or fade <= 0.0:
		return
	var tip := head(f, t)
	var foot: Vector2 = fit(f, FOOT, DEMON_FOOT)
	var from: Vector2 = origin_local(f, fit(f, HEIGHT, DEMON_HEIGHT))
	from.x = minf(from.x, tip.x - 40.0)
	var thick := 32.0 if heavy(move) else 26.0
	# The comet: a broad body of fire with two thinner tongues streaming above and below.
	for strand in range(3):
		var offset := 0.0 if strand == 0 else (-9.0 if strand == 1 else 8.0)
		var size := 1.0 if strand == 0 else 0.45
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		var alphas := PackedFloat32Array()
		var root := from + Vector2(16.0 * strand, offset)
		for n in range(14):
			var u := n / 13.0
			points.append(root.lerp(tip + Vector2(-6.0 * strand, offset * 0.3), u) + Vector2(0.0, sin(u * PI * 2.0 + since + strand) * 2.0 * (1.0 - u)))
			widths.append(thick * size * lerpf(0.3, 1.0, pow(u, 0.6)) * (1.0 - 0.6 * smoothstep(0.9, 1.0, u)))
			alphas.append(fade * smoothstep(0.0, 0.3, u) * (1.0 if strand == 0 else 0.8))
		vfx.flame(canvas, layer, points, widths, alphas, awake, f.attack_instance + strand)
	vfx.vortex(canvas, layer, foot + Vector2(-4.0, 0.0), 13.0, since * 0.9, fade * 0.9, awake)
	vfx.needle(canvas, layer, foot + Vector2(-34.0, -10.0), tip + Vector2(8.0, -4.0), 3.0, fade * 0.7, awake)
	if layer == Kit.LIGHT and vfx.glow != null:
		canvas.draw_texture_rect(vfx.glow, Rect2(tip - Vector2.ONE * 14.0, Vector2.ONE * 28.0), false, Color(Kit.WHITE, 0.45 * fade))
