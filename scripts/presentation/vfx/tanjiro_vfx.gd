extends Node2D
## Tanjiro's elemental effects after the Hinokami Chronicles look: cel-shaded
## water strands with ukiyo-e foam, Hinokami Kagura flame woven in while he is
## awakened, and pure sun flame for 碧罗之天. Each technique lives in
## vfx/tanjiro/; this node owns the layers, particle pools, contact bursts and
## the shared brush-strand drawing. Shapes follow the move clock and the drawn
## blade; particles and bursts advance only with the presentation time
## EffectsView passes in, so hitstop, super freeze, pause and KO freezes hold the
## whole picture. Combat state is only ever read.
const Kit = preload("res://scripts/presentation/vfx/tanjiro/kit.gd")
const Ribbon = preload("res://scripts/presentation/vfx/vfx_ribbon.gd")
const Pool = preload("res://scripts/presentation/vfx/vfx_pool.gd")
const Blade = preload("res://scripts/presentation/vfx/blade_track.gd")
const MIX_SHADER = preload("res://scripts/presentation/vfx/shaders/erode_mix.gdshader")
const ADD_SHADER = preload("res://scripts/presentation/vfx/shaders/erode_add.gdshader")
const ART := "res://art/effects/tanjiro/"
const TRACKS := "res://art/characters/tanjiro/"
const TECHNIQUES := {
	"slash": preload("res://scripts/presentation/vfx/tanjiro/water_slash.gd"),
	"wheel": preload("res://scripts/presentation/vfx/tanjiro/water_wheel.gd"),
	"vortex": preload("res://scripts/presentation/vfx/tanjiro/water_vortex.gd"),
	"dragon": preload("res://scripts/presentation/vfx/tanjiro/water_dragon.gd"),
	"sun": preload("res://scripts/presentation/vfx/tanjiro/sun_halo.gd"),
	"blade": preload("res://scripts/presentation/vfx/tanjiro/blade_trail.gd"),
	"waterfall": preload("res://scripts/presentation/vfx/tanjiro/waterfall.gd"),
}
## Moves drawn here and the technique drawing each; the rest of the kit still
## uses EffectsView.
const MOVES := {
	"tanjiro_236A": "slash", "tanjiro_236C": "slash",
	"tanjiro_623A": "wheel", "tanjiro_623C": "wheel",
	"tanjiro_214B": "vortex", "tanjiro_214D": "vortex",
	"tanjiro_super": "dragon",
	"tanjiro_max": "sun",
	"tanjiro_5A": "blade", "tanjiro_5C": "blade", "tanjiro_2A": "blade", "tanjiro_2C": "blade", "tanjiro_jA": "blade", "tanjiro_jC": "blade",
	# Move-set expansion: Striking Tide and Drop Ripple Thrust follow the drawn blade;
	# Waterfall Basin pours its own waterfall; the air Water Wheel draws the wheel ring.
	"tanjiro_5AA": "blade", "tanjiro_5AAC": "blade", "tanjiro_6C": "blade",
	"tanjiro_j236A": "waterfall", "tanjiro_j236C": "waterfall",
	"tanjiro_j214B": "wheel", "tanjiro_j214D": "wheel",
}
const TEXTURES := ["water-strands", "hybrid-fire-strands", "fire-strands", "white-brush-strands", "water-crescent", "water-crescent-heavy",
	"water-impact", "water-foam", "water-dragon-head", "hybrid-fire-chips", "fire-petals", "noise"]
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
var textures: Dictionary = {}
var band: GradientTexture2D
var dot: Texture2D
var drops := Pool.new(1, 1, 360)
var foam := Pool.new(4, 4, 140)
## Crimson flame pieces for the awakened water/fire blend.
var petals := Pool.new(4, 4, 220)
## Yellow-core flame pieces for pure Hinokami Kagura.
var embers := Pool.new(4, 4, 160)
var mist := Pool.new(1, 1, 220)
var bursts: Array[Dictionary] = []
var layers: Array[Node2D] = []
var techniques: Dictionary = {}
var _ticks: Dictionary = {}
var _projectiles: Dictionary = {}
## Local-to-canvas transform of the shape being drawn.
var base := Transform2D.IDENTITY

