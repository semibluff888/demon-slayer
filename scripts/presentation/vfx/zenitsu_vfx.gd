extends Node2D
## Zenitsu's thunder effects after the Hinokami Chronicles look: gold iai light
## with a white-hot core, cyan-white jagged lightning, thick dash beams with a
## spiky head, comic starbursts with long thin rays, gold sparks and debris.
## Each technique lives in vfx/zenitsu/; this node owns the layers, particle
## pools, contact bursts and the shared drawing helpers. Shapes follow the move
## clock; lightning is seeded per combat tick so it flickers with the game, never
## with the render rate. Particles are emitted from `consume`, which runs after
## every combat step, so each tick sees the fighter exactly where combat put it
## (dash origins and spark trails do not depend on the render rate); particles
## and bursts advance only with the presentation time EffectsView passes in, so
## hitstop, super freeze, pause and KO freezes hold the whole picture. Combat
## state is only ever read.
const Kit = preload("res://scripts/presentation/vfx/zenitsu/kit.gd")
const Bolt = preload("res://scripts/presentation/vfx/zenitsu/bolt.gd")
const Ribbon = preload("res://scripts/presentation/vfx/vfx_ribbon.gd")
const Pool = preload("res://scripts/presentation/vfx/vfx_pool.gd")
const TECHNIQUES := {
	"cut": preload("res://scripts/presentation/vfx/zenitsu/iai_cut.gd"),
	"thunderclap": preload("res://scripts/presentation/vfx/zenitsu/thunderclap.gd"),
	"rising": preload("res://scripts/presentation/vfx/zenitsu/rising_iai.gd"),
	"turn": preload("res://scripts/presentation/vfx/zenitsu/turn_slash.gd"),
	"distant": preload("res://scripts/presentation/vfx/zenitsu/distant_thunder.gd"),
	"sixfold": preload("res://scripts/presentation/vfx/zenitsu/sixfold.gd"),
	"godspeed": preload("res://scripts/presentation/vfx/zenitsu/godspeed.gd"),
}
## Moves drawn here and the technique drawing each; body normals and the throw
## keep EffectsView's shared impacts.
const MOVES := {
	"zenitsu_5A": "cut", "zenitsu_5C": "cut", "zenitsu_2A": "cut", "zenitsu_2C": "cut", "zenitsu_jA": "cut", "zenitsu_jC": "cut",
	"zenitsu_5AA": "cut", "zenitsu_5AAC": "cut",
	"zenitsu_236A": "thunderclap", "zenitsu_236C": "thunderclap", "zenitsu_3C": "thunderclap",
	"zenitsu_j236A": "thunderclap", "zenitsu_j236C": "thunderclap",
	"zenitsu_623A": "rising", "zenitsu_623C": "rising", "zenitsu_6C": "rising",
	"zenitsu_214B": "turn", "zenitsu_214D": "turn",
	"zenitsu_j214B": "distant", "zenitsu_j214D": "distant",
	"zenitsu_super": "sixfold",
	"zenitsu_max": "godspeed",
}
var combat: RefCounted
var camera: RefCounted
var actors: Array = []
var glow: Texture2D
## Authored sword-cut curves for normal attacks, by effect id (EffectsView's).
var cut_curves: Dictionary = {}
## Sub-tick reveal for smooth high refresh rates; captures and tests turn it off.
var interpolate: bool = true
var frac: float = 0.0
var time: float = 0.0
var dot: Texture2D
var chunk: Texture2D
var band: GradientTexture2D
## Gold sparks thrown off cuts and impacts.
var sparks := Pool.new(1, 1, 360)
## Cyan electric motes drifting off lightning.
var motes := Pool.new(1, 1, 200)
## Dark ground and rock chunks.
var debris := Pool.new(1, 1, 90)
var bursts: Array[Dictionary] = []
var layers: Array[Node2D] = []
var techniques: Dictionary = {}
var _ticks: Dictionary = {}
## Local-to-canvas transform of the shape being drawn.
var base := Transform2D.IDENTITY

