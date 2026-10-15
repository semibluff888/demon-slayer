extends Node2D
## Akaza's 破坏杀 effects after the Hinokami Chronicles look: spiky cyan shock
## bursts with a white-hot core, white air-pressure arcs and rings round his
## fists and feet, comet-like air fists, crystal eruptions from the floor, dark
## dust and black rock, the red start-up of every special, and while awakened
## (术式展开·罗针) a snowflake compass under his feet, blue-violet shocks and a
## flickering flame outline. Each technique lives in vfx/akaza/; this node owns
## the layers, particle pools, contact bursts and the shared drawing helpers.
## Shapes follow the move clock; particles are emitted from `consume`, which runs
## after every combat step, so each tick sees the fighters and projectiles
## exactly where combat put them; particles and bursts advance only with the
## presentation time EffectsView passes in, so hitstop, super freeze, pause and
## KO freezes hold the whole picture. Combat state is only ever read.
const Kit = preload("res://scripts/presentation/vfx/akaza/kit.gd")
const Ribbon = preload("res://scripts/presentation/vfx/vfx_ribbon.gd")
const Pool = preload("res://scripts/presentation/vfx/vfx_pool.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const Compass = preload("res://scripts/presentation/vfx/akaza/compass.gd")
const TECHNIQUES := {
	"fist": preload("res://scripts/presentation/vfx/akaza/fist.gd"),
	"kick": preload("res://scripts/presentation/vfx/akaza/kick.gd"),
	"kushiki": preload("res://scripts/presentation/vfx/akaza/kushiki.gd"),
	"kanmuri": preload("res://scripts/presentation/vfx/akaza/kanmuri.gd"),
	"ranshiki": preload("res://scripts/presentation/vfx/akaza/ranshiki.gd"),
	"manyo": preload("res://scripts/presentation/vfx/akaza/manyo.gd"),
	"step_punch": preload("res://scripts/presentation/vfx/akaza/step_punch.gd"),
	"ryusen": preload("res://scripts/presentation/vfx/akaza/ryusen.gd"),
	"hiyu": preload("res://scripts/presentation/vfx/akaza/hiyu.gd"),
	"metsu": preload("res://scripts/presentation/vfx/akaza/metsu.gd"),
	"afterglow": preload("res://scripts/presentation/vfx/akaza/afterglow.gd"),
	"grapple": preload("res://scripts/presentation/vfx/akaza/grapple.gd"),
}
## Every Akaza move and the technique drawing it.
const MOVES := {
	"akaza_5A": "fist", "akaza_2A": "fist", "akaza_jA": "fist", "akaza_5C": "fist", "akaza_2C": "fist", "akaza_jC": "fist",
	"akaza_5AA": "fist",
	"akaza_5B": "kick", "akaza_2B": "kick", "akaza_jB": "kick", "akaza_5D": "kick", "akaza_2D": "kick", "akaza_jD": "kick",
	"akaza_236A": "kushiki", "akaza_236C": "kushiki", "akaza_j236A": "kushiki", "akaza_j236C": "kushiki",
	"akaza_623A": "kanmuri", "akaza_623C": "kanmuri",
	"akaza_214B": "ranshiki", "akaza_214D": "ranshiki",
	"akaza_5AAC": "manyo",
	"akaza_6B": "ryusen",
	"akaza_6C": "step_punch",
	"akaza_j214B": "hiyu", "akaza_j214D": "hiyu",
	"akaza_super": "metsu",
	"akaza_max": "afterglow",
	"akaza_throw": "grapple",
}
var combat: RefCounted
var camera: RefCounted
var actors: Array = []
var glow: Texture2D
## Kept for parity with the other rebuilt effects (unused: Akaza has no blade).
var cut_curves: Dictionary = {}
## Sub-tick reveal for smooth high refresh rates; captures and tests turn it off.
var interpolate: bool = true
var frac: float = 0.0
var time: float = 0.0
var dot: Texture2D
var chunk: Texture2D
var blob: Texture2D
var flake: Texture2D
var band: GradientTexture2D
## Cyan-white sparks thrown off strikes; red ones off the start-up.
var sparks := Pool.new(1, 1, 320)
## Glittering crystal flakes that drift and turn.
var flakes := Pool.new(1, 1, 240)
## Black (and, in eruptions, blue) rock chunks.
var debris := Pool.new(1, 1, 120)
## Dark smoke rolling along the floor.
var dust := Pool.new(1, 1, 90)
var bursts: Array[Dictionary] = []
var layers: Array[Node2D] = []
var techniques: Dictionary = {}
## The awakening (术式展开·罗针): compass, flame outline and their start-up.
var compass: RefCounted
var _ticks: Dictionary = {}
## Live projectiles drawn here, by "owner:instance", as last seen by `consume`.
var _shots: Dictionary = {}
## Local-to-canvas transform of the shape being drawn.
var base := Transform2D.IDENTITY

func _ready() -> void:
	dot = _spark_texture()
	chunk = _chunk_texture()
	blob = _blob_texture()
	flake = _flake_texture()
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
	flakes.fade_in = 0.1
	flakes.fade_out = 0.5
	debris.fade_in = 0.0
	debris.fade_out = 0.3
	dust.fade_in = 0.15
	dust.fade_out = 0.6
	for spec in [["AkazaFloor", -9, false], ["AkazaSigil", -9, true], ["AkazaGlow", -1, true], ["AkazaFront", 0, false], ["AkazaLight", 0, true]]:
		layers.append(_layer(spec[0], spec[1], spec[2]))
	for key: String in TECHNIQUES:
		var technique: RefCounted = TECHNIQUES[key].new()
		technique.vfx = self
		techniques[key] = technique
	compass = Compass.new()
	compass.vfx = self

## Crisp spark: white core, cyan rim.
static func _spark_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length() / 14.0
			var alpha := clampf((1.0 - d) * 4.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.6, 0.92, 1.0).lerp(Color.WHITE, clampf((0.6 - d) * 3.0, 0.0, 1.0)) * Color(1, 1, 1, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## An irregular rock chunk with a lighter top edge; tinted per particle.
static func _chunk_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var corners := PackedVector2Array()
	for n in range(6):
		var a := TAU * n / 6.0 + 0.3
		corners.append(Vector2(16, 16) + Vector2(cos(a), sin(a)) * (9.0 + 5.0 * rand(17, n)))
	for y in range(32):
		for x in range(32):
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(p, corners):
				var shade := 0.55 + 0.45 * clampf((20.0 - y) / 12.0, 0.0, 1.0)
				image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## A soft round puff for smoke.
static func _blob_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var d := Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length() / 30.0
			var alpha := clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha * alpha * (3.0 - 2.0 * alpha)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## A small crystal shard: a bright kite with a white facet.
static func _flake_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var kite := PackedVector2Array([Vector2(16, 2), Vector2(26, 14), Vector2(16, 30), Vector2(7, 15)])
	var facet := PackedVector2Array([Vector2(16, 4), Vector2(23, 14), Vector2(16, 17)])
	for y in range(32):
		for x in range(32):
			var p := Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(p, facet):
				image.set_pixel(x, y, Color(1, 1, 1, 1))
			elif Geometry2D.is_point_in_polygon(p, kite):
				image.set_pixel(x, y, Color(0.75, 0.95, 1.0, 0.9))
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
	for pool in [sparks, flakes, debris, dust]:
		pool.clear()
	bursts.clear()
	_ticks.clear()
	_shots.clear()
	for each: RefCounted in techniques.values():
		each.reset()
	compass.reset()
	time = 0.0
	redraw()

func redraw() -> void:
	for layer in layers:
		layer.queue_redraw()

# --- Simulation -------------------------------------------------------------------

func advance(delta: float) -> void:
	time += delta
	for pool in [sparks, flakes, debris, dust]:
		pool.advance(delta)
	for burst: Dictionary in bursts:
		burst.age += delta
	bursts = bursts.filter(func(b: Dictionary) -> bool: return b.age < b.life)
	redraw()

func consume(events: Array) -> void:
	for f in combat.fighters:
		_emit_fighter(f)
	_track_shots(events)
	for each: RefCounted in techniques.values():
		each.linger(combat.fighters, actors)
	compass.consume(events, combat.fighters, actors)
	for event: Dictionary in events:
		if event.type == "round_end":
			break
		if event.type == "throw" and event.has("attacker"):
			var thrower = combat.fighters[event.attacker]
			var throw_move: Resource = combat.definition(thrower).throw_move
			if handles(throw_move):
				techniques.grapple.slam(event, thrower, awakened(event.attacker))
			continue
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

## Projectiles: trail particles every tick, and a burst where an air shot meets the
## floor (it vanishes there without a contact event).
func _track_shots(events: Array) -> void:
	var live := {}
	for p: Dictionary in combat.projectiles:
		var move: Resource = combat.moves.get(str(p.move))
		if not handles(move):
			continue
		var key := "%d:%d" % [int(p.owner), int(p.instance)]
		live[key] = {"x": float(p.x), "y": float(p.y), "vx": float(p.vx), "vy": float(p.get("vy", 0.0)), "move": str(p.move),
			"facing": int(p.facing), "owner": int(p.owner), "instance": int(p.instance), "life": int(p.life)}
		# Only a tick that moved the shot sheds a trail (freezes call this too).
		var seen: Dictionary = _shots.get(key, {})
		if seen.is_empty() or int(seen.life) != int(p.life):
			technique(move).emit_shot(live[key], awakened(int(p.owner)))
	for key: String in _shots:
		if live.has(key):
			continue
		var shot: Dictionary = _shots[key]
		var struck := events.any(func(e: Dictionary) -> bool: return e.type in ["hit", "block"] and int(e.get("instance", -1)) == int(shot.instance))
		if not struck:
			technique(combat.moves[shot.move]).shot_ended(shot, awakened(int(shot.owner)))
	_shots = live

# --- Particle bursts --------------------------------------------------------------

## Sparks flung from `at`; `bias` leans them one way.
func spark_burst(at: Vector2, count: int, bias: Vector2, slow: float, fast: float, seed: int, tint: Color = Kit.ICE) -> void:
	for n in range(count):
		var direction := (Vector2.from_angle(rand(seed, n) * TAU) + bias * 0.9).normalized()
		sparks.spawn(at, direction * lerpf(slow, fast, rand(seed, n + 50)), lerpf(0.16, 0.38, rand(seed, n + 100)), lerpf(1.5, 3.0, rand(seed, n + 150)), 0, tint,
			220.0, 1.4, 0.0, 0.0, 0.6, 2.2)

## Crystal flakes spinning out of `at`, drifting slowly.
func flake_burst(at: Vector2, count: int, speed: float, seed: int, awakened_form: bool, lift: float = 30.0) -> void:
	for n in range(count):
		var direction := Vector2.from_angle(rand(seed, n) * TAU)
		var tint := Kit.CRYSTAL_LIGHT.lerp(Kit.tone(awakened_form), 0.35 * rand(seed, n + 7))
		flakes.spawn(at + direction * 4.0, direction * speed * lerpf(0.3, 1.0, rand(seed, n + 20)) + Vector2(0.0, -lift),
			lerpf(0.35, 0.75, rand(seed, n + 40)), lerpf(2.2, 4.2, rand(seed, n + 50)), 0, tint, 40.0, 1.8, rand(seed, n + 60) * TAU, rand(seed, n + 70) * 10.0 - 5.0, 0.7)

## Rock chunks thrown up from the floor or a struck body; `blue` paints them as
## the crystal rubble of an eruption.
func debris_burst(at: Vector2, count: int, bias: Vector2, seed: int, blue: bool = false) -> void:
	for n in range(count):
		var direction := (Vector2(rand(seed, n) * 2.0 - 1.0, -lerpf(0.5, 1.0, rand(seed, n + 10))) + bias).normalized()
		var tint := Kit.CYAN_DEEP.lerp(Kit.CRYSTAL, 0.4 * rand(seed, n + 15)) if blue and n % 2 == 0 else Color(0.16, 0.16, 0.18)
		debris.spawn(at, direction * lerpf(90.0, 230.0, rand(seed, n + 20)), lerpf(0.4, 0.75, rand(seed, n + 30)), lerpf(3.0, 7.0, rand(seed, n + 40)), 0,
			tint, 420.0, 0.4, rand(seed, n + 50) * TAU, rand(seed, n + 60) * 14.0 - 7.0)

## Dark smoke rolling out along the floor from `at`, leaning `bias.x`.
func dust_burst(at: Vector2, count: int, bias: Vector2, seed: int, size: float = 1.0) -> void:
	for n in range(count):
		var side := rand(seed, n) * 2.0 - 1.0
		var velocity := Vector2(side * 60.0 + bias.x * 90.0, -lerpf(6.0, 26.0, rand(seed, n + 10)) + bias.y * 40.0) * lerpf(0.5, 1.0, rand(seed, n + 20))
		dust.spawn(at + Vector2(side * 6.0, -2.0), velocity, lerpf(0.4, 0.65, rand(seed, n + 30)), lerpf(10.0, 18.0, rand(seed, n + 40)) * size, 0,
			Color(Kit.DUST, lerpf(0.35, 0.55, rand(seed, n + 50))), -10.0, 2.6, 0.0, 0.0, 2.2)

## Contact: a spiky shock burst whose first frame is already full size (hitstop
## holds it there), white pressure rings, rays on big hits, sparks, flakes and
## rock. `scale` grows everything (light 0.5, heavy 0.75, special 1, supers more).
func strike(event: Dictionary, attacker: RefCounted, scale: float, awakened_form: bool, rays_too: bool = false) -> void:
	var at: Vector2 = event.position
	var facing := float(attacker.facing)
	var seed: int = attacker.attack_instance * 977 + int(event.get("segment", 0)) * 31 + attacker.slot * 13
	if event.type == "block":
		bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.16, "size": 12.0, "squash": 1.4, "facing": facing, "seed": seed, "awake": awakened_form})
		bursts.append({"kind": "shock", "at": at, "age": 0.0, "life": 0.1, "size": 9.0, "facing": facing, "seed": seed, "awake": awakened_form, "pale": true})
		spark_burst(at, 8, Vector2(-facing, -0.5), 60.0, 140.0, seed, Kit.ICE)
		return
	bursts.append({"kind": "shock", "at": at, "age": 0.0, "life": 0.13 + 0.05 * minf(scale, 1.5), "size": 10.0 + 15.0 * scale, "facing": facing, "seed": seed,
		"awake": awakened_form})
	bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.18, "size": 10.0 + 12.0 * scale, "squash": 1.5, "facing": facing, "seed": seed + 1, "awake": awakened_form})
	spark_burst(at, int(10 + 16 * scale), Vector2(facing, -0.3), 90.0, 240.0, seed)
	if scale >= 0.75:
		flake_burst(at, int(4 + 6 * scale), 70.0, seed + 3, awakened_form)
	if scale >= 1.0 or rays_too:
		bursts.append({"kind": "rays", "at": at, "age": 0.0, "life": 0.2, "size": 70.0 * scale, "facing": facing, "seed": seed + 2, "awake": awakened_form})
		bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.24, "size": 18.0 + 16.0 * scale, "squash": 0.9, "facing": facing, "seed": seed + 4, "awake": awakened_form})
		debris_burst(at, int(3 + 3 * scale), Vector2(facing * 0.5, 0.0), seed + 5)

