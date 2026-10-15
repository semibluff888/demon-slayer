extends "res://scripts/presentation/vfx/akaza/technique.gd"
## The throw: the reaching hand snaps a small ring of air, and where the victim
## is slammed into the floor a shock bursts with a dome of air, rock, dust and
## a crater.

## The grabbing hand on the drawn throw frames (roster-v1 art).
const HAND := Vector2(36.0, -56.0)
const CRATER := 1.2

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var since := clock(f) - float(move.startup)
	if since < -1.0 or since > move.active + 4.0:
		return
	var k := clampf((since + 1.0) / 4.0, 0.0, 1.0)
	vfx.ring(canvas, layer, HAND, Vector2(lerpf(3.0, 7.0, k), lerpf(8.0, 15.0, k)), 0.0, 1.0 - k, 1.8, actor.form_active())

## The victim hits the floor (the combat "throw" event, at the impact tick).
func slam(event: Dictionary, thrower: RefCounted, awakened: bool) -> void:
	var at: Vector2 = event.position
	var floor_at := Vector2(at.x, Arena.FLOOR_Y)
	var facing := float(thrower.facing)
	var seed: int = thrower.attack_instance * 271 + thrower.slot * 13
	vfx.bursts.append({"kind": "shock", "at": at + Vector2(0.0, -6.0), "age": 0.0, "life": 0.18, "size": 22.0, "facing": facing, "seed": seed, "awake": awakened})
	vfx.bursts.append({"kind": "ring", "at": floor_at + Vector2(0.0, -2.0), "age": 0.0, "life": 0.26, "size": 30.0, "squash": 0.5, "facing": facing, "seed": seed + 1,
		"awake": awakened})
	vfx.bursts.append({"kind": "crater", "technique": self, "at": floor_at, "age": 0.0, "life": CRATER, "size": 20.0, "facing": 1.0, "seed": seed + 2})
	vfx.debris_burst(floor_at, 6, Vector2(facing * 0.2, 0.0), seed + 3)
	vfx.dust_burst(floor_at, 7, Vector2.ZERO, seed + 4, 1.2)
	vfx.spark_burst(at, 14, Vector2(0.0, -0.6), 90.0, 230.0, seed + 5)
	vfx.flake_burst(at, 5, 70.0, seed + 6, awakened)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	if burst.kind == "crater" and layer == Kit.FLOOR:
		vfx.crater(canvas, Vector2.ZERO, float(burst.size), 1.0 - smoothstep(0.6, 1.0, k), int(burst.seed))