func _ready() -> void:
	for id: String in TEXTURES:
		var path: String = ART + id + ".png"
		if ResourceLoader.exists(path):
			textures[id] = load(path)
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	falloff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	band = GradientTexture2D.new()
	band.gradient = falloff
	band.fill_from = Vector2(0, 0)
	band.fill_to = Vector2(0, 1)
	band.width = 4
	band.height = 64
	dot = _droplet_texture()
	drops.fade_in = 0.0
	drops.fade_out = 0.3
	mist.fade_in = 0.15
	mist.fade_out = 0.6
	foam.fade_out = 0.4
	petals.fade_out = 0.4
	embers.fade_out = 0.45
	for spec in [["TanjiroBack", MIX_SHADER, -9, false], ["TanjiroWater", MIX_SHADER, -1, false], ["TanjiroSolid", null, -1, false],
			["TanjiroFront", null, 0, false], ["TanjiroFlame", ADD_SHADER, 0, true], ["TanjiroLight", null, 0, true]]:
		layers.append(_layer(spec[0], spec[1], spec[2], spec[3]))
	for key: String in TECHNIQUES:
		var technique: RefCounted = TECHNIQUES[key].new()
		technique.vfx = self
		techniques[key] = technique

## Crisp cel droplet: white body, pale cyan rim.
static func _droplet_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length() / 14.0
			var alpha := clampf((1.0 - d) * 9.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.78, 0.95, 1.0).lerp(Color.WHITE, clampf((0.75 - d) * 4.0, 0.0, 1.0)) * Color(1, 1, 1, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _layer(id: String, shader: Shader, z: int, additive: bool) -> Node2D:
	var node := Node2D.new()
	node.name = id
	node.z_index = z
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if shader != null:
		var paint := ShaderMaterial.new()
		paint.shader = shader
		paint.set_shader_parameter("erosion_noise", textures.get("noise"))
		node.material = paint
	else:
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
	for pool in [drops, foam, petals, embers, mist]:
		pool.clear()
	bursts.clear()
	_ticks.clear()
	_projectiles.clear()
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
	for f in combat.fighters:
		_emit_fighter(f)
	for each: RefCounted in techniques.values():
		each.linger(combat.fighters, actors)
	_track_projectiles()
	for pool in [drops, foam, petals, embers, mist]:
		pool.advance(delta)
	for burst: Dictionary in bursts:
		burst.age += delta
	bursts = bursts.filter(func(b: Dictionary) -> bool: return b.age < b.life)
	redraw()

func consume(events: Array) -> void:
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

func _track_projectiles() -> void:
	var seen := {}
	for p: Dictionary in combat.projectiles:
		var move: Resource = combat.moves.get(p.move)
		if not handles(move):
			continue
		var key := "%d:%d" % [int(p.owner), int(p.instance)]
		seen[key] = true
		var age: int = move.projectile_lifetime - int(p.life)
		var record: Dictionary = _projectiles.get(key, {"age": -1})
		for tick in range(int(record.age) + 1, age + 1):
			technique(move).emit_projectile(p, move, tick, age)
		_projectiles[key] = {"age": age, "x": p.x, "y": p.y, "facing": int(p.facing), "move": p.move, "owner": int(p.owner), "instance": int(p.instance)}
	for key: String in _projectiles.keys():
		var record: Dictionary = _projectiles[key]
		if not seen.has(key):
			technique(combat.moves[record.move]).release_projectile(record)
			_projectiles.erase(key)

# --- Particle bursts --------------------------------------------------------------

func droplets(at: Vector2, count: int, bias: Vector2, slow: float, fast: float, seed: int) -> void:
	for n in range(count):
		var direction := (Vector2.from_angle(rand(seed, n) * TAU) + bias * 0.9).normalized()
		drops.spawn(at, direction * lerpf(slow, fast, rand(seed, n + 50)), lerpf(0.3, 0.55, rand(seed, n + 100)), lerpf(1.5, 3.4, rand(seed, n + 150)), 0, Color.WHITE,
			380.0, 0.6, 0.0, 0.0, 0.7, 0.8)

func foam_burst(at: Vector2, count: int, bias: Vector2, slow: float, fast: float, seed: int) -> void:
	for n in range(count):
		var direction := (Vector2.from_angle(rand(seed, n) * TAU) + bias * 0.8).normalized()
		foam.spawn(at, direction * lerpf(slow, fast, rand(seed, n + 50)), lerpf(0.25, 0.4, rand(seed, n + 100)), lerpf(6.0, 10.0, rand(seed, n + 150)),
			(Kit.SPRAY_CELLS + Kit.CURL_CELLS)[n % 12], Color.WHITE, 220.0, 1.5, rand(seed, n + 200) * TAU, rand(seed, n + 250) * 6.0 - 3.0, 0.8)

func mist_burst(at: Vector2, count: int, speed: float, seed: int) -> void:
	for n in range(count):
		mist.spawn(at, Vector2.from_angle(rand(seed, n) * TAU) * speed * lerpf(0.5, 1.0, rand(seed, n + 20)), 0.45, lerpf(9.0, 14.0, rand(seed, n + 40)), 0,
			Color(0.85, 0.95, 1.0, 0.35), 0.0, 2.0, 0.0, 0.0, 1.8)

## Crimson flame pieces (awakened water/fire blend).
func petal_burst(at: Vector2, count: int, speed: float, seed: int) -> void:
	for n in range(count):
		petals.spawn(at, Vector2.from_angle(rand(seed, n) * TAU) * speed * lerpf(0.4, 1.0, rand(seed, n + 20)) + Vector2(0, -20), lerpf(0.4, 0.7, rand(seed, n + 40)),
			lerpf(5.0, 9.0, rand(seed, n + 60)), Kit.FLAME_CELLS[n % Kit.FLAME_CELLS.size()], Color.WHITE, -40.0, 1.5, rand(seed, n + 80) * TAU, rand(seed, n + 100) * 8.0 - 4.0, 0.7)

## Yellow-core flame pieces (pure Hinokami Kagura).
func ember_burst(at: Vector2, count: int, speed: float, seed: int) -> void:
	for n in range(count):
		var cells: Array = Kit.SUN_TONGUE_CELLS if n % 3 else Kit.SUN_SPARK_CELLS
		embers.spawn(at, Vector2.from_angle(rand(seed, n) * TAU) * speed * lerpf(0.4, 1.0, rand(seed, n + 20)) + Vector2(0, -30), lerpf(0.35, 0.65, rand(seed, n + 40)),
			lerpf(5.0, 10.0, rand(seed, n + 60)), cells[n % cells.size()], Color.WHITE, -60.0, 1.6, rand(seed, n + 80) * TAU, rand(seed, n + 100) * 8.0 - 4.0, 0.6)

## Water contact: full-size splash crown, gold X flash, ring and spray. Hitstop
## holds these on their first frame, so that frame must already read.
func water_contact(event: Dictionary, attacker: RefCounted, scale: float, hybrid: bool, cross: bool = true) -> void:
	var at: Vector2 = event.position
	var facing := float(attacker.facing)
	var seed: int = attacker.attack_instance * 977 + int(event.get("segment", 0)) * 31
	if event.type == "hit":
		bursts.append({"kind": "splash", "at": at, "age": 0.0, "life": 0.32, "size": 48.0 * scale, "facing": facing, "spin": rand(seed, 1) * 0.3 - 0.15})
		if cross:
			bursts.append({"kind": "cross", "at": at, "age": 0.0, "life": 0.14, "size": 128.0 * scale, "facing": facing})
		bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.22, "size": 28.0 * scale, "tone": Color(1.0, 0.38, 0.24) if hybrid else Color(0.8, 0.95, 1.0)})
		droplets(at, int(24 * scale), Vector2(facing, -0.2), 90.0, 230.0, seed)
		foam_burst(at, int(5 * scale + 0.5), Vector2(facing, -0.3), 50.0, 110.0, seed + 3)
		mist_burst(at, 5, 26.0, seed + 5)
		if hybrid:
			petal_burst(at, int(24 * scale), 130.0, seed + 9)
	else:
		bursts.append({"kind": "splash", "at": at, "age": 0.0, "life": 0.28, "size": 40.0, "facing": facing, "spin": 0.0})
		droplets(at, 12, Vector2(-facing, -0.5), 60.0, 140.0, seed)