func _ready() -> void:
	dot = _spark_texture()
	chunk = _chunk_texture()
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	falloff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	band = GradientTexture2D.new()
	band.gradient = falloff
	band.fill_from = Vector2(0, 0)
	band.fill_to = Vector2(0, 1)
	band.width = 4
	band.height = 64
	sparks.fade_in = 0.0
	sparks.fade_out = 0.35
	motes.fade_in = 0.1
	motes.fade_out = 0.5
	debris.fade_in = 0.0
	debris.fade_out = 0.3
	for spec in [["ZenitsuBack", -9, false], ["ZenitsuGlow", -1, true], ["ZenitsuFront", 0, false], ["ZenitsuLight", 0, true]]:
		layers.append(_layer(spec[0], spec[1], spec[2]))
	for key: String in TECHNIQUES:
		var technique: RefCounted = TECHNIQUES[key].new()
		technique.vfx = self
		techniques[key] = technique

## Crisp spark: white core, warm rim.
static func _spark_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length() / 14.0
			var alpha := clampf((1.0 - d) * 4.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 0.85, 0.5).lerp(Color.WHITE, clampf((0.6 - d) * 3.0, 0.0, 1.0)) * Color(1, 1, 1, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## An irregular dark rock chunk with a lighter top edge.
static func _chunk_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var corners := PackedVector2Array()
	for n in range(7):
		var a := TAU * n / 7.0
		corners.append(Vector2(16, 16) + Vector2(cos(a), sin(a)) * (9.0 + 5.0 * Bolt.rand(11, n)))
	for y in range(32):
		for x in range(32):
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(p, corners):
				var shade := 0.10 + 0.12 * clampf((20.0 - y) / 12.0, 0.0, 1.0)
				image.set_pixel(x, y, Color(shade, shade * 0.95, shade * 0.9, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _layer(id: String, z: int, additive: bool) -> Node2D:
	var node := Node2D.new()
	node.name = id
	node.z_index = z
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if additive else CanvasItemMaterial.BLEND_MODE_MIX
	node.material = blend
	node.draw.connect(_paint.bind(node, layers.size()))
	add_child(node)
	return node

func handles(move: Resource) -> bool:
	return move != null and MOVES.has(move.id)

func technique(move: Resource) -> RefCounted:
	return techniques[MOVES[move.id]]

func reset() -> void:
	for pool in [sparks, motes, debris]:
		pool.clear()
	bursts.clear()
	_ticks.clear()
	for each: RefCounted in techniques.values():
		each.reset()
	time = 0.0
	redraw()

func redraw() -> void:
	for layer in layers:
		layer.queue_redraw()

# --- Simulation -------------------------------------------------------------------

func advance(delta: float) -> void:
	time += delta
	for pool in [sparks, motes, debris]:
		pool.advance(delta)
	for burst: Dictionary in bursts:
		burst.age += delta
	bursts = bursts.filter(func(b: Dictionary) -> bool: return b.age < b.life)
	redraw()

func consume(events: Array) -> void:
	for f in combat.fighters:
		_emit_fighter(f)
	for each: RefCounted in techniques.values():
		each.linger(combat.fighters, actors)
	for event: Dictionary in events:
		if event.type == "round_end":
			break
		if event.type not in ["hit", "block"] or not event.has("attacker"):
			continue
		var move: Resource = combat.moves.get(event.get("move", ""))
		if not handles(move):
			continue
		technique(move).contact(event, move, combat.fighters[event.attacker], awakened(event.attacker))
	redraw()

func _emit_fighter(f: RefCounted) -> void:
	if not handles(f.move) or not combat.presents_attack(f.slot) or f.slot >= actors.size():
		_ticks.erase(f.slot)
		return
	var last: Array = _ticks.get(f.slot, [-1, -1])
	var from: int = int(last[1]) + 1 if int(last[0]) == f.attack_instance else 0
	var drawing: RefCounted = technique(f.move)
	for tick in range(from, f.move_frame + 1):
		drawing.emit(f, actors[f.slot], tick)
	_ticks[f.slot] = [f.attack_instance, f.move_frame]

# --- Particle bursts --------------------------------------------------------------

## Gold sparks flung from `at`; `bias` leans them one way.
func spark_burst(at: Vector2, count: int, bias: Vector2, slow: float, fast: float, seed: int, tint: Color = Kit.GOLD_HOT) -> void:
	for n in range(count):
		var direction := (Vector2.from_angle(rand(seed, n) * TAU) + bias * 0.9).normalized()
		sparks.spawn(at, direction * lerpf(slow, fast, rand(seed, n + 50)), lerpf(0.18, 0.42, rand(seed, n + 100)), lerpf(1.6, 3.2, rand(seed, n + 150)), 0, tint,
			260.0, 1.2, 0.0, 0.0, 0.6, 2.4)

## Cyan electric motes drifting up from `at`.
func mote_burst(at: Vector2, count: int, speed: float, seed: int, awakened: bool) -> void:
	for n in range(count):
		motes.spawn(at + Vector2(rand(seed, n) - 0.5, rand(seed, n + 9) - 0.5) * 20.0,
			Vector2.from_angle(rand(seed, n + 20) * TAU) * speed * lerpf(0.3, 1.0, rand(seed, n + 30)) + Vector2(0, -18.0),
			lerpf(0.3, 0.6, rand(seed, n + 40)), lerpf(1.4, 2.6, rand(seed, n + 50)), 0, Kit.bolt_tint(awakened), -20.0, 1.6)

## Dark chunks thrown up from the floor or the struck body.
func debris_burst(at: Vector2, count: int, bias: Vector2, seed: int) -> void:
	for n in range(count):
		var direction := (Vector2(rand(seed, n) * 2.0 - 1.0, -lerpf(0.5, 1.0, rand(seed, n + 10))) + bias).normalized()
		debris.spawn(at, direction * lerpf(90.0, 220.0, rand(seed, n + 20)), lerpf(0.4, 0.7, rand(seed, n + 30)), lerpf(3.0, 6.5, rand(seed, n + 40)), 0,
			Color.WHITE, 420.0, 0.4, rand(seed, n + 50) * TAU, rand(seed, n + 60) * 14.0 - 7.0)

## Thunder contact: comic starburst, gold X flash, short bolts, rays and sparks.
## Hitstop holds these on their first frame, so that frame must already read.
func strike(event: Dictionary, attacker: RefCounted, scale: float, awakened_form: bool, cross: bool) -> void:
	var at: Vector2 = event.position
	var facing := float(attacker.facing)
	var seed: int = attacker.attack_instance * 977 + int(event.get("segment", 0)) * 31 + attacker.slot * 13
	if event.type == "hit":
		bursts.append({"kind": "star", "at": at, "age": 0.0, "life": 0.16, "size": 16.0 * scale + 7.0, "facing": facing, "seed": seed,
			"fill": Kit.GOLD_HOT, "rim": Kit.EMBER})
		if cross:
			bursts.append({"kind": "cross", "at": at, "age": 0.0, "life": 0.15, "size": 120.0 * scale, "facing": facing, "seed": seed})
		bursts.append({"kind": "bolts", "at": at, "age": 0.0, "life": 0.12, "size": 30.0 * scale + 8.0, "facing": facing, "seed": seed, "awakened": awakened_form})
		spark_burst(at, int(20 * scale) + 6, Vector2(facing, -0.3), 90.0, 260.0, seed)
		mote_burst(at, int(6 * scale) + 2, 50.0, seed + 3, awakened_form)
		if scale >= 1.0:
			bursts.append({"kind": "rays", "at": at, "age": 0.0, "life": 0.22, "size": 100.0 * scale, "facing": facing, "seed": seed})
			debris_burst(at, 6, Vector2(facing * 0.4, 0.0), seed + 5)
	else:
		bursts.append({"kind": "star", "at": at, "age": 0.0, "life": 0.12, "size": 13.0, "facing": facing, "seed": seed,
			"fill": Color(0.86, 0.96, 1.0), "rim": Kit.CYAN_DEEP})
		spark_burst(at, 10, Vector2(-facing, -0.5), 60.0, 150.0, seed, Kit.CYAN)

# --- Drawing ---------------------------------------------------------------------

func _paint(canvas: Node2D, layer: int) -> void:
	if camera == null or combat == null:
		return
	if combat.phase in ["fight", "round_end"]:
		for f in combat.fighters:
			if handles(f.move) and combat.presents_attack(f.slot) and f.slot < actors.size():
				set_base(canvas, frame_transform(f.x, f.y, f.facing))
				technique(f.move).draw(canvas, layer, f, actors[f.slot])
		for each: RefCounted in techniques.values():
			each.draw_lingering(canvas, layer)
	for burst: Dictionary in bursts:
		_draw_burst(canvas, layer, burst)
	canvas.draw_set_transform(Vector2.ZERO)
	var to_screen := Callable(camera, "point")
	match layer:
		Kit.FRONT:
			debris.draw(canvas, chunk, to_screen, camera.zoom)
		Kit.LIGHT:
			sparks.draw(canvas, dot, to_screen, camera.zoom)
			motes.draw(canvas, glow, to_screen, camera.zoom)

func _draw_burst(canvas: Node2D, layer: int, burst: Dictionary) -> void:
	var k: float = burst.age / burst.life
	set_base(canvas, Transform2D(0.0, Vector2(camera.zoom * burst.facing, camera.zoom), 0.0, camera.point(burst.at)))
	var seed: int = burst.seed
	match burst.kind:
		"star":
			var pop := 1.0 - pow(1.0 - clampf(burst.age / 0.05, 0.0, 1.0), 3.0)
			var alpha := 1.0 - smoothstep(0.45, 1.0, k)
			star(canvas, layer, Vector2.ZERO, burst.size * (0.7 + 0.3 * pop), 11, seed, alpha, burst.fill, burst.rim)
		"cross":
			if layer == Kit.LIGHT:
				var grow := 1.0 - pow(1.0 - clampf(burst.age / 0.04, 0.0, 1.0), 3.0)
				cross(canvas, Vector2.ZERO, burst.size * (0.85 + 0.15 * grow), 1.0 - smoothstep(0.35, 1.0, k), seed)
		"bolts":
			# Short bolts radiate from the hit; they re-strike once mid-life.
			var flicker := seed + (1 if k > 0.5 else 0) * 7
			for n in range(5):
				var direction := Vector2.from_angle(Bolt.rand(flicker, n) * TAU)
				var trunk := Bolt.path(direction * 6.0, direction * burst.size * lerpf(0.6, 1.1, Bolt.rand(flicker, n + 10)), flicker + n * 17, 0.28, 3)
				bolt(canvas, layer, trunk, 2.2, burst.awakened, 1.0 - smoothstep(0.6, 1.0, k))
		"rays":
			if layer == Kit.LIGHT:
				rays(canvas, Vector2.ZERO, seed, 14, burst.size * (0.6 + 0.4 * k), 1.0 - k)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## Canvas transform of a fighter-local frame at world (x, y) facing `facing`.
func frame_transform(x: float, y: float, facing: float) -> Transform2D:
	return Transform2D(0.0, Vector2(camera.zoom * facing, camera.zoom), 0.0, camera.point(Vector2(x, y)))

func set_base(canvas: Node2D, transform: Transform2D) -> void:
	base = transform
	canvas.draw_set_transform_matrix(base)

## One lightning line: wide blue (gold when awakened) glow under the fighters,
## a tinted body and a white-hot core on top.
func bolt(canvas: Node2D, layer: int, points: PackedVector2Array, width: float, awakened_form: bool, alpha: float) -> void:
	if points.size() < 2 or alpha <= 0.01:
		return
	match layer:
		Kit.GLOW:
			canvas.draw_polyline(points, Color(Kit.bolt_glow(awakened_form), 0.32 * alpha), width * 4.0, true)
		Kit.LIGHT:
			canvas.draw_polyline(points, Color(Kit.bolt_tint(awakened_form), 0.75 * alpha), width * 1.7, true)
		Kit.FRONT:
			canvas.draw_polyline(points, Color(Kit.WHITE, alpha), maxf(width * 0.6, 0.8), true)

## A crescent of iai light along `path` (point(u, offset), width(u)), revealed to
## `head` and eroding behind `tail`. Styles: "electric" (thin cyan-white),
## "gold" (gold body, white core, blue rim and a lightning fringe), "heat"
## (gold with orange glow).
func crescent(canvas: Node2D, layer: int, path: RefCounted, head: float, tail: float, style: String, awakened_form: bool, seed: int, count: int = 28) -> void:
	if head <= 0.02 or tail >= 1.0:
		return
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(count):
		var u := head * n / (count - 1.0)
		points.append(path.point(u, 0.0))
		widths.append(path.width(u))
		tint.append(Color(1, 1, 1, smoothstep(tail - 0.2, tail + 0.04, u)))
	var electric := style == "electric" and not awakened_form
	var rim_tone: Color = Kit.HEAT if style == "heat" else (Kit.bolt_glow(awakened_form) if style != "electric" else Kit.CYAN_DEEP)
	match layer:
		Kit.GLOW:
			Ribbon.draw(canvas, points, _scaled(widths, 3.0), _tinted(tint, Color(rim_tone, 0.28)), band)
		Kit.FRONT:
			var body_tone: Color = Kit.CYAN if electric else Kit.GOLD
			Ribbon.draw(canvas, points, widths, _tinted(tint, Color(body_tone, 0.95)), band)
			Ribbon.draw(canvas, points, _scaled(widths, 0.45), _tinted(tint, Kit.WHITE), band)
		Kit.LIGHT:
			Ribbon.draw(canvas, points, _scaled(widths, 1.4), _tinted(tint, Color(Kit.CYAN if electric else Kit.GOLD_HOT, 0.5)), band)
	if style == "electric" and not awakened_form:
		return
	# A lightning fringe along the outer edge, re-struck every combat tick.
	for n in range(4):
		var u := lerpf(maxf(tail, 0.15), head, (n + 0.5) / 4.0)
		var edge: Vector2 = path.point(u, path.width(u) * 0.5)
		var out: Vector2 = path.point(u, path.width(u) * 0.5 + 10.0 + 8.0 * Bolt.rand(seed, n)) - edge
		bolt(canvas, layer, Bolt.path(edge, edge + out.rotated((Bolt.rand(seed, n + 5) - 0.5) * 0.9), seed + n * 13, 0.35, 2), 1.4, awakened_form,
			smoothstep(tail - 0.1, tail + 0.1, u))

## A dash beam from `tail` to `head`: a thick white-hot core with gold edges,
## tapering to the tail, with a spiky star at the head.
func beam(canvas: Node2D, layer: int, tail: Vector2, head: Vector2, thickness: float, alpha: float, awakened_form: bool, seed: int, head_star: bool = true) -> void:
	if alpha <= 0.01 or tail.distance_to(head) < 2.0:
		return
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(12):
		var u := n / 11.0
		points.append(tail.lerp(head, u))
		widths.append(thickness * (0.18 + 0.82 * pow(u, 0.7)))
		tint.append(Color(1, 1, 1, alpha * smoothstep(0.0, 0.25, u)))
	_beam_strip(canvas, layer, points, widths, tint)
	if head_star:
		star(canvas, layer, head, thickness * 1.25, 9, seed, alpha, Color(0.9, 0.98, 1.0), Kit.bolt_glow(awakened_form))

## One beam strip on its layer: soft gold glow, gold body with a white core,
## additive gold light.
func _beam_strip(canvas: Node2D, layer: int, points: PackedVector2Array, widths: PackedFloat32Array, tint: PackedColorArray) -> void:
	match layer:
		Kit.GLOW:
			Ribbon.draw(canvas, points, _scaled(widths, 2.6), _tinted(tint, Color(Kit.GOLD, 0.3)), band)
		Kit.FRONT:
			Ribbon.draw(canvas, points, widths, _tinted(tint, Color(Kit.GOLD_HOT, 0.95)), band)
			Ribbon.draw(canvas, points, _scaled(widths, 0.5), _tinted(tint, Kit.WHITE), band)
		Kit.LIGHT:
			Ribbon.draw(canvas, points, _scaled(widths, 1.5), _tinted(tint, Color(Kit.GOLD_HOT, 0.45)), band)

## The pointed front of a dash beam ending at `at` with `thickness`: a lance of
## light carrying the beam on and tapering to `tip`, and (at `shock` alpha) two
## thin shock lines folding back from the tip like a bow wave.
func spearhead(canvas: Node2D, layer: int, at: Vector2, tip: Vector2, thickness: float, alpha: float, shock: float, awakened_form: bool) -> void:
	var length := at.distance_to(tip)
	if alpha <= 0.01 or length < 1.0:
		return
	var direction := (tip - at) / length
	var tint := PackedColorArray([Color(1, 1, 1, alpha), Color(1, 1, 1, alpha), Color(1, 1, 1, alpha)])
	_beam_strip(canvas, layer, PackedVector2Array([at, at.lerp(tip, 0.4), tip]), PackedFloat32Array([thickness, thickness * 0.62, 0.0]), tint)
	if layer == Kit.LIGHT and shock > 0.01:
		var edge := Kit.bolt_tint(awakened_form)
		for side: float in [-1.0, 1.0]:
			var back := direction.rotated(PI + side * 0.38) * length * 1.4
			Ribbon.draw(canvas, PackedVector2Array([tip, tip + back * 0.5, tip + back]), PackedFloat32Array([1.8, 1.2, 0.0]),
				PackedColorArray([Color(Kit.WHITE, 0.9 * shock), Color(edge, 0.6 * shock), Color(edge, 0.0)]), band)

## A comic starburst: alternating long and short spikes, filled, with a rim line.
func star(canvas: Node2D, layer: int, at: Vector2, radius: float, spikes: int, seed: int, alpha: float, fill: Color, rim: Color) -> void:
	if alpha <= 0.01 or radius < 1.0:
		return
	if layer == Kit.GLOW or layer == Kit.LIGHT:
		if glow != null:
			var size := radius * (2.6 if layer == Kit.GLOW else 1.4)
			canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * size, Vector2.ONE * size * 2.0), false, Color(fill, (0.35 if layer == Kit.GLOW else 0.6) * alpha))
		return
	if layer != Kit.FRONT:
		return
	var points := PackedVector2Array()
	var turn := Bolt.rand(seed, 70) * TAU
	for n in range(spikes * 2):
		var a := turn + TAU * n / (spikes * 2.0)
		var r := radius * (lerpf(0.85, 1.25, Bolt.rand(seed, n)) if n % 2 == 0 else lerpf(0.38, 0.5, Bolt.rand(seed, n)))
		points.append(at + Vector2(cos(a), sin(a)) * r)
	canvas.draw_colored_polygon(points, Color(fill, alpha))
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline, Color(rim, alpha), maxf(radius * 0.07, 1.0), true)

