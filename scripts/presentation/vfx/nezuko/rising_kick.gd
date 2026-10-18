extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 升空踢 (623A/C), after 飞扑踢 (held): after the blood gathers, a white
## whirl and dust at her feet as she springs, and the rising kick drags a long
## band of pink fire from low in front up over her head, a burst at its crest;
## the band stays where it was torn once the kick is spent.

## The rising foot arc round her hip, fighter-local: on the v3 rising_kick frames the
## foot climbs almost straight up to about (17, -67); on the kept demon-form drawing
## from about (46, -63) to (31, -71).
func arc(f: RefCounted, move: Resource) -> Paths.Arc:
	var big := heavy(move)
	var size: float = vfx.drawn(f)
	var centre: Vector2 = fit(f, Vector2(8.0, -30.0), Vector2(6.0, -36.0))
	var path := Paths.Arc.new(centre, 0.9, -1.45, 40.0 * size, (46.0 if big else 42.0) * size, (20.0 if big else 16.0) * size)
	path.profile = "crescent"
	return path

func head(t: float, move: Resource) -> float:
	return clampf((t - move.startup + 1.0) / (move.active * 0.5 + 0.5), 0.0, 1.0)

func tail(t: float, move: Resource) -> float:
	return clampf((t - move.startup - move.active * 0.5) / (move.active * 0.5 + 8.0), 0.0, 1.25)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 131 + f.slot * 7919 + tick * 19
	emit_activation(f, tick, awake)
	anchor(f, tick)
	if tick == move.startup:
		var place := frame(f, float(tick))
		var feet: Vector2 = vfx.world(place, Vector2(10.0 * vfx.drawn(f), 0.0))
		vfx.dust_burst(feet, 5, Vector2(0.0, -0.3), seed, 1.0)
		vfx.ember_burst(feet + Vector2(0.0, -8.0), 12, Vector2(0.3 * float(f.facing), -1.0), 90.0, 230.0, seed + 1, awake)
	if tick >= move.startup and tick < move.startup + move.active:
		var place := frame(f, float(tick))
		var u := head(float(tick), move)
		vfx.flake_burst(vfx.world(place, arc(f, move).point(u, 0.0)), 2, 40.0, seed + 2, awake, 25.0)
		if tick == move.startup + int(move.active * 0.5):
			vfx.bursts.append({"kind": "blaze", "at": vfx.world(place, arc(f, move).point(1.0, 0.0)), "age": 0.0, "life": 0.2, "size": 14.0 if heavy(move) else 11.0,
				"facing": float(f.facing), "seed": seed + 3, "awake": awake})

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.15 if heavy(move) else 1.0, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var gather := activation_strength(t)
	if gather > 0.0:
		vfx.activation(canvas, layer, f, actor, gather, f.attack_instance * 13, awake)
	var lead := head(t, move)
	var erosion := tail(t, move)
	if lead <= 0.0 or erosion >= 1.0:
		return
	var place := frame(f, t)
	vfx.set_base(canvas, vfx.frame_transform(place.x, place.y, place.facing))
	var path := arc(f, move)
	vfx.flame_along(canvas, layer, path, lead, erosion, 1.0, awake, 1.8, f.attack_instance, 22)
	vfx.crescent(canvas, layer, path, lead, clampf(erosion + 0.2, 0.0, 1.0), 0.7, awake, 24)
	if t < float(move.startup) + 3.0:
		vfx.vortex(canvas, layer, Vector2(10.0, -4.0) * vfx.drawn(f), 16.0 * vfx.drawn(f), t * 0.8, 1.0 - clampf((t - move.startup) / 3.0, 0.0, 1.0), awake)