## Sun contact: gold X flash, a hot flare and flame pieces, no water.
func sun_contact(event: Dictionary, attacker: RefCounted, scale: float) -> void:
	var at: Vector2 = event.position
	var facing := float(attacker.facing)
	var seed: int = attacker.attack_instance * 977 + int(event.get("segment", 0)) * 31
	if event.type == "hit":
		bursts.append({"kind": "flare", "at": at, "age": 0.0, "life": 0.3, "size": 46.0 * scale, "facing": facing})
		bursts.append({"kind": "cross", "at": at, "age": 0.0, "life": 0.16, "size": 150.0 * scale, "facing": facing})
		bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.24, "size": 34.0 * scale, "tone": Color(1.0, 0.5, 0.2)})
		ember_burst(at, int(26 * scale), 170.0, seed)
		petal_burst(at, int(16 * scale), 120.0, seed + 7)
	else:
		bursts.append({"kind": "flare", "at": at, "age": 0.0, "life": 0.2, "size": 28.0, "facing": facing})
		ember_burst(at, 10, 90.0, seed)

# --- Drawing ---------------------------------------------------------------------

func _paint(canvas: Node2D, layer: int) -> void:
	if camera == null or combat == null:
		return
	if combat.phase in ["fight", "round_end"]:
		for f in combat.fighters:
			if handles(f.move) and combat.presents_attack(f.slot) and f.slot < actors.size():
				set_base(canvas, frame_transform(f.x, f.y, f.facing))
				technique(f.move).draw(canvas, layer, f, actors[f.slot])
		for p: Dictionary in combat.projectiles:
			var move: Resource = combat.moves.get(p.move)
			if handles(move):
				set_base(canvas, frame_transform(p.x, p.y, p.facing))
				technique(move).draw_projectile(canvas, layer, p, move)
		for each: RefCounted in techniques.values():
			each.draw_lingering(canvas, layer)
	canvas.draw_set_transform(Vector2.ZERO)
	var to_screen := Callable(camera, "point")
	match layer:
		Kit.FRONT:
			_draw_bursts(canvas, "splash")
			foam.draw(canvas, textures.get("water-foam"), to_screen, camera.zoom)
			petals.draw(canvas, textures.get("hybrid-fire-chips"), to_screen, camera.zoom)
			embers.draw(canvas, textures.get("fire-petals"), to_screen, camera.zoom)
			drops.draw(canvas, dot, to_screen, camera.zoom)
		Kit.LIGHT:
			mist.draw(canvas, glow, to_screen, camera.zoom)
			_draw_bursts(canvas, "light")