# --- Drawing ---------------------------------------------------------------------

func _paint(canvas: Node2D, layer: int) -> void:
	if camera == null or combat == null:
		return
	if combat.phase in ["fight", "round_end"]:
		compass.draw_all(canvas, layer, combat.fighters, actors)
		for f in combat.fighters:
			if handles(f.move) and combat.presents_attack(f.slot) and f.slot < actors.size():
				set_base(canvas, frame_transform(f.x, f.y, f.facing))
				technique(f.move).draw(canvas, layer, f, actors[f.slot])
		for p: Dictionary in combat.projectiles:
			var move: Resource = combat.moves.get(str(p.move))
			if handles(move):
				var x: float = float(p.x) + float(p.vx) * frac
				var y: float = float(p.y) + float(p.get("vy", 0.0)) * frac
				set_base(canvas, frame_transform(x, y, float(p.facing)))
				technique(move).draw_shot(canvas, layer, p, awakened(int(p.owner)))
		for each: RefCounted in techniques.values():
			each.draw_lingering(canvas, layer)
	for burst: Dictionary in bursts:
		_draw_burst(canvas, layer, burst)
	canvas.draw_set_transform(Vector2.ZERO)
	var to_screen := Callable(camera, "point")
	match layer:
		Kit.FRONT:
			dust.draw(canvas, blob, to_screen, camera.zoom)
			debris.draw(canvas, chunk, to_screen, camera.zoom)
		Kit.LIGHT:
			sparks.draw(canvas, dot, to_screen, camera.zoom)
			flakes.draw(canvas, flake, to_screen, camera.zoom)