## Gold X flash: two long tapered spikes, white core to amber rim.
func cross(canvas: Node2D, at: Vector2, length: float, alpha: float, seed: int) -> void:
	var tilt := (Bolt.rand(seed, 80) - 0.5) * 0.5
	for angle: float in [0.32 + tilt, -0.62 + tilt]:
		var axis := Vector2.from_angle(angle)
		var points := PackedVector2Array([at - axis * length * 0.5, at - axis * length * 0.15, at, at + axis * length * 0.15, at + axis * length * 0.5])
		for spec in [[10.0, Color(1.0, 0.62, 0.12, 0.6)], [5.0, Color(1.0, 0.92, 0.4, 0.9)], [2.0, Color(1, 1, 1, 1)]]:
			var thickness: float = spec[0]
			var tone: Color = spec[1]
			Ribbon.draw(canvas, points, PackedFloat32Array([0.0, thickness * 0.55, thickness, thickness * 0.55, 0.0]),
				PackedColorArray([Color(tone, 0.0), Color(tone, tone.a * alpha), Color(tone, tone.a * alpha), Color(tone, tone.a * alpha), Color(tone, 0.0)]), band)

## Long thin rays radiating from `at` (additive layers only).
func rays(canvas: Node2D, at: Vector2, seed: int, count: int, length: float, alpha: float) -> void:
	for n in range(count):
		var direction := Vector2.from_angle(TAU * n / count + Bolt.rand(seed, n + 90) * 0.35)
		var reach := length * lerpf(0.5, 1.0, Bolt.rand(seed, n + 110))
		Ribbon.draw(canvas, PackedVector2Array([at + direction * reach * 0.15, at + direction * reach * 0.55, at + direction * reach]),
			PackedFloat32Array([2.4, 1.4, 0.0]), PackedColorArray([Color(Kit.GOLD_HOT, 0.8 * alpha), Color(Kit.GOLD, 0.55 * alpha), Color(Kit.GOLD, 0.0)]), band)

