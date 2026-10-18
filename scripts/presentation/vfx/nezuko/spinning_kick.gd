extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 回旋踢 (214B/D), after the reference's roundhouse: each spinning kick sweeps a wave of pink blood
## fire round her from behind to the front at waist height, inside a white arc of
## air, the second the larger; embers fly off the wave's edge.

## The sweep round her body: centre and radii (seen from the side, flattened) at
## the kicking foot's height: the v3 spinning_kick frames put the foot near (29, -42)
## and (28, -51), the kept demon-form drawing near (47, -52) (DEMON_).
const CENTRE := Vector2(3, -44)
const RADII := Vector2(31, 11)
const DEMON_CENTRE := Vector2(4, -46)
const DEMON_RADII := Vector2(46, 15)

func wave(f: RefCounted, index: int, move: Resource) -> Paths.Arc:
	var big := heavy(move) or index > 0
	var centre: Vector2 = fit(f, CENTRE, DEMON_CENTRE)
	var radii: Vector2 = fit(f, RADII, DEMON_RADII)
	# The wave opens out as it comes round the front, to the reach of the kick's hit box.
	var front: float = maxf(radii.x * (1.15 if big else 1.05), box_front(move) - centre.x)
	var path := Paths.Arc.new(centre, PI * 0.95, PI * 2.05, radii.x * (1.1 if big else 1.0), front, 18.0 if big else 14.0)
	path.squash = radii.y / radii.x
	path.tilt = -0.12
	path.profile = "crescent"
	return path

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 233 + f.slot * 7919 + tick * 59
	emit_activation(f, tick, awake)
	var list := starts(move)
	for index in range(list.size()):
		var since := tick - int(list[index])
		if since >= 0 and since < 4:
			var u := clampf((since + 1.0) / 4.0, 0.0, 1.0)
			vfx.ember_burst(vfx.world(f, wave(f, index, move).point(u, 0.0)), 4, Vector2(1.0, -0.3), 70.0, 190.0, seed + index, awake)
		if since == 0:
			vfx.dust_burst(vfx.world(f, Vector2(0.0, 0.0)), 3, Vector2.ZERO, seed + 9 + index, 0.9)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.1 if last else 0.7, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var gather := activation_strength(t)
	if gather > 0.0:
		vfx.activation(canvas, layer, f, actor, gather * 0.8, f.attack_instance * 17, awake)
	var list := starts(move)
	for index in range(list.size()):
		var since := t - float(list[index])
		var lead := clampf((since + 2.0) / 4.0, 0.0, 1.0)
		var erosion := clampf((since - 1.0) / 7.0, 0.0, 1.25)
		if lead <= 0.0 or erosion >= 1.0:
			continue
		var path := wave(f, index, move)
		vfx.flame_along(canvas, layer, path, lead, erosion, 1.0, awake, 1.7, f.attack_instance + index, 22)
		vfx.crescent(canvas, layer, path, lead, clampf(erosion + 0.15, 0.0, 1.0), 0.75, awake, 24)
