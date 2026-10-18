extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 踵落 (6B), after 踵落: the heel goes up behind her head and comes down
## through a tall white ring of air, dragging a tongue of pink fire; a clean hit
## bursts into a white manga impact star over the blood flame.

## The heel's path from overhead down in front, fighter-local: HEEL on the v3 kakato
## frames (the heel peaks above her head, then falls through chest height to the
## floor), DEMON_HEEL on the kept demon-form drawing (body_air_heavy).
const HEEL := [Vector2(-5, -67), Vector2(30, -82), Vector2(30, -12)]
const DEMON_HEEL := [Vector2(-6, -80), Vector2(36, -98), Vector2(36, -14)]
## The centre of the tall ring of air the heel falls through.
const RING := Vector2(24, -46)
const DEMON_RING := Vector2(26, -52)

func path(f: RefCounted) -> Paths.Sweep:
	var heel: Array = fit(f, HEEL, DEMON_HEEL)
	return Paths.Sweep.new(heel[0], heel[1], heel[2], 15.0)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 197 + f.slot * 7919 + tick * 43
	if tick == move.startup - 6:
		vfx.dust_burst(vfx.world(f, Vector2(0.0, 0.0)), 4, Vector2.ZERO, seed, 0.9)
	if tick == move.startup:
		var tip: Vector2 = vfx.world(f, path(f).point(1.0, 0.0))
		vfx.ember_burst(tip, 12, Vector2(0.0, 1.0), 80.0, 200.0, seed + 1, awake)
		vfx.flake_burst(tip, 4, 60.0, seed + 2, awake, 10.0)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 0.85, awakened)
	if event.type == "hit":
		vfx.bursts.append({"kind": "star", "at": event.position, "age": 0.0, "life": 0.2, "size": 24.0, "facing": float(attacker.facing),
			"seed": attacker.attack_instance * 7 + 3})

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var since := clock(f) - float(move.startup)
	# The heel climbs (the ring opens) through the last frames of the start-up.
	var rise := clampf((since + 6.0) / 6.0, 0.0, 1.0)
	var fade := 1.0 - clampf((since - move.active) / 6.0, 0.0, 1.0)
	if rise <= 0.0 or fade <= 0.0:
		return
	var ring: Vector2 = fit(f, RING, DEMON_RING)
	vfx.ring(canvas, layer, ring, Vector2(lerpf(8.0, 14.0, rise), lerpf(30.0, 46.0, rise)) * vfx.drawn(f), 0.0, fade * 0.8 * rise, 2.4, awake)
	var head := clampf((since + 1.0) / 2.5, 0.0, 1.0)
	var tail := clampf((since - 1.0) / 6.0, 0.0, 1.25)
	vfx.crescent(canvas, layer, path(f), head, tail, 1.0, awake)
	vfx.flame_along(canvas, layer, path(f), head, clampf(tail + 0.15, 0.0, 1.0), 1.0, awake, 1.1, f.attack_instance)