## Canvas transform of a fighter-local frame at world (x, y) facing `facing`.
func frame_transform(x: float, y: float, facing: float) -> Transform2D:
	return Transform2D(0.0, Vector2(camera.zoom * facing, camera.zoom), 0.0, camera.point(Vector2(x, y)))

func set_base(canvas: Node2D, transform: Transform2D) -> void:
	base = transform
	canvas.draw_set_transform_matrix(base)

## Every strand of a water body along `path`, with flame woven in while
## awakened. Flame is opaque so red and blue stay distinct instead of washing
## out to white.
func water_body(canvas: Node2D, path: RefCounted, head: float, tail: float, hybrid: bool, instance: int, flow: float = 1.0, patches: bool = true) -> void:
	var length: float = path.length
	for k in range(Kit.STRANDS.size()):
		var spec: Dictionary = Kit.STRANDS[k]
		strand(canvas, path, head, tail, spec.offset, spec.width, spec.from, spec.to, spec.tint, spec.rows,
			length / 1.15, -time * float(spec.flow) * flow + float(spec.offset))
		if hybrid:
			flames(canvas, path, head, tail, k, flow)
	for fray: Dictionary in Kit.FRAYS:
		strand(canvas, path, head, tail - 0.1, fray.offset, fray.width, 0.0, fray.to, Color(0.95, 0.98, 1.0), [0.4, 0.8], length / 2.0, -time * 1.6 * flow + float(fray.offset))
	if hybrid:
		flames(canvas, path, head, tail, Kit.STRANDS.size(), flow)
		if patches:
			flame_patches(canvas, path, head, tail, instance)

