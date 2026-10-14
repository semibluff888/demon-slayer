extends "res://scripts/presentation/vfx/zenitsu/technique.gd"
## 居合·上撩 (623A/C) and 雷之呼吸·伍之型 热界雷 (6C): a gold crescent sweeping from
## low in front up over his head, and a branching bolt shooting up from the
## floor through it; 热界雷 glows orange like heat lightning. 上撩 lifts Zenitsu
## off the floor, so its crescent stays where it was cut.

func heat(move: Resource) -> bool:
	return move.id == "zenitsu_6C"

func arc(move: Resource) -> Paths.Arc:
	var big := heavy(move) and not heat(move)
	var path := Paths.Arc.new(Vector2(8.0, -46.0), 1.05, -1.95, 40.0, 54.0 if big else 48.0, 15.0 if big else 12.0)
	path.profile = "crescent"
	return path

func head(t: float, move: Resource) -> float:
	return clampf((t - move.startup + 1.0) / (move.active * 0.5 + 0.5), 0.0, 1.0)

func tail(t: float, move: Resource) -> float:
	return clampf((t - move.startup - move.active * 0.6) / (move.active * 0.4 + 7.0), 0.0, 1.25)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 131 + f.slot * 7919 + tick * 19
	anchor(f, tick)
	if tick == move.startup:
		var place := frame(f, float(tick))
		var feet: Vector2 = vfx.world(place, Vector2(18.0, -2.0))
		vfx.spark_burst(feet, 16, Vector2(0.3, -1.0), 90.0, 240.0, seed, Kit.HEAT if heat(move) else Kit.GOLD_HOT)
		vfx.debris_burst(feet, 4, Vector2(0.2, -0.3), seed + 1)
	if tick >= move.startup and tick < move.startup + move.active:
		var place := frame(f, float(tick))
		var path := arc(move)
		var u := head(float(tick), move)
		vfx.mote_burst(vfx.world(place, path.point(u, 0.0)), 2, 40.0, seed + 2, awake)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	if t < start and layer == Kit.LIGHT:
		vfx.body_flash(canvas, f, actor, Color(Kit.HEAT if heat(move) else Kit.GOLD, 0.4 * clampf(t / maxf(start, 1.0), 0.0, 1.0)))
	var lead := head(t, move)
	var erosion := tail(t, move)
	if lead <= 0.0 or erosion >= 1.0:
		return
	var place := frame(f, t)
	vfx.set_base(canvas, vfx.frame_transform(place.x, place.y, place.facing))
	var seed: int = f.attack_instance * 41 + f.move_frame
	var path := arc(move)
	vfx.crescent(canvas, layer, path, lead, erosion, "heat" if heat(move) else "gold", awake, seed)
	# The bolt climbs from the floor through the cut while it is being drawn.
	var strike := 1.0 - clampf((t - start - move.active * 0.6) / 6.0, 0.0, 1.0)
	if strike > 0.0:
		var top: Vector2 = path.point(lead, 0.0) + Vector2(0.0, -16.0)
		var trunk := Bolt.path(Vector2(24.0, 0.0), top, seed, 0.16, 4)
		vfx.bolt(canvas, layer, trunk, 2.4, awake, strike)
		for branch in Bolt.forks(trunk, seed + 5, 3, 26.0):
			vfx.bolt(canvas, layer, branch, 1.3, awake, strike * 0.8)
