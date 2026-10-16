extends "res://scripts/presentation/vfx/akaza/technique.gd"
## 破坏杀·灭式 (super): through the super freeze, after the red start-up, a
## blue-white burst swells at his fist inside two big turning crescents and the
## floor cracks under his feet; then the punch tears a horizontal blast of
## white and cyan along the floor, its shock head far out in front of him,
## smoke ripped up beneath it and a furrow left behind. The super draws its
## own charge, so SuperView skips the shared energy sphere.

## The guarding fist the charge gathers at, and the blast height at the extended
## fist (drawn annihilation frames, v3 art).
const FIST := Vector2(28.0, -38.0)
const PUNCH := Vector2(37.0, -32.0)
const HEIGHT := -34.0
## How far past the front of the hit box the blast's head reaches (local units).
const LEAD := 24.0
const TRENCH := 1.6

## The blast at move time `t`: {"from", "head", "alpha", "width"}, fighter-local.
func shape(f: RefCounted, t: float) -> Dictionary:
	var move: Resource = f.move
	var box: Rect2 = move.box
	var since := t - float(move.startup)
	var out := 1.0 - pow(1.0 - clampf((since + 1.0) / 2.0, 0.0, 1.0), 2.0)
	var head := Vector2(lerpf(PUNCH.x + 6.0, box.end.x + LEAD, out), HEIGHT)
	var erosion := clampf((since - move.active + 2.0) / 10.0, 0.0, 1.0)
	return {"from": PUNCH.lerp(head, erosion), "head": head, "alpha": 1.0 - smoothstep(0.7, 1.0, erosion), "width": lerpf(30.0, 14.0, erosion)}