## Flame strands drawn over water strand `after` (see Kit.FLAMES). They burn on
## a little after the water erodes.
func flames(canvas: Node2D, path: RefCounted, head: float, tail: float, after: int, flow: float = 1.0) -> void:
	for flame: Dictionary in Kit.FLAMES:
		if int(flame.after) != after:
			continue
		strand(canvas, path, head, tail + 0.06, flame.offset, flame.width, flame.from, flame.to, Color(1, 1, 1), [0.1, 0.9],
			path.length / 1.5, -time * float(flame.flow) * flow + float(flame.offset), textures.get("hybrid-fire-strands"))

## One brush strand along `path`: tapered at both ends, trimmed to its own share
## of the stroke, revealed up to `head` and eroding behind `tail`. `side` keeps
## only the near (1) or far (-1) half of a wrapped path.
func strand(canvas: Node2D, path: RefCounted, head: float, tail: float, offset: float, width: float, from: float, to: float,
		tint: Color, rows: Array, u_scale: float, u_offset: float, texture: Texture2D = null, side: int = 0, count: int = 32) -> void:
	var end := minf(head, to)
	if end <= from + 0.02:
		return
	var top: float = rows[1] if path.mirrored else rows[0]
	var bottom: float = rows[0] if path.mirrored else rows[1]
	var paint: Texture2D = texture if texture != null else textures.get("water-strands")
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var colors := PackedColorArray()
	var run_start := from
	for n in range(count):
		var u := lerpf(from, end, n / (count - 1.0))
		if side != 0 and path.depth(u) * side < 0.0:
			# Flush the visible run; the texture continues where it left off.
			if points.size() > 1:
				Ribbon.draw(canvas, points, widths, colors, paint, u_scale, u_offset + run_start * path.length / u_scale, top, bottom)
			points.clear()
			widths.clear()
			colors.clear()
			continue
		if points.is_empty():
			run_start = u
		var s := (u - from) / maxf(to - from, 0.001)
		var thickness: float = path.width(u)
		points.append(path.point(u, thickness * offset))
		widths.append(thickness * width * pow(sin(clampf(s, 0.02, 0.98) * PI), 0.6))
		colors.append(Color(tint, tint.a * smoothstep(tail - 0.22, tail + 0.02, u)))
	if points.size() > 1:
		Ribbon.draw(canvas, points, widths, colors, paint, u_scale, u_offset + (run_start * path.length / u_scale if side != 0 else 0.0), top, bottom)

## Torn flame pieces clinging to an awakened stroke, eroding with the strands.
func flame_patches(canvas: Node2D, path: RefCounted, head: float, tail: float, instance: int) -> void:
	var sheet: Texture2D = textures.get("hybrid-fire-chips")
	if sheet == null:
		return
	var cell := sheet.get_size() / 4.0
	for n in range(Kit.FLAME_PATCHES.size()):
		var u: float = Kit.FLAME_PATCHES[n][0]
		if u > head:
			break
		var presence := smoothstep(tail - 0.16, tail + 0.08, u)
		if presence <= 0.02:
			continue
		var thickness: float = path.width(u)
		var at: Vector2 = path.point(u, thickness * float(Kit.FLAME_PATCHES[n][1]))
		var angle: float = path.angle(u) + (rand(instance, n) - 0.5) * 0.6
		var size := thickness * lerpf(0.75, 1.05, rand(instance, n + 20)) + 5.0
		var index: int = Kit.PETAL_CELLS[(n * 5 + instance) % Kit.PETAL_CELLS.size()]
		var origin := Vector2(index % 4, index / 4) * cell
		canvas.draw_set_transform_matrix(base * Transform2D(angle, at))
		canvas.draw_texture_rect_region(sheet, Rect2(-size * 0.5, -size * 0.5, size, size), Rect2(origin, cell), Color(1, 1, 1, presence))
	canvas.draw_set_transform_matrix(base)

