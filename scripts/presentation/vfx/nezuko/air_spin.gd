extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 回旋踢·空 (j.214B/D), after 乱裂 (air): each spinning kick tears a huge
## crescent of pink fire round her whole body (it reaches behind her too, as the
## kick does), with a thin white ring of air; each hit bursts; she lands in a
## ring of dust.

## The body centre the crescents turn round, and their radius (fighter-local): the
## v3 air_spin kicks reach (27, -40) and (33, -47); DEMON_ on the kept demon-form
## drawing (spinning_kick).
const CENTRE := Vector2(2, -38)
const RADIUS := 34.0
const DEMON_CENTRE := Vector2(2, -36)
const DEMON_RADIUS := 40.0

var _landed: Dictionary = {}

func reset() -> void:
	super()
	_landed.clear()

## The crescents' radius: at least the fitted one, and wide enough that their front reaches
## the hit box's (which also covers her back, as the crescents do).
func spin_radius(f: RefCounted, move: Resource) -> float:
	var centre: Vector2 = fit(f, CENTRE, DEMON_CENTRE)
	return maxf(fit(f, RADIUS, DEMON_RADIUS), (box_front(move, 0.95) - centre.x) / 1.08)

func crescent_path(f: RefCounted, index: int, move: Resource) -> Paths.Arc:
	# The first sweeps up the front and over, the second back down through her.
	var a0 := 1.9 if index == 0 else -1.2
	var a1 := -1.5 if index == 0 else 2.3
	var big := heavy(move)
	var centre: Vector2 = fit(f, CENTRE, DEMON_CENTRE)
	var radius: float = spin_radius(f, move)
	var path := Paths.Arc.new(centre, a0, a1, radius * (1.05 if big else 1.0), radius * (1.15 if big else 1.08), 20.0 if big else 16.0)
	path.squash = 0.85
	path.profile = "crescent"
	return path

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 241 + f.slot * 7919 + tick * 23
	emit_activation(f, tick, awake, Vector2(0.0, -34.0))
	var list := starts(move)
	for index in range(list.size()):
		var since := tick - int(list[index])
		if since >= 0 and since < 4:
			var u := clampf((since + 1.0) / 4.0, 0.0, 1.0)
			vfx.ember_burst(vfx.world(f, crescent_path(f, index, move).point(u, 0.0)), 4, Vector2.ZERO, 70.0, 180.0, seed + index, awake)
			vfx.flake_burst(vfx.world(f, crescent_path(f, index, move).point(u, 0.0)), 1, 40.0, seed + 5 + index, awake, 10.0)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.1 if last else 0.7, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var gather := activation_strength(t)
	if gather > 0.0:
		vfx.activation(canvas, layer, f, actor, gather * 0.8, f.attack_instance * 17, awake, Vector2(0.0, -34.0))
	var list := starts(move)
	for index in range(list.size()):
		var since := t - float(list[index])
		var lead := clampf((since + 1.5) / 3.5, 0.0, 1.0)
		var erosion := clampf((since - 1.0) / 6.0, 0.0, 1.25)
		if lead <= 0.0 or erosion >= 1.0:
			continue
		var path := crescent_path(f, index, move)
		vfx.flame_along(canvas, layer, path, lead, erosion, 1.0, awake, 1.8, f.attack_instance + index, 22)
		var radius: float = spin_radius(f, move)
		var ring := Paths.Arc.new(path.pivot, path.a0, path.a1, radius * 1.3, radius * 1.35, 4.0)
		ring.squash = 0.85
		ring.profile = "crescent"
		vfx.crescent(canvas, layer, ring, lead, clampf(erosion + 0.1, 0.0, 1.0), 0.6, awake, 20)

func linger(fighters: Array, actors: Array) -> void:
	for f in fighters:
		if f.move != null or not f.grounded or not str(f.landing_move) in ["nezuko_j214B", "nezuko_j214D"]:
			continue
		if int(_landed.get(f.slot, -1)) == f.attack_instance:
			continue
		_landed[f.slot] = f.attack_instance
		var awake: bool = f.slot < actors.size() and actors[f.slot] != null and actors[f.slot].form_active()
		var seed: int = f.attack_instance * 257 + 7
		var feet := Vector2(f.x, f.y)
		vfx.dust_burst(feet, 6, Vector2.ZERO, seed, 1.0)
		vfx.bursts.append({"kind": "ring", "at": feet + Vector2(0.0, -2.0), "age": 0.0, "life": 0.24, "size": 26.0, "squash": 0.45, "facing": float(f.facing),
			"seed": seed + 1, "awake": awake})
		vfx.ember_burst(feet, 8, Vector2(0.0, -0.6), 60.0, 150.0, seed + 2, awake)
