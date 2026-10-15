extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·碎式 万叶闪柳 (5A > A > C): the raised fist gathers a cold glint and comes
## down along a streak of light into the floor in front of him, which erupts:
## a crown of crystal plates breaks out of the ground round the blow with a
## burst, upward rays and a short pillar, blue and black rubble and a ring of
## dust; the plates sink back within half a second and a crater stays behind.

## Seconds the eruption stands and the crater stays.
const ERUPTION := 0.6
const CRATER := 1.5

## Where the fist meets the floor, fighter-local.
func impact(move: Resource) -> Vector2:
	var box: Rect2 = move.box
	return Vector2(box.position.x + box.size.x * 0.55, 0.0)

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	if tick != move.startup:
		return
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 229 + f.slot * 7919
	var at: Vector2 = vfx.world(f, impact(move))
	var facing := float(f.facing)
	vfx.bursts.append({"kind": "eruption", "technique": self, "at": at, "age": 0.0, "life": ERUPTION, "size": 34.0, "facing": facing, "seed": seed, "awake": awake})
	vfx.bursts.append({"kind": "crater", "technique": self, "at": at, "age": 0.0, "life": CRATER, "size": 26.0, "facing": 1.0, "seed": seed + 1})
	vfx.bursts.append({"kind": "shock", "at": at + Vector2(0.0, -10.0), "age": 0.0, "life": 0.18, "size": 24.0, "facing": facing, "seed": seed + 2, "awake": awake})
	vfx.debris_burst(at, 6, Vector2(0.0, -0.3), seed + 3, true)
	vfx.debris_burst(at, 4, Vector2(facing * 0.3, 0.0), seed + 4)
	vfx.flake_burst(at + Vector2(0.0, -12.0), 10, 90.0, seed + 5, awake, 50.0)
	vfx.dust_burst(at, 6, Vector2.ZERO, seed + 6, 1.2)
	vfx.spark_burst(at + Vector2(0.0, -6.0), 14, Vector2(0.0, -1.0), 100.0, 260.0, seed + 7)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.1, awakened, true)

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	if t >= start + 2.0:
		return
	var floor_at := impact(move)
	# The fist's glint, travelling down from overhead to the floor.
	var k := clampf((t - start + 8.0) / 8.0, 0.0, 1.0)
	var fist := Vector2(lerpf(14.0, floor_at.x, k * k), lerpf(-76.0, -6.0, k * k))
	if layer == Kit.LIGHT and vfx.glow != null and k > 0.0:
		canvas.draw_texture_rect(vfx.glow, Rect2(fist - Vector2.ONE * 11.0, Vector2.ONE * 22.0), false, Color(Kit.tone(awake), 0.8 * k))
	# The streak the blow comes down along.
	var streak := clampf((t - start + 4.0) / 3.0, 0.0, 1.0) * (1.0 - clampf((t - start) / 2.0, 0.0, 1.0))
	if streak > 0.0:
		vfx.needle(canvas, layer, Vector2(floor_at.x - 10.0, -96.0), floor_at + Vector2(0.0, -2.0), 6.0, streak, awake)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	var awake: bool = burst.get("awake", false)
	var size: float = burst.size
	match burst.kind:
		"eruption":
			var rise := 1.0 - pow(1.0 - clampf(k / 0.14, 0.0, 1.0), 3.0)
			var sink := 1.0 - smoothstep(0.55, 1.0, k)
			vfx.crystals(canvas, layer, Vector2.ZERO, size, rise * sink, int(burst.seed), awake, 9)
			var flash := 1.0 - clampf(k / 0.4, 0.0, 1.0)
			if flash > 0.0:
				if layer == Kit.LIGHT:
					vfx.rays(canvas, Vector2(0.0, -6.0), int(burst.seed) + 7, 12, size * 2.2, flash, Kit.tone(awake), 1.7, -PI * 0.5)
				# A short pillar of light where the fist went in.
				vfx.needle(canvas, layer, Vector2(0.0, 0.0), Vector2(0.0, -size * 2.4 * rise), 10.0 * flash + 2.0, flash, awake)
		"crater":
			if layer == Kit.FLOOR:
				vfx.crater(canvas, Vector2.ZERO, size, 1.0 - smoothstep(0.65, 1.0, k), int(burst.seed))