## Ukiyo-e foam curls riding the outer edge of a stroke, from `from_u` to its head.
func foam_crest(canvas: Node2D, path: RefCounted, head: float, tail: float, count: int, from_u: float = 0.42, edge: float = 0.42) -> void:
	var sheet: Texture2D = textures.get("water-foam")
	if sheet == null:
		return
	var cell := sheet.get_size() / 4.0
	# Curls face the left of travel; flip them when that is the inside.
	var side := -1.0 if path.mirrored else 1.0
	for n in range(count):
		var u := from_u + (0.98 - from_u) * n / maxf(count - 1.0, 1.0)
		if u > head:
			break
		var presence := smoothstep(tail - 0.2, tail + 0.02, u)
		if presence <= 0.05:
			continue
		var thickness: float = path.width(u)
		var at: Vector2 = path.point(u, thickness * edge)
		var size := (thickness * 0.62 + 4.0) * lerpf(0.6, 1.0, presence)
		var index: int = Kit.CURL_CELLS[n % Kit.CURL_CELLS.size()]
		var origin := Vector2(index % 4, index / 4) * cell
		canvas.draw_set_transform_matrix(base * Transform2D(path.angle(u), Vector2(1, side), 0.0, at))
		canvas.draw_texture_rect_region(sheet, Rect2(-size * 0.5, -size * 0.7, size, size), Rect2(origin, cell), Color(1, 1, 1, presence))
	canvas.draw_set_transform_matrix(base)

## A soft wash along a path, `spread` times its thickness (additive layers).
func glow_along(canvas: Node2D, path: RefCounted, head: float, tail: float, color: Color, spread: float, offset: float = 0.0, count: int = 40) -> void:
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(count):
		var u := head * n / (count - 1.0)
		var thickness: float = path.width(u)
		points.append(path.point(u, thickness * offset))
		widths.append(thickness * spread)
		tint.append(Color(color, color.a * smoothstep(tail - 0.22, tail + 0.02, u)))
	Ribbon.draw(canvas, points, widths, tint, band)

## Thin water (and flame, when awakened) along the drawn blade.
func blade_water(canvas: Node2D, layer: int, actor: Node2D, amount: float, hybrid: bool) -> void:
	var held := blade(actor, actor.frame_index)
	if held.size() != 2:
		return
	var direction := (held[1] - held[0]).normalized()
	var points := Ribbon.smooth(PackedVector2Array([held[0].lerp(held[1], 0.15), held[0].lerp(held[1], 0.6), held[1] + direction * 3.0]), 4)
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(points.size()):
		var u := float(n) / (points.size() - 1)
		widths.append(3.6 * amount * sin(clampf(u, 0.05, 0.95) * PI))
		tint.append(Color(1, 1, 1, amount))
	match layer:
		Kit.WATER:
			Ribbon.draw(canvas, points, widths, tint, textures.get("water-strands"), 14.0, -time * 2.5, 0.25, 0.9)
		Kit.FLAME:
			if hybrid:
				var thin := PackedFloat32Array()
				for w in widths:
					thin.append(w * 0.8)
				Ribbon.draw(canvas, points, thin, tint, textures.get("hybrid-fire-strands"), 12.0, -time * 3.0, 0.1, 0.9)
		Kit.LIGHT:
			var wide := PackedFloat32Array()
			var soft := PackedColorArray()
			for n in range(points.size()):
				wide.append(widths[n] * 3.0)
				soft.append(Color(Kit.FIRE_GLOW if hybrid else Kit.WATER_GLOW, 0.35 * amount))
			Ribbon.draw(canvas, points, wide, soft, band)

