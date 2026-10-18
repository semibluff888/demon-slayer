extends "res://scripts/presentation/vfx/nezuko/technique.gd"
## The throw (抓技): her clawed hand closes in a splash of black-red ink, and
## where the victim is slammed into the floor the ground breaks: a blood-flame
## burst, slabs of stone tipping up, rock and dust flying, a crater.

## The grabbing hand, fighter-local: on the v3 throw_forward grab (frame 0) and on
## the kept demon-form drawing's (frames 1-2, DEMON_HAND).
const HAND := Vector2(22, -41)
const DEMON_HAND := Vector2(33, -56)
const ERUPTION := 0.5
const CRATER := 1.2

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var since := clock(f) - float(move.startup)
	if since < -1.0 or since > move.active + 5.0:
		return
	var k := clampf((since + 1.0) / 5.0, 0.0, 1.0)
	var awake: bool = actor.form_active()
	var hand: Vector2 = fit(f, HAND, DEMON_HAND)
	var size: float = vfx.drawn(f)
	vfx.ring(canvas, layer, hand, Vector2(lerpf(3.0, 7.0, k), lerpf(8.0, 15.0, k)) * size, 0.0, 1.0 - k, 1.8, awake)
	if layer == Kit.FRONT:
		for n in range(9):
			var a: float = TAU * (n + vfx.rand(f.attack_instance, n) * 0.6) / 9.0
			var direction := Vector2.from_angle(a)
			var from := hand + direction * 5.0 * size
			var to := hand + direction * lerpf(12.0, 22.0, vfx.rand(f.attack_instance, n + 20)) * (0.6 + 0.4 * k) * size
			var side := direction.orthogonal() * 1.8
			canvas.draw_colored_polygon(PackedVector2Array([from - side, to, from + side]), Color(Kit.INK, 0.75 * (1.0 - k)))

## The victim hits the floor (the combat "throw" event, at the impact tick).
func slam(event: Dictionary, thrower: RefCounted, awakened: bool) -> void:
	var at: Vector2 = event.position
	var floor_at := Vector2(at.x, Arena.FLOOR_Y)
	var facing := float(thrower.facing)
	var seed: int = thrower.attack_instance * 277 + thrower.slot * 13
	vfx.bursts.append({"kind": "blaze", "at": at + Vector2(0.0, -6.0), "age": 0.0, "life": 0.22, "size": 20.0, "facing": facing, "seed": seed, "awake": awakened})
	vfx.bursts.append({"kind": "ring", "at": floor_at + Vector2(0.0, -2.0), "age": 0.0, "life": 0.26, "size": 30.0, "squash": 0.5, "facing": facing, "seed": seed + 1,
		"awake": awakened})
	vfx.bursts.append({"kind": "eruption", "technique": self, "at": floor_at, "age": 0.0, "life": ERUPTION, "size": 24.0, "facing": facing, "seed": seed + 2, "awake": awakened})
	vfx.bursts.append({"kind": "crater", "technique": self, "at": floor_at, "age": 0.0, "life": CRATER, "size": 20.0, "facing": 1.0, "seed": seed + 3, "awake": awakened})
	vfx.debris_burst(floor_at, 7, Vector2(0.0, -0.3), seed + 4, false, 1.2)
	vfx.dust_burst(floor_at, 7, Vector2.ZERO, seed + 5, 1.2)
	vfx.ember_burst(at, 14, Vector2(0.0, -0.6), 90.0, 230.0, seed + 6, awakened)
	vfx.flake_burst(at, 6, 80.0, seed + 7, awakened)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	var awake: bool = burst.get("awake", false)
	match burst.kind:
		"eruption":
			var rise := 1.0 - pow(1.0 - clampf(k / 0.14, 0.0, 1.0), 3.0)
			vfx.rubble(canvas, layer, Vector2.ZERO, float(burst.size), rise * (1.0 - smoothstep(0.55, 1.0, k)), int(burst.seed), awake, 7)
		"crater":
			vfx.crater(canvas, layer, Vector2.ZERO, float(burst.size), 1.0 - smoothstep(0.6, 1.0, k), int(burst.seed), 0.0, awake)
