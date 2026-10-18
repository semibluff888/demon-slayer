extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## 爆血·觉醒连击 (MAX), after 爆血踵落: through the freeze the demon blood
## gathers in a great ring of ink and a pillar of fire stands round her; two
## burning kicks; then the heel comes down on her target and the floor erupts: a
## white spiked flash, a dome of pink fire like an onion with white-hot cracks
## running up it, rock flying and a crater left glowing. The MAX draws its own
## charge, so SuperView skips the shared energy sphere.

## Kick crescents for the first two hits, and the heel's path down onto the
## target for the last (awakened_combo frames put the foot near (49, -50)).
const KICKS := [
	[Vector2(-4, -10), Vector2(16, -64), Vector2(48, -52)],
	[Vector2(-6, -8), Vector2(24, -42), Vector2(48, -44)],
]
const HEEL := [Vector2(0, -86), Vector2(48, -104), Vector2(50, -14)]
## The dome erupts on the heel-drop impact and burns out as she recovers (user review,
## 2026-10-18: it used to grow for 0.2 s after the hit and burn on long after the move).
const DOME := 0.8
const ERUPTION := 0.6
const CRATER := 1.8

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 269 + f.slot * 7919 + tick * 31
	emit_activation(f, tick, awake)
	if tick < move.startup:
		if tick % 2 == 0:
			vfx.flake_burst(vfx.world(f, Vector2(0.0, -40.0)), 2, 60.0, seed, awake, 40.0)
		return
	var list := starts(move)
	if tick in list:
		var index := list.find(tick)
		var tip: Vector2 = vfx.world(f, HEEL[2] if index == list.size() - 1 else Vector2(reaching(move, KICKS[mini(index, 1)], 0.8)[2]))
		vfx.ember_burst(tip, 12, Vector2(float(f.facing), -0.3), 80.0, 220.0, seed + index, awake)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	var last: bool = int(event.get("segment", 0)) >= move.hit_count() - 1
	vfx.strike(event, attacker, 1.6 if last else 0.9, awakened, last)
	if not last or event.type != "hit":
		return
	var seed: int = attacker.attack_instance * 271 + 5
	var at := Vector2(float(event.position.x), Arena.FLOOR_Y)
	var facing := float(attacker.facing)
	vfx.bursts.append({"kind": "star", "at": event.position, "age": 0.0, "life": 0.24, "size": 40.0, "facing": facing, "seed": seed})
	vfx.bursts.append({"kind": "dome", "technique": self, "at": at, "age": 0.0, "life": DOME, "size": 1.0, "facing": facing, "seed": seed + 1, "awake": awakened})
	vfx.bursts.append({"kind": "eruption", "technique": self, "at": at, "age": 0.0, "life": ERUPTION, "size": 34.0, "facing": facing, "seed": seed + 2, "awake": awakened})
	vfx.bursts.append({"kind": "crater", "technique": self, "at": at, "age": 0.0, "life": CRATER, "size": 30.0, "facing": 1.0, "seed": seed + 3, "awake": awakened})
	vfx.debris_burst(at, 10, Vector2(0.0, -0.4), seed + 4, true, 1.4)
	vfx.flake_burst(at + Vector2(0.0, -40.0), 16, 140.0, seed + 5, awakened, 90.0)
	vfx.dust_burst(at, 8, Vector2.ZERO, seed + 6, 1.5)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var age := charge_age(f)
	if t < start + 1.0:
		var k := clampf(age / float(move.freeze_frames + move.startup), 0.0, 1.0)
		vfx.activation(canvas, layer, f, actor, minf(1.0, 0.5 + k), f.attack_instance * 23, awake)
		vfx.pillar(canvas, layer, Vector2.ZERO, lerpf(40.0, 120.0, k), 34.0, 0.75 * k, awake, f.attack_instance, age / 60.0)
		if t < start:
			return
	var list := starts(move)
	for index in range(list.size()):
		var since := t - float(list[index])
		var head := clampf((since + 1.0) / 2.2, 0.0, 1.0)
		var tail := clampf((since - 1.0) / 6.0, 0.0, 1.25)
		if head <= 0.0 or tail >= 1.0:
			continue
		var last := index == list.size() - 1
		var keys: Array = HEEL if last else reaching(move, KICKS[mini(index, 1)], 0.8)
		var curve := Paths.Sweep.new(keys[0], keys[1], keys[2], 20.0 if last else 14.0)
		vfx.flame_along(canvas, layer, curve, head, tail, 1.0, awake, 1.8 if last else 1.3, f.attack_instance + index)
		vfx.crescent(canvas, layer, curve, head, clampf(tail + 0.15, 0.0, 1.0), 0.8, awake)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	var awake: bool = burst.get("awake", false)
	var seed: int = burst.seed
	match burst.kind:
		"dome":
			# Its clock starts a little in, so the tongues are half out while the hit stops.
			var grow := 1.0 - pow(1.0 - clampf((k + 0.1) / 0.2, 0.0, 1.0), 3.0)
			var fade := 1.0 - smoothstep(0.75, 1.0, k)
			vfx.dome(canvas, layer, Vector2.ZERO, 62.0 * (0.7 + 0.3 * grow), fade, awake, seed, 0.1 + k * 0.9)
			if layer == Kit.LIGHT and k < 0.3:
				vfx.rays(canvas, Vector2(0.0, -30.0), seed + 7, 14, 170.0, 1.0 - k / 0.3, Kit.tone(awake), 2.2, -PI * 0.5)
		"eruption":
			var rise := 1.0 - pow(1.0 - clampf(k / 0.14, 0.0, 1.0), 3.0)
			var sink := 1.0 - smoothstep(0.55, 1.0, k)
			vfx.rubble(canvas, layer, Vector2.ZERO, float(burst.size), rise * sink, seed, awake, 9)
		"crater":
			vfx.crater(canvas, layer, Vector2.ZERO, float(burst.size), 1.0 - smoothstep(0.65, 1.0, k), seed, 1.0 - smoothstep(0.1, 0.7, k), awake)