## Bright wash along the floor in front of the stance, eroding from behind.
func ground_streak(canvas: Node2D, layer: int, age: float, reach: float, thickness: float, from_x: float = -4.0) -> void:
	if age < 0.0 or age > 20.0:
		return
	var span := reach * clampf(age / 2.0 + 0.3, 0.0, 1.0)
	var tail := clampf((age - 4.0) / 16.0, 0.0, 1.2)
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(16):
		var u := n / 15.0
		points.append(Vector2(lerpf(from_x, span, u), -0.6 - sin(u * PI) * 0.8))
		widths.append(thickness * sin(clampf(u, 0.04, 0.96) * PI))
		tint.append(Color(1.0, 1.0, 1.0, smoothstep(tail - 0.2, tail + 0.05, u)))
	if layer == Kit.WATER:
		Ribbon.draw(canvas, points, widths, tint, textures.get("water-strands"), 30.0, -time * 1.5, 0.2, 0.9)
	elif layer == Kit.LIGHT:
		var wide := PackedFloat32Array()
		var soft := PackedColorArray()
		for n in range(points.size()):
			wide.append(widths[n] * 2.6)
			soft.append(Color(0.45, 0.85, 1.0, 0.4 * tint[n].a))
		Ribbon.draw(canvas, points, wide, soft, band)

## The fighter's own drawing flashed in `color` (additive layers only).
func body_flash(canvas: Node2D, f: RefCounted, actor: Node2D, color: Color) -> void:
	if actor.texture == null:
		return
	canvas.draw_set_transform(camera.point(Vector2(f.x, f.y)), 0, Vector2(camera.zoom * actor.pose_facing(), camera.zoom))
	canvas.draw_texture_rect(actor.texture, actor.sprite_rect(), false, color)
	canvas.draw_set_transform_matrix(base)

## A horizontal lens streak through local `at` (additive layers only).
func lens_streak(canvas: Node2D, at: Vector2, length: float, thickness: float, color: Color) -> void:
	var points := PackedVector2Array([at - Vector2(length, 0), at - Vector2(length * 0.3, 0), at, at + Vector2(length * 0.3, 0), at + Vector2(length, 0)])
	var widths := PackedFloat32Array([0.0, thickness * 0.5, thickness, thickness * 0.5, 0.0])
	var tint := PackedColorArray([Color(color, 0.0), color, color, color, Color(color, 0.0)])
	Ribbon.draw(canvas, points, widths, tint, band)
	if glow != null:
		canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * thickness * 3.0, Vector2.ONE * thickness * 6.0), false, color)

func _draw_bursts(canvas: Node2D, group: String) -> void:
	var zoom: float = camera.zoom
	for burst: Dictionary in bursts:
		var k: float = burst.age / burst.life
		var center: Vector2 = camera.point(burst.at)
		if group == "splash" and burst.kind == "splash":
			var texture: Texture2D = textures.get("water-impact")
			if texture == null:
				continue
			var size: float = burst.size * (0.8 + 0.2 * (1.0 - pow(1.0 - clampf(burst.age / 0.08, 0.0, 1.0), 3.0)))
			var aspect := float(texture.get_width()) / texture.get_height()
			canvas.draw_set_transform(center, burst.spin, Vector2(zoom * burst.facing, zoom))
			canvas.draw_texture_rect(texture, Rect2(-size * aspect * 0.42, -size * 0.55, size * aspect, size), false, Color(1, 1, 1, 1.0 - smoothstep(0.3, 1.0, k)))
			canvas.draw_set_transform(Vector2.ZERO)
		elif group == "light" and burst.kind == "cross":
			_draw_cross(canvas, center, burst, zoom)
		elif group == "light" and burst.kind == "ring":
			var tone: Color = burst.get("tone", Color(0.8, 0.95, 1.0))
			var radius: float = (6.0 + burst.size * (1.0 - pow(1.0 - k, 2.0))) * zoom
			canvas.draw_arc(center, radius, 0.0, TAU, 48, Color(tone, (1.0 - k) * 0.75), lerpf(3.0, 0.6, k) * zoom, true)
			canvas.draw_texture_rect(glow, Rect2(center - Vector2.ONE * 11.0 * zoom, Vector2.ONE * 22.0 * zoom), false, Color(1, 1, 1, maxf(0.0, 1.0 - burst.age / 0.08) * 0.45))
		elif group == "light" and burst.kind == "flare":
			_draw_flare(canvas, center, burst, zoom, k)