func _draw_burst(canvas: Node2D, layer: int, burst: Dictionary) -> void:
	var k: float = burst.age / burst.life
	set_base(canvas, Transform2D(0.0, Vector2(camera.zoom * float(burst.facing), camera.zoom), 0.0, camera.point(burst.at)))
	var seed: int = burst.seed
	var awake: bool = burst.get("awake", false)
	match burst.kind:
		"shock":
			var pop := 1.0 - pow(1.0 - clampf(burst.age / 0.04, 0.0, 1.0), 3.0)
			var alpha := 1.0 - smoothstep(0.45, 1.0, k)
			shock(canvas, layer, Vector2.ZERO, float(burst.size) * (0.78 + 0.22 * pop + 0.15 * k), seed, alpha, awake, 14, burst.get("pale", false))
		"ring":
			var grow := 1.0 - pow(1.0 - k, 2.0)
			var radius: float = float(burst.size) * (0.6 + 0.8 * grow)
			ring(canvas, layer, Vector2.ZERO, Vector2(radius, radius * float(burst.squash) * 0.62), 0.0, 1.0 - k, 2.2, awake)
		"rays":
			if layer == Kit.LIGHT:
				rays(canvas, Vector2.ZERO, seed, 14, float(burst.size) * (0.6 + 0.4 * k), 1.0 - k, Kit.tone(awake))
		_:
			var owner: RefCounted = burst.get("technique")
			if owner != null:
				owner.draw_burst(canvas, layer, burst, k)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## Canvas transform of a fighter-local frame at world (x, y) facing `facing`.