## Dark speed lines streaming back from `head` along the dash (solid layer).
func speed_lines(canvas: Node2D, tail: Vector2, head: Vector2, seed: int, count: int, alpha: float) -> void:
	var along := head - tail
	if along.length() < 4.0 or alpha <= 0.01:
		return
	var normal := along.orthogonal().normalized()
	for n in range(count):
		var offset := normal * lerpf(-30.0, 30.0, Bolt.rand(seed, n))
		var from := tail.lerp(head, lerpf(0.0, 0.6, Bolt.rand(seed, n + 20))) + offset
		var to := from + along.normalized() * along.length() * lerpf(0.25, 0.5, Bolt.rand(seed, n + 40))
		canvas.draw_line(from, to, Color(Kit.SPEED_LINE, 0.55 * alpha), lerpf(0.8, 1.8, Bolt.rand(seed, n + 60)), true)

## A dark scorch streak on the floor (local y = 0) from `from_x` to `to_x`.
func scorch(canvas: Node2D, from_x: float, to_x: float, alpha: float) -> void:
	if absf(to_x - from_x) < 4.0 or alpha <= 0.01:
		return
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(10):
		var u := n / 9.0
		points.append(Vector2(lerpf(from_x, to_x, u), -0.5))
		widths.append(5.5 * sin(clampf(u, 0.05, 0.95) * PI))
		tint.append(Color(Kit.SCORCH, 0.55 * alpha))
	Ribbon.draw(canvas, points, widths, tint, band)