func emit(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var seed: int = f.attack_instance * 257 + f.slot * 7919 + tick * 29
	emit_activation(f, tick)
	if tick < move.startup:
		if tick % 2 == 0:
			vfx.flake_burst(vfx.world(f, FIST), 2, 30.0, seed, awake, 10.0)
		return
	if tick >= move.startup + move.active:
		return
	var blast := shape(f, float(tick))
	var head: Vector2 = blast.head
	if tick == move.startup:
		vfx.bursts.append({"kind": "trench", "technique": self, "at": vfx.world(f, Vector2.ZERO), "age": 0.0, "life": TRENCH, "size": 1.0,
			"facing": float(f.facing), "seed": seed, "from": -10.0, "to": move.box.end.x + 10.0})
		vfx.dust_burst(vfx.world(f, Vector2(-8.0, 0.0)), 6, Vector2(-0.6, 0.0) * float(f.facing), seed + 1, 1.3)
	# Smoke torn up along the floor under the blast.
	var x := lerpf(0.0, head.x, vfx.rand(seed, 2))
	vfx.dust_burst(vfx.world(f, Vector2(x, 0.0)), 2, Vector2(0.8 * float(f.facing), 0.0), seed + 4, 1.2)
	vfx.spark_burst(vfx.world(f, head), 6, Vector2(float(f.facing), 0.0), 90.0, 240.0, seed + 5)

func contact(event: Dictionary, move: Resource, attacker: RefCounted, awakened: bool) -> void:
	vfx.strike(event, attacker, 1.6, awakened, true)
	if event.type == "hit":
		vfx.bursts.append({"kind": "ring", "at": event.position, "age": 0.0, "life": 0.3, "size": 46.0, "squash": 0.95, "facing": float(attacker.facing),
			"seed": attacker.attack_instance * 3 + 9, "awake": awakened})

func draw(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var awake: bool = actor.form_active()
	var t := clock(f)
	var start := float(move.startup)
	var seed: int = f.attack_instance * 67 + f.move_frame
	var age := charge_age(f)
	var red := activation_strength(age)
	if red > 0.0:
		vfx.activation(canvas, layer, f, actor, red, f.attack_instance * 19)
	if t < start + 1.0:
		var k := clampf(age / float(move.freeze_frames + move.startup), 0.0, 1.0)
		vfx.shock(canvas, layer, FIST, lerpf(6.0, 20.0, k), f.attack_instance * 67, k, awake)
		for n in range(2):
			var a0 := age * (0.35 if n == 0 else -0.28) + n * PI
			var path := Paths.Arc.new(FIST, a0, a0 + 2.4, 28.0 + 10.0 * n, 34.0 + 10.0 * n, 10.0)
			path.profile = "crescent"
			vfx.crescent(canvas, layer, path, 1.0, 0.0, k * 0.9, awake, 20)
		if layer == Kit.FLOOR:
			for n in range(6):
				var a: float = TAU * (n + vfx.rand(f.attack_instance, n) * 0.5) / 6.0
				var reach := lerpf(10.0, 34.0, k) * lerpf(0.7, 1.0, vfx.rand(f.attack_instance, n + 10))
				canvas.draw_line(Vector2(cos(a) * 4.0, sin(a) * 1.0), Vector2(cos(a) * reach, sin(a) * reach * Kit.FLOOR_SQUASH), Color(Kit.CRATER, 0.7 * k), 1.1, true)
		if layer == Kit.LIGHT:
			vfx.body_flash(canvas, f, actor, Color(Kit.tone(awake), 0.3 * k))
		if t < start:
			return
	var blast := shape(f, t)
	var from: Vector2 = blast.from
	var head: Vector2 = blast.head
	var alpha: float = blast.alpha
	var width: float = blast.width
	if alpha <= 0.01:
		return
	tear(canvas, layer, from, head, width, alpha, awake, seed)
	vfx.shock(canvas, layer, head, width * 0.75, f.attack_instance * 67 + 1, alpha, awake)

## The blast body: a wavering band (deep edge, coloured body, white core) with
## streaks of air spiralling along it.
func tear(canvas: Node2D, layer: int, from: Vector2, head: Vector2, width: float, alpha: float, awake: bool, seed: int) -> void:
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(14):
		var u := n / 13.0
		points.append(from.lerp(head, u) + Vector2(0.0, (vfx.rand(seed, n) - 0.5) * 4.0))
		widths.append(width * lerpf(0.35, 1.0, pow(u, 0.5)) * lerpf(0.85, 1.1, vfx.rand(seed, n + 20)))
		tint.append(Color(1, 1, 1, alpha * smoothstep(0.0, 0.2, u)))
	match layer:
		Kit.GLOW:
			Ribbon.draw(canvas, points, vfx._scaled(widths, 2.0), vfx._tinted(tint, Color(Kit.deep(awake), 0.45)), vfx.band)
		Kit.FRONT:
			Ribbon.draw(canvas, points, widths, vfx._tinted(tint, Color(Kit.tone(awake), 0.9)), vfx.band)
			Ribbon.draw(canvas, points, vfx._scaled(widths, 0.42), vfx._tinted(tint, Kit.WHITE), vfx.band)
		Kit.LIGHT:
			Ribbon.draw(canvas, points, vfx._scaled(widths, 1.3), vfx._tinted(tint, Color(Kit.ICE, 0.45)), vfx.band)
			for k in range(5):
				var y: float = (vfx.rand(seed, k + 40) - 0.5) * width * 0.9
				var x0 := lerpf(from.x, head.x, vfx.rand(seed, k + 50) * 0.6)
				Ribbon.draw(canvas, PackedVector2Array([Vector2(x0, from.y + y), Vector2(lerpf(x0, head.x, 0.6), from.y + y * 0.6)]), PackedFloat32Array([0.0, 1.4]),
					PackedColorArray([Color(Kit.WHITE, 0.0), Color(Kit.WHITE, 0.7 * alpha)]), vfx.band)

func draw_burst(canvas: Node2D, layer: int, burst: Dictionary, k: float) -> void:
	if burst.kind == "trench" and layer == Kit.FLOOR:
		vfx.trench(canvas, float(burst.from), float(burst.to), 1.0 - smoothstep(0.6, 1.0, k), int(burst.seed))