func frame_transform(x: float, y: float, facing: float) -> Transform2D:
	return Transform2D(0.0, Vector2(camera.zoom * facing, camera.zoom), 0.0, camera.point(Vector2(x, y)))

## A canvas transform at a world point without mirroring, for floor decals.
func world_transform(at: Vector2, facing: float = 1.0) -> Transform2D:
	return Transform2D(0.0, Vector2(camera.zoom * facing, camera.zoom), 0.0, camera.point(at))

func set_base(canvas: Node2D, transform: Transform2D) -> void:
	base = transform
	canvas.draw_set_transform_matrix(base)

## A star polygon round `at`: `spikes` long points alternating with short ones,
## jittered by `seed`; `flare` stretches every third point into a flame tongue.
static func jagged(at: Vector2, radius: float, spikes: int, seed: int, flare: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var turn := rand(seed, 70) * TAU
	var count := spikes * 2
	for n in range(count):
		var a := turn + TAU * (n + (rand(seed, n + 200) - 0.5) * 0.6) / count
		var long := n % 2 == 0
		var r := radius * (lerpf(0.8, 1.15, rand(seed, n)) if long else lerpf(0.42, 0.58, rand(seed, n)))
		if long and (n >> 1) % 3 == 0:
			r *= lerpf(1.0, 1.0 + 0.45 * flare, rand(seed, n + 90))
		points.append(at + Vector2(cos(a), sin(a)) * r)
	return points

## The signature shock: a deep jagged outer burst, a cyan (violet when awakened)
## body and a white-hot core, soft glow under the fighters and additive light and
## thin spikes over them. `pale` keeps a guarded hit small and cool.
func shock(canvas: Node2D, layer: int, at: Vector2, radius: float, seed: int, alpha: float, awakened_form: bool, spikes: int = 14, pale: bool = false) -> void:
	if alpha <= 0.01 or radius < 1.0:
		return
	var tone := Kit.ICE if pale else Kit.tone(awakened_form)
	var edge := Kit.CYAN_DEEP if pale else Kit.deep(awakened_form)
	match layer:
		Kit.GLOW:
			if glow != null:
				canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * radius * 2.4, Vector2.ONE * radius * 4.8), false, Color(edge, 0.42 * alpha))
		Kit.FRONT:
			canvas.draw_colored_polygon(jagged(at, radius, spikes, seed, 1.0), Color(edge, 0.85 * alpha))
			canvas.draw_colored_polygon(jagged(at, radius * 0.78, spikes, seed + 1, 0.8), Color(tone, 0.95 * alpha))
			canvas.draw_colored_polygon(jagged(at, radius * 0.44, maxi(6, spikes >> 1), seed + 2, 0.5), Color(Kit.WHITE, alpha))
		Kit.LIGHT:
			if glow != null:
				canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * radius * 1.3, Vector2.ONE * radius * 2.6), false, Color(tone, 0.6 * alpha))
			for n in range(8):
				var direction := Vector2.from_angle(TAU * n / 8.0 + rand(seed, n + 300) * 0.6)
				var reach := radius * lerpf(1.1, 1.6, rand(seed, n + 310))
				Ribbon.draw(canvas, PackedVector2Array([at + direction * radius * 0.5, at + direction * reach]), PackedFloat32Array([1.6, 0.0]),
					PackedColorArray([Color(Kit.ICE, 0.8 * alpha), Color(Kit.ICE, 0.0)]), band)