## A vertical column of electric light with bolts climbing it (air charge).
func pillar(canvas: Node2D, layer: int, at: Vector2, height: float, width: float, alpha: float, awakened_form: bool, seed: int) -> void:
	if alpha <= 0.01:
		return
	if layer == Kit.GLOW or layer == Kit.LIGHT:
		var points := PackedVector2Array([at + Vector2(0, height * 0.5), at, at - Vector2(0, height * 0.5)])
		Ribbon.draw(canvas, points, PackedFloat32Array([width * 0.2, width, width * 0.2]),
			PackedColorArray([Color(Kit.bolt_glow(awakened_form), 0.0), Color(Kit.bolt_glow(awakened_form), (0.3 if layer == Kit.GLOW else 0.22) * alpha),
				Color(Kit.bolt_glow(awakened_form), 0.0)]), band)
	for n in range(3):
		var x := (Bolt.rand(seed, n) - 0.5) * width * 0.6
		bolt(canvas, layer, Bolt.path(at + Vector2(x, height * 0.4), at + Vector2(x * 0.4, -height * 0.45), seed + n * 19, 0.18, 3), 1.6, awakened_form, alpha * 0.8)

## A crackling sphere of lightning around `at` (远雷's hover).
func sphere(canvas: Node2D, layer: int, at: Vector2, radius: float, alpha: float, awakened_form: bool, seed: int) -> void:
	if alpha <= 0.01:
		return
	if (layer == Kit.GLOW or layer == Kit.LIGHT) and glow != null:
		canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * radius * 1.4, Vector2.ONE * radius * 2.8), false,
			Color(Kit.bolt_glow(awakened_form), (0.4 if layer == Kit.GLOW else 0.25) * alpha))
	bolt(canvas, layer, Bolt.ring(at, Vector2(radius, radius), seed, 22, 0.22), 1.6, awakened_form, alpha)
	for n in range(3):
		var a := Bolt.rand(seed, n + 40) * TAU
		var p := at + Vector2.from_angle(a) * radius
		bolt(canvas, layer, Bolt.path(p, p + Vector2.from_angle(a) * radius * 0.5, seed + n * 23, 0.35, 2), 1.2, awakened_form, alpha)