## Gold X flash on contact: two long tapered spikes, white core to amber rim.
func _draw_cross(canvas: Node2D, center: Vector2, burst: Dictionary, zoom: float) -> void:
	var grow := 1.0 - pow(1.0 - clampf(burst.age / 0.04, 0.0, 1.0), 3.0)
	var alpha := 1.0 - smoothstep(0.35, 1.0, burst.age / burst.life)
	var length: float = burst.size * (0.9 + 0.1 * grow) * zoom
	for angle: float in [0.34, -0.58]:
		var axis := Vector2.from_angle(angle) * Vector2(burst.facing, 1)
		var points := PackedVector2Array([center - axis * length * 0.5, center - axis * length * 0.2, center, center + axis * length * 0.2, center + axis * length * 0.5])
		for pass_spec in [[11.0, Color(1.0, 0.6, 0.1, 0.6)], [5.6, Color(1.0, 0.92, 0.35, 0.9)], [2.2, Color(1, 1, 1, 1)]]:
			var thickness: float = pass_spec[0] * zoom
			var tone: Color = pass_spec[1]
			Ribbon.draw(canvas, points, PackedFloat32Array([0.0, thickness * 0.55, thickness, thickness * 0.55, 0.0]),
				PackedColorArray([Color(tone, 0.0), Color(tone, tone.a * alpha), Color(tone, tone.a * alpha), Color(tone, tone.a * alpha), Color(tone, 0.0)]), band)

## Hot contact flare for sun flame: white core, orange body, a few short rays.
func _draw_flare(canvas: Node2D, center: Vector2, burst: Dictionary, zoom: float, k: float) -> void:
	var radius: float = burst.size * (0.7 + 0.3 * (1.0 - pow(1.0 - minf(k * 3.0, 1.0), 2.0))) * zoom
	var fade := 1.0 - smoothstep(0.2, 1.0, k)
	canvas.draw_texture_rect(glow, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, Color(Kit.SUN_GLOW, 0.8 * fade))
	canvas.draw_texture_rect(glow, Rect2(center - Vector2.ONE * radius * 0.4, Vector2.ONE * radius * 0.8), false, Color(1, 0.95, 0.8, fade))
	for n in range(6):
		var ray := Vector2.from_angle(n * TAU / 6.0 + 0.3) * Vector2(burst.facing, 1)
		Ribbon.draw(canvas, PackedVector2Array([center, center + ray * radius * 0.8, center + ray * radius * 1.5]),
			PackedFloat32Array([radius * 0.16, radius * 0.08, 0.0]), PackedColorArray([Color(1, 0.8, 0.4, fade), Color(1, 0.55, 0.2, fade * 0.8), Color(1, 0.4, 0.1, 0.0)]), band)

# --- Geometry ---------------------------------------------------------------------

## The held blade on drawing `index` of the current clip, in local units.
func blade(actor: Node2D, index: int) -> PackedVector2Array:
	var pose := blade_pose(actor, actor.clip, index)
	if pose.size() != 2:
		return PackedVector2Array()
	return PackedVector2Array([actor.canvas_to_local(pose[0]), actor.canvas_to_local(pose[1])])

## Raw canvas-pixel hilt and tip of `clip` drawing `index`, in the active form.
func blade_pose(actor: Node2D, clip: String, index: int) -> PackedVector2Array:
	var directory := TRACKS + ("awakening/" if actor.uses_awakened_frames() else "")
	return Blade.pose(directory, clip, index)

func awakened(slot: int) -> bool:
	return slot < actors.size() and actors[slot] != null and actors[slot].form_active()

## Fighter-local point or direction to world, for anything with x, y, facing.
static func world(frame: Variant, local: Vector2) -> Vector2:
	return Vector2(frame.x + local.x * frame.facing, frame.y + local.y)

static func world_dir(frame: Variant, local: Vector2) -> Vector2:
	return Vector2(local.x * frame.facing, local.y)

## Deterministic 0..1 noise so a replayed move always sheds the same particles.
static func rand(seed: int, n: int) -> float:
	var h := (seed * 73856093) ^ (n * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