## A white air-pressure ring (an ellipse round `center`, rotated), thicker on its
## leading side, with a faint coloured rim.
func ring(canvas: Node2D, layer: int, center: Vector2, radii: Vector2, rotation: float, alpha: float, thickness: float, awakened_form: bool) -> void:
	if alpha <= 0.01 or radii.x < 0.5:
		return
	if layer != Kit.FRONT and layer != Kit.LIGHT:
		return
	var points := Ribbon.arc(center, radii, -PI, PI, 33, rotation)
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(points.size()):
		var lead := 0.5 + 0.5 * cos(-PI + TAU * n / 32.0)
		widths.append(thickness * lerpf(0.35, 1.0, lead) * (1.6 if layer == Kit.LIGHT else 1.0))
		tint.append(Color(Kit.WHITE if layer == Kit.FRONT else Kit.tone(awakened_form), (0.6 if layer == Kit.FRONT else 0.35) * alpha * lerpf(0.4, 1.0, lead)))
	Ribbon.draw(canvas, points, widths, tint, band)

## A crescent along `path` revealed to `head` and eroding behind `tail`: a white
## body with a coloured rim (the pressure arcs of kicks and swings).
func crescent(canvas: Node2D, layer: int, path: RefCounted, head: float, tail: float, alpha: float, awakened_form: bool, count: int = 24) -> void:
	if head <= 0.02 or tail >= 1.0 or alpha <= 0.01:
		return
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(count):
		var u := head * n / (count - 1.0)
		points.append(path.point(u, 0.0))
		widths.append(path.width(u))
		tint.append(Color(1, 1, 1, alpha * smoothstep(tail - 0.2, tail + 0.04, u)))
	match layer:
		Kit.GLOW:
			Ribbon.draw(canvas, points, _scaled(widths, 2.6), _tinted(tint, Color(Kit.deep(awakened_form), 0.32)), band)
		Kit.FRONT:
			Ribbon.draw(canvas, points, widths, _tinted(tint, Color(Kit.WHITE, 0.82)), band)
		Kit.LIGHT:
			Ribbon.draw(canvas, points, _scaled(widths, 1.5), _tinted(tint, Color(Kit.tone(awakened_form), 0.5)), band)

## A long, thin, tapered line of light from `from` to `to` (dash flashes).
func needle(canvas: Node2D, layer: int, from: Vector2, to: Vector2, width: float, alpha: float, awakened_form: bool) -> void:
	if alpha <= 0.01 or from.distance_to(to) < 1.0:
		return
	var points := PackedVector2Array([from, from.lerp(to, 0.72), to])
	var widths := PackedFloat32Array([width * 0.25, width, 0.0])
	match layer:
		Kit.GLOW:
			Ribbon.draw(canvas, points, _scaled(widths, 3.0), _tinted(PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]), Color(Kit.deep(awakened_form), 0.35 * alpha)), band)
		Kit.FRONT:
			Ribbon.draw(canvas, points, widths, PackedColorArray([Color(Kit.WHITE, 0.4 * alpha), Color(Kit.WHITE, alpha), Color(Kit.WHITE, alpha)]), band)
		Kit.LIGHT:
			Ribbon.draw(canvas, points, _scaled(widths, 1.8), PackedColorArray([Color(Kit.tone(awakened_form), 0.2 * alpha), Color(Kit.tone(awakened_form), 0.6 * alpha),
				Color(Kit.ICE, 0.6 * alpha)]), band)

