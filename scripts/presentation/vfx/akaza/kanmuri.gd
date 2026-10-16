extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·脚式·冠先割 (623A/C): after the red start-up the rising kick tears a
## tall white crescent of air from low in front up over his head, rimmed in the
## shock colour, with a burst at its crest and flakes spinning off the foot.
## The kick lifts Akaza off the floor, so the crescent stays where it was cut.

## The kick rises from low in front to straight overhead round his hip (fitted to
## the drawn crown_splitter frames, v3 art; the foot peaks near (12, -76)).
func arc(move: Resource) -> Paths.Arc:
	var big := heavy(move)
	var path := Paths.Arc.new(Vector2(4.0, -38.0), 0.85, -1.3, 40.0, 44.0 if big else 41.0, 17.0 if big else 14.0)
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
	emit_activation(f, tick)
	anchor(f, tick)
	if tick == move.startup:
		var place := frame(f, float(tick))
		var feet: Vector2 = vfx.world(place, Vector2(14.0, 0.0))
		vfx.dust_burst(feet, 5, Vector2(0.0, -0.3), seed, 1.0)
		vfx.spark_burst(feet + Vector2(0.0, -8.0), 12, Vector2(0.3 * float(f.facing), -1.0), 90.0, 230.0, seed + 1)
	if tick >= move.startup and tick < move.startup + move.active:
		var place := frame(f, float(tick))
		var path := arc(move)
		var u := head(float(tick), move)
		vfx.flake_burst(vfx.world(place, path.point(u, 0.0)), 2, 40.0, seed + 2, awake, 20.0)
		if tick == move.startup + int(move.active * 0.5):
			var crest: Vector2 = vfx.world(place, path.point(1.0, 0.0))
			vfx.bursts.append({"kind": "shock", "at": crest, "age": 0.0, "life": 0.18, "size": 14.0 if heavy(move) else 11.0, "facing": float(f.facing),
				"seed": seed + 3, "awake": awake})

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.15 if heavy(move) else 1.0, awakened)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var red := activation_strength(t)
	if red > 0.0:
		vfx.activation(canvas, layer, f, actor, red, f.attack_instance * 11)
	var lead := head(t, move)
	var erosion := tail(t, move)
	if lead <= 0.0 or erosion >= 1.0:
		return
	var place := frame(f, t)
	vfx.set_base(canvas, vfx.frame_transform(place.x, place.y, place.facing))
	vfx.crescent(canvas, layer, arc(move), lead, erosion, 1.0, awake, 28)