## A flat ring of lightning round the body (回身斩), far half behind the fighters.
func lightning_ring(canvas: Node2D, layer: int, center: Vector2, radii: Vector2, alpha: float, awakened_form: bool, seed: int) -> void:
	if alpha <= 0.01:
		return
	var loop := Bolt.ring(center, radii, seed, 36, 0.12)
	var far := PackedVector2Array()
	var near := PackedVector2Array()
	for point in loop:
		if point.y < center.y:
			far.append(point)
		else:
			near.append(point)
	if layer == Kit.BACK:
		canvas.draw_polyline(far, Color(Kit.bolt_tint(awakened_form), 0.7 * alpha), 2.0, true)
	elif layer in [Kit.GLOW, Kit.LIGHT, Kit.FRONT]:
		bolt(canvas, layer, near, 2.2, awakened_form, alpha)

## The fighter's own drawing flashed in `color` (additive layers only).
func body_flash(canvas: Node2D, f: RefCounted, actor: Node2D, color: Color) -> void:
	if actor.texture == null:
		return
	canvas.draw_set_transform(camera.point(Vector2(f.x, f.y)), 0, Vector2(camera.zoom * actor.pose_facing(), camera.zoom))
	canvas.draw_texture_rect(actor.texture, actor.sprite_rect(), false, color)
	canvas.draw_set_transform_matrix(base)

static func _scaled(widths: PackedFloat32Array, factor: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for w in widths:
		result.append(w * factor)
	return result

static func _tinted(alphas: PackedColorArray, tone: Color) -> PackedColorArray:
	var result := PackedColorArray()
	for c in alphas:
		result.append(Color(tone, tone.a * c.a))
	return result

func awakened(slot: int) -> bool:
	return slot < actors.size() and actors[slot] != null and actors[slot].form_active()

## Fighter-local point or direction to world, for anything with x, y, facing.
static func world(frame: Variant, local: Vector2) -> Vector2:
	return Vector2(frame.x + local.x * frame.facing, frame.y + local.y)

static func world_dir(frame: Variant, local: Vector2) -> Vector2:
	return Vector2(local.x * frame.facing, local.y)

static func rand(seed: int, n: int) -> float:
	return Bolt.rand(seed, n)