## A swirl of air round `at`: three spiral strokes turning by `spin`.
func vortex(canvas: Node2D, layer: int, at: Vector2, radius: float, spin: float, alpha: float, awakened_form: bool) -> void:
	if alpha <= 0.01 or (layer != Kit.FRONT and layer != Kit.LIGHT):
		return
	for k in range(3):
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		var tint := PackedColorArray()
		for n in range(12):
			var u := n / 11.0
			var a := spin + TAU * k / 3.0 + u * 2.4
			var r := radius * lerpf(0.35, 1.0, u)
			points.append(at + Vector2(cos(a) * r * 0.55, sin(a) * r))
			widths.append(lerpf(0.4, 2.4, sin(u * PI)))
			tint.append(Color(Kit.WHITE if layer == Kit.FRONT else Kit.tone(awakened_form), alpha * sin(u * PI) * (0.75 if layer == Kit.FRONT else 0.5)))
		Ribbon.draw(canvas, points, widths, tint, band)

## Long thin rays radiating from `at` (additive layers only).
func rays(canvas: Node2D, at: Vector2, seed: int, count: int, length: float, alpha: float, tint: Color, spread: float = TAU, heading: float = 0.0) -> void:
	for n in range(count):
		var direction := Vector2.from_angle(heading - spread * 0.5 + spread * (n + rand(seed, n + 90) * 0.6) / count)
		var reach := length * lerpf(0.5, 1.0, rand(seed, n + 110))
		Ribbon.draw(canvas, PackedVector2Array([at + direction * reach * 0.15, at + direction * reach * 0.55, at + direction * reach]),
			PackedFloat32Array([2.2, 1.3, 0.0]), PackedColorArray([Color(Kit.ICE, 0.8 * alpha), Color(tint, 0.55 * alpha), Color(tint, 0.0)]), band)

## Dark smoke-free floor scar: an elliptical crater with cracks (FLOOR layer).
func crater(canvas: Node2D, at: Vector2, radius: float, alpha: float, seed: int) -> void:
	if alpha <= 0.01:
		return
	var points := PackedVector2Array()
	for n in range(18):
		var a := TAU * n / 18.0
		var r := radius * lerpf(0.82, 1.08, rand(seed, n))
		points.append(at + Vector2(cos(a) * r, sin(a) * r * Kit.FLOOR_SQUASH))
	canvas.draw_colored_polygon(points, Color(Kit.CRATER, 0.6 * alpha))
	var inner := PackedVector2Array()
	for p in points:
		inner.append(at + (p - at) * 0.55)
	canvas.draw_colored_polygon(inner, Color(0.0, 0.0, 0.0, 0.35 * alpha))
	for n in range(7):
		var a := TAU * (n + rand(seed, n + 40) * 0.5) / 7.0
		var from := at + Vector2(cos(a) * radius * 0.9, sin(a) * radius * 0.9 * Kit.FLOOR_SQUASH)
		var to := at + Vector2(cos(a) * radius * lerpf(1.3, 1.8, rand(seed, n + 50)), sin(a) * radius * lerpf(1.3, 1.8, rand(seed, n + 50)) * Kit.FLOOR_SQUASH)
		canvas.draw_line(from, to, Color(Kit.CRATER, 0.7 * alpha), 1.0, true)

## A dark furrow torn along the floor from `from_x` to `to_x` (FLOOR layer).
func trench(canvas: Node2D, from_x: float, to_x: float, alpha: float, seed: int) -> void:
	if absf(to_x - from_x) < 4.0 or alpha <= 0.01:
		return
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(14):
		var u := n / 13.0
		points.append(Vector2(lerpf(from_x, to_x, u), -0.5 + (rand(seed, n) - 0.5) * 1.2))
		widths.append(7.0 * sin(clampf(u, 0.04, 0.96) * PI) * lerpf(0.7, 1.15, rand(seed, n + 20)))
		tint.append(Color(Kit.CRATER, 0.6 * alpha))
	Ribbon.draw(canvas, points, widths, tint, band)

## The red start-up of a special, strength `k` (fighter-local): a red glow round
## his body with his drawing flushed red, a ring of black-red ink spikes and two
## long red needles crossing through him.
func activation(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D, k: float, seed: int, centre: Vector2 = Vector2(0.0, -40.0)) -> void:
	if k <= 0.01:
		return
	match layer:
		Kit.GLOW:
			if glow != null:
				canvas.draw_texture_rect(glow, Rect2(centre - Vector2.ONE * 46.0, Vector2.ONE * 92.0), false, Color(Kit.BLOOD, 0.5 * k))
		Kit.FRONT:
			for n in range(12):
				var a := TAU * (n + rand(seed, n) * 0.6) / 12.0
				var direction := Vector2.from_angle(a)
				var from := centre + direction * 15.0
				var to := centre + direction * lerpf(28.0, 44.0, rand(seed, n + 20)) * lerpf(0.7, 1.0, k)
				var side := direction.orthogonal() * lerpf(2.0, 3.6, rand(seed, n + 40))
				canvas.draw_colored_polygon(PackedVector2Array([from - side, to, from + side]), Color(Kit.INK, 0.8 * k))
		Kit.LIGHT:
			if glow != null:
				canvas.draw_texture_rect(glow, Rect2(centre - Vector2.ONE * 32.0, Vector2.ONE * 64.0), false, Color(Kit.RED, 0.65 * k))
			body_flash(canvas, f, actor, Color(Kit.RED_HOT, 0.45 * k))
			for side: float in [-1.0, 1.0]:
				var axis := Vector2.from_angle(-PI * 0.5 + side * 0.62)
				Ribbon.draw(canvas, PackedVector2Array([centre - axis * 110.0, centre, centre + axis * 110.0]), PackedFloat32Array([0.0, 1.6, 0.0]),
					PackedColorArray([Color(Kit.RED_HOT, 0.0), Color(Kit.RED_HOT, k), Color(Kit.RED_HOT, 0.0)]), band)

## Crystal slabs breaking out of the floor round `at` (local, y = floor): a back
## row under the fighters (FLOOR) and a front row over them (FRONT), each slab a
## leaning, pointed plate lit from above with dark grain and outline; `grow`
## raises and lowers them.
func crystals(canvas: Node2D, layer: int, at: Vector2, size: float, grow: float, seed: int, awakened_form: bool, count: int = 8) -> void:
	if grow <= 0.01:
		return
	var tint := Kit.CRYSTAL.lerp(Kit.tone(awakened_form), 0.25)
	if layer == Kit.GLOW and glow != null:
		canvas.draw_texture_rect(glow, Rect2(at + Vector2(-size * 1.6, -size * 2.1), Vector2(size * 3.2, size * 3.2)), false, Color(Kit.tone(awakened_form), 0.4 * grow))
		return
	if layer != Kit.FLOOR and layer != Kit.FRONT:
		return
	for n in range(count):
		var back := n % 2 == 0
		if back != (layer == Kit.FLOOR):
			continue
		var u := (n + 0.5) / count
		var x := at.x + lerpf(-size, size, u) + (rand(seed, n + 5) - 0.5) * size * 0.15
		var y := at.y + (-1.5 if back else 1.5)
		var h := size * lerpf(0.6, 1.25, rand(seed, n)) * grow * (1.0 - 0.45 * absf(u - 0.5) * 2.0)
		var w := size * lerpf(0.28, 0.42, rand(seed, n + 10))
		var lean := (u - 0.5) * 0.9 + (rand(seed, n + 20) - 0.5) * 0.3
		var up := Vector2(sin(lean), -cos(lean))
		var side := Vector2(cos(lean), sin(lean))
		var b0 := Vector2(x, y) - side * w * 0.5
		var b1 := Vector2(x, y) + side * w * 0.5
		var t1 := b1 + up * h * lerpf(0.75, 1.0, rand(seed, n + 30))
		var t0 := b0 + up * h * lerpf(0.85, 1.05, rand(seed, n + 40))
		var tip := (t0 + t1) * 0.5 + up * h * 0.18
		var plate := PackedVector2Array([b0, b1, t1, tip, t0])
		var dark := tint.darkened(0.3)
		canvas.draw_polygon(plate, PackedColorArray([dark, dark, tint, Kit.CRYSTAL_LIGHT, tint]))
		for g in range(2):
			var s := lerpf(0.3, 0.7, (g + rand(seed, n + 50 + g) * 0.5) / 2.0)
			canvas.draw_line(b0.lerp(b1, s), t0.lerp(t1, s) - up * 2.0, Color(Kit.CRYSTAL_LINE, 0.45), 0.7, true)
		var outline := plate.duplicate()
		outline.append(plate[0])
		canvas.draw_polyline(outline, Color(Kit.CRYSTAL_LINE, 0.9), 0.9, true)

## The 罗针 compass: a six-fold snowflake laid flat on the floor round `center`
## (local units, y = floor), revealed from the middle outward by `reveal` and
## turned by `spin`. Glowing lines on the SIGIL layer; a soft pool of light
## under them.
func compass_shape(canvas: Node2D, layer: int, center: Vector2, radius: float, reveal: float, spin: float, color: Color, alpha: float) -> void:
	if layer != Kit.SIGIL or alpha <= 0.01 or reveal <= 0.0 or radius < 2.0:
		return
	var floor_at := func(local: Vector2) -> Vector2:
		var p := local.rotated(spin)
		return center + Vector2(p.x, p.y * Kit.FLOOR_SQUASH)
	var stage := func(from: float, to: float) -> float:
		return clampf((reveal - from) / (to - from), 0.0, 1.0)
	if glow != null:
		canvas.draw_texture_rect(glow, Rect2(center - Vector2(radius * 1.15, radius * 1.15 * Kit.FLOOR_SQUASH),
			Vector2(radius * 2.3, radius * 2.3 * Kit.FLOOR_SQUASH)), false, Color(color, 0.28 * alpha * stage.call(0.0, 0.5)))
	var line := Color(color, 0.85 * alpha)
	var thin := Color(color, 0.55 * alpha)
	# Centre hexagon.
	var hexagon: float = stage.call(0.0, 0.15)
	if hexagon > 0.0:
		var points := PackedVector2Array()
		for n in range(7):
			points.append(floor_at.call(Vector2.from_angle(TAU * n / 6.0) * radius * 0.16 * hexagon))
		canvas.draw_polyline(points, line, 1.4, true)
	for n in range(6):
		var axis := Vector2.from_angle(TAU * n / 6.0 + PI / 6.0)
		var side := axis.orthogonal()
		# Main spoke growing outward.
		var grow: float = stage.call(0.1, 0.6)
		if grow > 0.0:
			canvas.draw_line(floor_at.call(axis * radius * 0.16), floor_at.call(axis * radius * lerpf(0.16, 1.0, grow)), line, 1.3, true)
		# A rhombus on the spoke.
		var rhombus: float = stage.call(0.4, 0.6)
		if rhombus > 0.0:
			var mid := axis * radius * 0.41
			var points := PackedVector2Array([floor_at.call(mid - axis * radius * 0.09), floor_at.call(mid + side * radius * 0.05 * rhombus),
				floor_at.call(mid + axis * radius * 0.09), floor_at.call(mid - side * radius * 0.05 * rhombus), floor_at.call(mid - axis * radius * 0.09)])
			canvas.draw_polyline(points, line, 1.1, true)
		# Snowflake branches near the tip.
		var branch: float = stage.call(0.6, 0.85)
		if branch > 0.0:
			for s: float in [-1.0, 1.0]:
				var root := axis * radius * 0.7
				canvas.draw_line(floor_at.call(root), floor_at.call(root + (axis + side * s).normalized() * radius * 0.13 * branch), thin, 1.0, true)
		# A small hexagon at the tip.
		var tip: float = stage.call(0.7, 0.9)
		if tip > 0.0:
			var points := PackedVector2Array()
			for k in range(7):
				points.append(floor_at.call(axis * radius * 0.88 + Vector2.from_angle(TAU * k / 6.0) * radius * 0.06 * tip))
			canvas.draw_polyline(points, thin, 1.0, true)
		# Secondary spokes between the main ones.
		var secondary: float = stage.call(0.55, 0.8)
		if secondary > 0.0:
			var between := Vector2.from_angle(TAU * n / 6.0)
			canvas.draw_line(floor_at.call(between * radius * 0.55), floor_at.call(between * radius * lerpf(0.55, 0.8, secondary)), thin, 1.0, true)
	# Inner ring, then the double outer ring, drawn round as they appear.
	for spec in [[0.55, 0.35, 0.6, 1.1], [1.0, 0.75, 1.0, 1.4], [0.92, 0.8, 1.0, 0.9]]:
		var k: float = stage.call(spec[1], spec[2])
		if k <= 0.0:
			continue
		var points := PackedVector2Array()
		var count := maxi(2, int(48 * k) + 1)
		for m in range(count):
			points.append(floor_at.call(Vector2.from_angle(TAU * k * m / (count - 1)) * radius * float(spec[0])))
		canvas.draw_polyline(points, line if spec[3] > 1.0 else thin, float(spec[3]), true)

## The fighter's own drawing flashed in `color` (additive layers only).
func body_flash(canvas: Node2D, f: RefCounted, actor: Node2D, color: Color) -> void:
	if actor.texture == null or color.a <= 0.01:
		return
	canvas.draw_set_transform(camera.point(Vector2(f.x, f.y)), 0, Vector2(camera.zoom * actor.pose_facing(), camera.zoom))
	canvas.draw_texture_rect(actor.texture, actor.sprite_rect(), false, color)
	canvas.draw_set_transform_matrix(base)

## A flickering flame outline: the fighter's drawing repeated round itself in
## `color`, leaning upward, so only a halo shows past the body (SIGIL layer).
func aura(canvas: Node2D, f: RefCounted, actor: Node2D, color: Color, seed: int) -> void:
	if actor.texture == null or color.a <= 0.01:
		return
	var rect: Rect2 = actor.sprite_rect()
	for n in range(8):
		var a := TAU * n / 8.0
		var offset := Vector2(cos(a) * 1.6, sin(a) * 1.3 - lerpf(0.6, 2.2, rand(seed, n)))
		canvas.draw_set_transform(camera.point(Vector2(f.x, f.y)) + offset * camera.zoom, 0, Vector2(camera.zoom * actor.pose_facing(), camera.zoom))
		canvas.draw_texture_rect(actor.texture, rect, false, Color(color, color.a * lerpf(0.55, 1.0, rand(seed, n + 20))))
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

## Deterministic 0..1 noise (the same hash as the other rebuilt effects).
static func rand(seed: int, n: int) -> float:
	var h := (seed * 73856093) ^ (n * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
