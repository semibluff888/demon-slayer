extends Node2D
## Nezuko's 血鬼术·爆血 effects after the Hinokami Chronicles look: pink blood
## flame with a white-hot core and torn crimson edges, claw strokes in threes,
## flakes of burning blood, white air arcs and manga impact stars, the blood that
## gathers in a ring of black-red ink before every special, pillars, whirls and a
## dome of fire for the supers, dark dust, black rock and scorched floors; in her
## demon form (鬼化) the fire turns a redder crimson and a flame outline clings to
## her. Each technique lives in vfx/nezuko/; this node owns the layers, particle
## pools, contact bursts and the shared drawing helpers. Shapes follow the move
## clock; particles are emitted from `consume`, which runs after every combat
## step, so each tick sees the fighters exactly where combat put them; particles
## and bursts advance only with the presentation time EffectsView passes in, so
## hitstop, super freeze, pause and KO freezes hold the whole picture. Combat
## state is only ever read.
const Kit = preload("res://scripts/presentation/vfx/nezuko/kit.gd")
const Ribbon = preload("res://scripts/presentation/vfx/vfx_ribbon.gd")
const Pool = preload("res://scripts/presentation/vfx/vfx_pool.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const Demon = preload("res://scripts/presentation/vfx/nezuko/demon.gd")
## Baked textures (tools/build_nezuko_vfx_art.py); rock chunks are Akaza's.
const ART := "res://art/effects/nezuko/"
const ROCKS := "res://art/effects/akaza/rocks.png"
## Rows of flame-strip.png / claw-strip.png: 4 pink variants, then 4 crimson.
const STRIP_ROWS := 8.0
const TECHNIQUES := {
	"claw": preload("res://scripts/presentation/vfx/nezuko/claw.gd"),
	"kick": preload("res://scripts/presentation/vfx/nezuko/kick.gd"),
	"renzoku": preload("res://scripts/presentation/vfx/nezuko/renzoku.gd"),
	"kakato": preload("res://scripts/presentation/vfx/nezuko/kakato.gd"),
	"slide": preload("res://scripts/presentation/vfx/nezuko/slide.gd"),
	"blood_kick": preload("res://scripts/presentation/vfx/nezuko/blood_kick.gd"),
	"rising_kick": preload("res://scripts/presentation/vfx/nezuko/rising_kick.gd"),
	"spinning_kick": preload("res://scripts/presentation/vfx/nezuko/spinning_kick.gd"),
	"dive": preload("res://scripts/presentation/vfx/nezuko/dive.gd"),
	"air_spin": preload("res://scripts/presentation/vfx/nezuko/air_spin.gd"),
	"bakketsu": preload("res://scripts/presentation/vfx/nezuko/bakketsu.gd"),
	"kakato_max": preload("res://scripts/presentation/vfx/nezuko/kakato_max.gd"),
	"grapple": preload("res://scripts/presentation/vfx/nezuko/grapple.gd"),
}
## Every Nezuko move and the technique drawing it.
const MOVES := {
	"nezuko_5A": "claw", "nezuko_2A": "claw", "nezuko_jA": "claw", "nezuko_5C": "claw", "nezuko_2C": "claw", "nezuko_jC": "claw",
	"nezuko_5B": "kick", "nezuko_2B": "kick", "nezuko_jB": "kick", "nezuko_5D": "kick", "nezuko_2D": "kick", "nezuko_jD": "kick",
	"nezuko_5BB": "renzoku", "nezuko_5BBD": "renzoku",
	"nezuko_6B": "kakato",
	"nezuko_3D": "slide",
	"nezuko_236A": "blood_kick", "nezuko_236C": "blood_kick",
	"nezuko_623A": "rising_kick", "nezuko_623C": "rising_kick",
	"nezuko_214B": "spinning_kick", "nezuko_214D": "spinning_kick",
	"nezuko_j236A": "dive", "nezuko_j236C": "dive",
	"nezuko_j214B": "air_spin", "nezuko_j214D": "air_spin",
	"nezuko_super": "bakketsu",
	"nezuko_max": "kakato_max",
	"nezuko_throw": "grapple",
}
var combat: RefCounted
var camera: RefCounted
var actors: Array = []
var glow: Texture2D
## Kept for parity with the other rebuilt effects (unused: Nezuko has no blade).
var cut_curves: Dictionary = {}
## Sub-tick reveal for smooth high refresh rates; captures and tests turn it off.
var interpolate: bool = true
var frac: float = 0.0
var time: float = 0.0
var dot: Texture2D
var blob: Texture2D
## Contact bursts: pink (normal) and crimson (鬼化), 4 variants x 2 stages.
var blaze_art: Array[Texture2D] = []
var flame_strip: Texture2D
var claw_strip: Texture2D
var flake_sheet: Texture2D
var star_sheet: Texture2D
var rocks: Texture2D
var band: GradientTexture2D
## Pink-white embers thrown off strikes and the start-up.
var embers := Pool.new(1, 1, 320)
## Torn flakes of burning blood that tumble and drift (flakes.png, 4 x 4).
var flakes := Pool.new(4, 4, 240)
## Rock chunks: dark stone, or lit pink from below by the fire.
var debris := Pool.new(4, 4, 120)
## Dark smoke rolling along the floor.
var dust := Pool.new(1, 1, 90)
var bursts: Array[Dictionary] = []
var layers: Array[Node2D] = []
var techniques: Dictionary = {}
## The demon form (鬼化·爆血): its start-up and the flame outline.
var demon: RefCounted
## The slot whose drawing scale `body_scale` reports while a technique runs.
var focus: int = -1
## Local-to-canvas transform of the shape being drawn.
var base := Transform2D.IDENTITY

func _ready() -> void:
	dot = _ember_texture()
	blob = _blob_texture()
	for palette in ["pink", "crimson"]:
		blaze_art.append(load(ART + "blaze-%s.png" % palette))
	flame_strip = load(ART + "flame-strip.png")
	claw_strip = load(ART + "claw-strip.png")
	flake_sheet = load(ART + "flakes.png")
	star_sheet = load(ART + "star.png")
	rocks = load(ROCKS)
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	falloff.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	band = GradientTexture2D.new()
	band.gradient = falloff
	band.fill_from = Vector2(0, 0)
	band.fill_to = Vector2(0, 1)
	band.width = 4
	band.height = 64
	embers.fade_in = 0.0
	embers.fade_out = 0.4
	flakes.fade_in = 0.05
	flakes.fade_out = 0.45
	debris.fade_in = 0.0
	debris.fade_out = 0.3
	dust.fade_in = 0.15
	dust.fade_out = 0.6
	for spec in [["NezukoFloor", -9, false], ["NezukoSigil", -9, true], ["NezukoGlow", -1, true], ["NezukoFront", 0, false], ["NezukoLight", 0, true]]:
		layers.append(_layer(spec[0], spec[1], spec[2]))
	for key: String in TECHNIQUES:
		var technique: RefCounted = TECHNIQUES[key].new()
		technique.vfx = self
		techniques[key] = technique
	demon = Demon.new()
	demon.vfx = self

## A hot ember: white core, pink rim.
static func _ember_texture() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length() / 14.0
			var alpha := clampf((1.0 - d) * 4.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 0.55, 0.78).lerp(Color.WHITE, clampf((0.6 - d) * 3.0, 0.0, 1.0)) * Color(1, 1, 1, alpha))
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
	for pool in [embers, flakes, debris, dust]:
		pool.clear()
	bursts.clear()
	_ticks.clear()
	for each: RefCounted in techniques.values():
		each.reset()
	demon.reset()
	time = 0.0
	redraw()

func redraw() -> void:
	for layer in layers:
		layer.queue_redraw()

# --- Simulation -------------------------------------------------------------------

var _ticks: Dictionary = {}

func advance(delta: float) -> void:
	time += delta
	for pool in [embers, flakes, debris, dust]:
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
	demon.consume(events, combat.fighters, actors)
	for event: Dictionary in events:
		if event.type == "round_end":
			break
		if event.type == "throw" and event.has("attacker"):
			var thrower = combat.fighters[event.attacker]
			var throw_move: Resource = combat.definition(thrower).throw_move
			if handles(throw_move):
				focus = int(event.attacker)
				techniques.grapple.slam(event, thrower, awakened(event.attacker))
			continue
		if event.type not in ["hit", "block"] or not event.has("attacker"):
			continue
		var move: Resource = combat.moves.get(event.get("move", ""))
		if not handles(move):
			continue
		focus = int(event.attacker)
		technique(move).contact(event, move, combat.fighters[event.attacker], awakened(event.attacker))
	focus = -1
	redraw()

func _emit_fighter(f: RefCounted) -> void:
	if not handles(f.move) or not combat.presents_attack(f.slot) or f.slot >= actors.size():
		_ticks.erase(f.slot)
		return
	var last: Array = _ticks.get(f.slot, [-1, -1])
	var from: int = int(last[1]) + 1 if int(last[0]) == f.attack_instance else 0
	var drawing: RefCounted = technique(f.move)
	focus = f.slot
	for tick in range(from, f.move_frame + 1):
		drawing.emit(f, actors[f.slot], tick)
	focus = -1
	_ticks[f.slot] = [f.attack_instance, f.move_frame]

# --- Particle bursts --------------------------------------------------------------

## Embers flung from `at`; `bias` leans them one way.
func ember_burst(at: Vector2, count: int, bias: Vector2, slow: float, fast: float, seed: int, awakened_form: bool) -> void:
	var tint := Color(1.0, 0.82, 0.86) if awakened_form else Color.WHITE
	for n in range(count):
		var direction := (Vector2.from_angle(rand(seed, n) * TAU) + bias * 0.9).normalized()
		embers.spawn(at, direction * lerpf(slow, fast, rand(seed, n + 50)), lerpf(0.16, 0.38, rand(seed, n + 100)), lerpf(1.5, 3.0, rand(seed, n + 150)), 0, tint,
			220.0, 1.4, 0.0, 0.0, 0.6, 2.2)

## Torn flakes of burning blood thrown out of `at`, tumbling as they drift up.
func flake_burst(at: Vector2, count: int, speed: float, seed: int, awakened_form: bool, lift: float = 30.0) -> void:
	for n in range(count):
		var direction := Vector2.from_angle(rand(seed, n) * TAU)
		var tint := Color(1.0, 0.72, 0.74) if awakened_form else Color.WHITE
		flakes.spawn(at + direction * 4.0, direction * speed * lerpf(0.3, 1.0, rand(seed, n + 20)) + Vector2(0.0, -lift),
			lerpf(0.35, 0.75, rand(seed, n + 40)), lerpf(3.0, 6.0, rand(seed, n + 50)), int(rand(seed, n + 80) * 16.0), tint.darkened(0.2 * rand(seed, n + 90)),
			30.0, 1.8, rand(seed, n + 60) * TAU, rand(seed, n + 70) * 12.0 - 6.0, 0.8)

## Rock chunks thrown up where a blow breaks the floor; with `lit` every other
## one glows pink from below. `scale` grows them.
func debris_burst(at: Vector2, count: int, bias: Vector2, seed: int, lit: bool = false, scale: float = 1.0) -> void:
	for n in range(count):
		var direction := (Vector2(rand(seed, n) * 2.0 - 1.0, -lerpf(0.5, 1.0, rand(seed, n + 10))) + bias).normalized()
		var tint := Kit.ROCK_LIT if lit and n % 2 == 0 else Kit.ROCK
		tint = tint.darkened(0.25 * rand(seed, n + 15))
		debris.spawn(at, direction * lerpf(90.0, 230.0, rand(seed, n + 20)), lerpf(0.45, 0.8, rand(seed, n + 30)), lerpf(4.5, 9.0, rand(seed, n + 40)) * scale,
			int(rand(seed, n + 70) * 16.0), tint, 420.0, 0.4, rand(seed, n + 50) * TAU, rand(seed, n + 60) * 14.0 - 7.0)

## Dark smoke rolling out along the floor from `at`, leaning `bias.x`.
func dust_burst(at: Vector2, count: int, bias: Vector2, seed: int, size: float = 1.0) -> void:
	for n in range(count):
		var side := rand(seed, n) * 2.0 - 1.0
		var velocity := Vector2(side * 60.0 + bias.x * 90.0, -lerpf(6.0, 26.0, rand(seed, n + 10)) + bias.y * 40.0) * lerpf(0.5, 1.0, rand(seed, n + 20))
		dust.spawn(at + Vector2(side * 6.0, -2.0), velocity, lerpf(0.4, 0.65, rand(seed, n + 30)), lerpf(10.0, 18.0, rand(seed, n + 40)) * size, 0,
			Color(Kit.DUST, lerpf(0.35, 0.55, rand(seed, n + 50))), -10.0, 2.6, 0.0, 0.0, 2.2)

## Contact: a blood-flame burst whose first frame is already full size (hitstop
## holds it there), a white pressure ring, embers and torn flakes; heavier blows
## add the yellow-white cross flash, specials rays. Rock only flies where a blow
## strikes the floor. `scale` grows everything (light 0.5, heavy 0.75, special 1,
## supers more).
func strike(event: Dictionary, attacker: RefCounted, scale: float, awakened_form: bool, rays_too: bool = false) -> void:
	var at: Vector2 = event.position
	var facing := float(attacker.facing)
	var seed: int = attacker.attack_instance * 977 + int(event.get("segment", 0)) * 31 + attacker.slot * 13
	if event.type == "block":
		bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.16, "size": 12.0, "squash": 1.4, "facing": facing, "seed": seed, "awake": awakened_form})
		bursts.append({"kind": "blaze", "at": at, "age": 0.0, "life": 0.14, "size": 9.0, "facing": facing, "seed": seed, "awake": awakened_form, "pale": true})
		ember_burst(at, 8, Vector2(-facing, -0.5), 60.0, 140.0, seed, awakened_form)
		return
	bursts.append({"kind": "blaze", "at": at, "age": 0.0, "life": 0.18 + 0.06 * minf(scale, 1.5), "size": 9.0 + 13.0 * scale, "facing": facing, "seed": seed,
		"awake": awakened_form})
	bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.18, "size": 10.0 + 12.0 * scale, "squash": 1.5, "facing": facing, "seed": seed + 1, "awake": awakened_form})
	ember_burst(at, int(10 + 16 * scale), Vector2(facing, -0.3), 90.0, 240.0, seed, awakened_form)
	flake_burst(at, int(3 + 6 * scale), 80.0, seed + 3, awakened_form)
	if scale >= 0.75:
		bursts.append({"kind": "cross", "at": at, "age": 0.0, "life": 0.14, "size": 30.0 + 26.0 * scale, "facing": facing, "seed": seed + 5, "awake": awakened_form})
	if scale >= 1.0 or rays_too:
		bursts.append({"kind": "rays", "at": at, "age": 0.0, "life": 0.2, "size": 70.0 * scale, "facing": facing, "seed": seed + 2, "awake": awakened_form})

# --- Drawing ---------------------------------------------------------------------

func _paint(canvas: Node2D, layer: int) -> void:
	if camera == null or combat == null:
		return
	if combat.phase in ["fight", "round_end"]:
		demon.draw_all(canvas, layer, combat.fighters, actors)
		for f in combat.fighters:
			if handles(f.move) and combat.presents_attack(f.slot) and f.slot < actors.size():
				focus = f.slot
				set_base(canvas, frame_transform(f.x, f.y, f.facing))
				technique(f.move).draw(canvas, layer, f, actors[f.slot])
		focus = -1
	for burst: Dictionary in bursts:
		_draw_burst(canvas, layer, burst)
	canvas.draw_set_transform(Vector2.ZERO)
	var to_screen := Callable(camera, "point")
	match layer:
		Kit.FRONT:
			dust.draw(canvas, blob, to_screen, camera.zoom)
			debris.draw(canvas, rocks, to_screen, camera.zoom)
			flakes.draw(canvas, flake_sheet, to_screen, camera.zoom)
		Kit.LIGHT:
			embers.draw(canvas, dot, to_screen, camera.zoom)

func _draw_burst(canvas: Node2D, layer: int, burst: Dictionary) -> void:
	var k: float = burst.age / burst.life
	var scale: float = float(burst.get("scale", 1.0))
	set_base(canvas, Transform2D(0.0, Vector2(camera.zoom * float(burst.facing) * scale, camera.zoom * scale), 0.0, camera.point(burst.at)))
	var seed: int = burst.seed
	var awake: bool = burst.get("awake", false)
	match burst.kind:
		"blaze":
			var alpha := 1.0 - smoothstep(0.5, 1.0, k)
			blaze(canvas, layer, Vector2.ZERO, float(burst.size), seed, alpha, awake, k, burst.get("pale", false))
		"ring":
			var grow := 1.0 - pow(1.0 - k, 2.0)
			var radius: float = float(burst.size) * (0.6 + 0.8 * grow)
			ring(canvas, layer, Vector2.ZERO, Vector2(radius, radius * float(burst.squash) * 0.62), 0.0, 1.0 - k, 2.2, awake)
		"rays":
			if layer == Kit.LIGHT:
				rays(canvas, Vector2.ZERO, seed, 10, float(burst.size) * (0.5 + 0.3 * k), 0.7 * (1.0 - k), Kit.tone(awake))
		"cross":
			if layer == Kit.LIGHT:
				cross(canvas, Vector2.ZERO, float(burst.size) * (0.8 + 0.4 * k), 1.0 - k, seed)
		"star":
			star(canvas, layer, Vector2.ZERO, float(burst.size) * (0.85 + 0.3 * k), 1.0 - smoothstep(0.55, 1.0, k), seed)
		_:
			var owner: RefCounted = burst.get("technique")
			if owner != null:
				owner.draw_burst(canvas, layer, burst, k)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## Nezuko's drawing scale: CharacterDefinition.model_scale, times the demon
## form's size while she is in it (presentation only). The fighter-local points
## of the technique scripts were measured on her drawing at 1.0, so
## fighter-local frames, floor decals and `world` grow with her; points taken
## from the world (the opponent, a dash origin) are divided back
## (Technique.target_local, origin_local, local_of). Contact bursts and particles
## stay world-sized. Uses the fighter a technique is running for (`focus`), read
## from combat state and her definition (not the fighter view, which may not have
## synced yet), so emission never depends on the render loop.
func body_scale() -> float:
	if combat == null:
		return 1.0
	var slots: Array = [focus] if focus >= 0 else range(combat.fighters.size())
	for slot: int in slots:
		var f = combat.fighters[slot] if slot < combat.fighters.size() else null
		if f == null or str(f.character) != "nezuko":
			continue
		var definition: Resource = combat.definition(f)
		var form: float = float(definition.awakening.form_scale) if demon_art(f) and definition.awakening != null else 1.0
		return float(definition.model_scale) * form
	return 1.0

## Her normal form is the v3 redraw (2026-10-18) while the demon form keeps its
## shipped atlas. The v3 drawing is smaller (idle top 61 units against 73) and its
## limbs sit elsewhere, so techniques fit limb positions per form (Technique.fit) and
## size body-wide shapes (a gathering orb, a whirl round her) by `drawn`.
const V3_BODY := 0.84

## True while she is drawn from the kept demon-form atlas. From combat state, like
## `body_scale`, so emission never depends on the render loop.
static func demon_art(f: RefCounted) -> bool:
	return f.hp > 0 and (f.awakening_ticks > 0 or f.presents_awakened_finisher())

## Size of body-wide shapes for the drawing in use.
static func drawn(f: RefCounted) -> float:
	return 1.0 if demon_art(f) else V3_BODY

## Canvas transform of a fighter-local frame at world (x, y) facing `facing`.
func frame_transform(x: float, y: float, facing: float) -> Transform2D:
	var size: float = camera.zoom * body_scale()
	return Transform2D(0.0, Vector2(size * facing, size), 0.0, camera.point(Vector2(x, y)))

## A canvas transform at a world point without mirroring, for floor decals.
func world_transform(at: Vector2, facing: float = 1.0) -> Transform2D:
	var size: float = camera.zoom * body_scale()
	return Transform2D(0.0, Vector2(size * facing, size), 0.0, camera.point(at))

func set_base(canvas: Node2D, transform: Transform2D) -> void:
	base = transform
	canvas.draw_set_transform_matrix(base)

## The contact burst, after the reference: a full clump of curling pink flame
## round a white-hot core, baked in art/effects/nezuko/blaze-*.png (four
## variants, each dense and then breaking up), picked and turned by `seed`. `age`
## 0..1 runs its life: the first frame is already full size (hitstop holds it),
## then it swells a little and breaks up. Black-red ink spikes shoot out through
## it (FRONT), a hot flash lights it (LIGHT), a soft glow sits under the fighters
## (GLOW). `pale` keeps a guarded hit small and cool.
func blaze(canvas: Node2D, layer: int, at: Vector2, radius: float, seed: int, alpha: float, awakened_form: bool, age: float = 0.0, pale: bool = false) -> void:
	if alpha <= 0.01 or radius < 1.0:
		return
	var size := radius * (1.0 + 0.18 * age)
	var spin := rand(seed, 70) * TAU + age * 0.6
	var broken := smoothstep(0.15, 0.65, age)
	match layer:
		Kit.GLOW:
			if glow != null:
				canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * size * 2.0, Vector2.ONE * size * 4.0), false, Color(Kit.deep(awakened_form), 0.35 * alpha))
		Kit.FRONT:
			blaze_sprite(canvas, at, size, seed, broken, alpha * (0.7 if pale else 1.0), awakened_form, spin, Color(1.0, 0.9, 0.95) if pale else Color.WHITE)
			var ink := alpha * (1.0 - smoothstep(0.25, 0.75, age)) * (0.4 if pale else 0.8)
			var lines := 5 if pale else 8
			for n in range(lines):
				if ink <= 0.01:
					break
				var direction := Vector2.from_angle(TAU * (n + rand(seed, n + 400) * 0.8) / lines)
				var from := at + direction * size * lerpf(0.4, 0.75, rand(seed, n + 410))
				var to := at + direction * size * lerpf(1.4, 1.9, rand(seed, n + 420)) * (1.0 + 0.3 * age)
				Ribbon.draw(canvas, PackedVector2Array([from, from.lerp(to, 0.4), to]), PackedFloat32Array([0.0, lerpf(1.2, 2.2, rand(seed, n + 430)), 0.0]),
					PackedColorArray([Color(Kit.INK, 0.0), Color(Kit.INK, ink), Color(Kit.INK, 0.0)]), band)
		Kit.LIGHT:
			var flash := alpha * pow(1.0 - age, 3.0)
			if glow != null and flash > 0.01:
				canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * size * 0.4, Vector2.ONE * size * 0.8), false, Color(Kit.WHITE, 0.16 * flash))
				canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * size * 1.2, Vector2.ONE * size * 2.4), false, Color(Kit.tone(awakened_form), 0.14 * flash))
			blaze_sprite(canvas, at, size, seed, broken, alpha * 0.14, awakened_form, spin)

## One baked burst from the blaze sheet centred on `at`, its rim reaching about
## 1.2 x `radius`, turned by `spin` and mirrored by `seed`; `broken` (0..1)
## cross-fades the dense first frame into its breaking-up stage.
func blaze_sprite(canvas: Node2D, at: Vector2, radius: float, seed: int, broken: float, alpha: float, awakened_form: bool, spin: float,
		tint: Color = Color.WHITE) -> void:
	var sheet: Texture2D = blaze_art[1 if awakened_form else 0] if blaze_art.size() == 2 else null
	if sheet == null or alpha <= 0.01:
		return
	var cell := sheet.get_width() / 4.0
	var column := float(int(rand(seed, 71) * 4.0) % 4) * cell
	var flip := 1.0 if rand(seed, 72) < 0.5 else -1.0
	var side := radius * 2.8
	var rect := Rect2(-Vector2.ONE * side * 0.5, Vector2.ONE * side)
	canvas.draw_set_transform_matrix(base * Transform2D(spin, Vector2(flip, 1.0), 0.0, at))
	if broken < 1.0:
		canvas.draw_texture_rect_region(sheet, rect, Rect2(column, 0.0, cell, cell), Color(tint, alpha * (1.0 - broken)))
	if broken > 0.0:
		canvas.draw_texture_rect_region(sheet, rect, Rect2(column, cell, cell, cell), Color(tint, alpha * broken))
	canvas.draw_set_transform_matrix(base)

## A white air-pressure ring (an ellipse round `center`, rotated), thicker on its
## leading side, with a faint pink rim.
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
		tint.append(Color(Kit.WHITE if layer == Kit.FRONT else Kit.tone(awakened_form), (0.6 if layer == Kit.FRONT else 0.3) * alpha * lerpf(0.4, 1.0, lead)))
	Ribbon.draw(canvas, points, widths, tint, band)

## A crescent along `path` revealed to `head` and eroding behind `tail`: a white
## body with a pink rim (the air arcs of kicks).
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
			Ribbon.draw(canvas, points, widths, _tinted(tint, Color(Kit.WHITE, 0.8)), band)
		Kit.LIGHT:
			Ribbon.draw(canvas, points, _scaled(widths, 1.5), _tinted(tint, Color(Kit.tone(awakened_form), 0.45)), band)

## A flame stroke through `points` (root first) with `widths`: the baked flame
## strip (white core, pink body, torn crimson edge, a tip breaking into flecks)
## as a solid band on FRONT, its light again on LIGHT and a wide glow on GLOW.
## `variant` picks one of the four strips; `fade` (per point alpha) erodes it.
func flame(canvas: Node2D, layer: int, points: PackedVector2Array, widths: PackedFloat32Array, alphas: PackedFloat32Array, awakened_form: bool, variant: int,
		strip: Texture2D = null) -> void:
	if points.size() < 2:
		return
	var texture: Texture2D = strip if strip != null else flame_strip
	var row := float(variant % 4 + (4 if awakened_form else 0))
	var v0 := row / STRIP_ROWS
	var v1 := (row + 1.0) / STRIP_ROWS
	var tint := PackedColorArray()
	for a in alphas:
		tint.append(Color(1, 1, 1, a))
	match layer:
		Kit.GLOW:
			Ribbon.draw(canvas, points, _scaled(widths, 2.2), _tinted(tint, Color(Kit.deep(awakened_form), 0.3)), band)
		Kit.FRONT:
			Ribbon.draw(canvas, points, widths, tint, texture, 0.0, 0.0, v0, v1)
		Kit.LIGHT:
			Ribbon.draw(canvas, points, widths, _tinted(tint, Color(1, 1, 1, 0.22)), texture, 0.0, 0.0, v0, v1)

## A flame stroke laid along `path` (Paths.Sweep / Arc), revealed to `head` and
## burnt away behind `tail`, its width the path's profile times `thickness`.
func flame_along(canvas: Node2D, layer: int, path: RefCounted, head: float, tail: float, alpha: float, awakened_form: bool, thickness: float, variant: int,
		count: int = 18) -> void:
	if head <= 0.02 or tail >= 1.0 or alpha <= 0.01:
		return
	var from := clampf(tail, 0.0, head)
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	for n in range(count):
		var u := lerpf(from, head, n / (count - 1.0))
		points.append(path.point(u, 0.0))
		widths.append(path.width(u) * thickness)
		alphas.append(alpha * smoothstep(0.0, 0.2, float(n) / (count - 1.0)))
	flame(canvas, layer, points, widths, alphas, awakened_form, variant)

## Three (or `count`) claw strokes side by side along the curve start -> control
## -> end, revealed to `head` and eroding behind `tail`, each a little later and
## shorter than the one before (乱裂). `spread` is the gap between strokes.
func claws(canvas: Node2D, layer: int, keys: Array, count: int, spread: float, head: float, tail: float, alpha: float, awakened_form: bool, width: float, seed: int) -> void:
	if alpha <= 0.01 or head <= 0.0 or tail >= 1.0:
		return
	var start: Vector2 = keys[0]
	var control: Vector2 = keys[1]
	var end: Vector2 = keys[2]
	var across := (end - start).normalized().orthogonal()
	for k in range(count):
		var offset := across * spread * (k - (count - 1) * 0.5)
		var lag := 0.12 * k
		var h := clampf(head - lag, 0.0, 1.0)
		var e := clampf(tail - lag * 0.5, 0.0, 1.0)
		if h <= 0.02 or e >= 1.0:
			continue
		var shorten := 1.0 - 0.12 * absf(k - (count - 1) * 0.5)
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		var alphas := PackedFloat32Array()
		for n in range(14):
			var u := lerpf(e, h, n / 13.0)
			var uu := lerpf(0.5 - 0.5 * shorten, 0.5 + 0.5 * shorten, u)
			var p := start.lerp(control, uu).lerp(control.lerp(end, uu), uu)
			points.append(p + offset * lerpf(0.7, 1.15, uu))
			widths.append(width * pow(sin(clampf(uu, 0.03, 0.97) * PI), 0.6))
			alphas.append(alpha * smoothstep(0.0, 0.25, n / 13.0))
		flame(canvas, layer, points, widths, alphas, awakened_form, int(rand(seed, k) * 4.0), claw_strip)

## A long, thin, tapered streak from `from` to `to` (dashes, heel drops).
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
				Color(Kit.BLUSH, 0.6 * alpha)]), band)

## A white whirl of air round `at`: three spiral strokes turning by `spin`.
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
			points.append(at + Vector2(cos(a) * r, sin(a) * r * 0.55))
			widths.append(lerpf(0.4, 2.6, sin(u * PI)))
			tint.append(Color(Kit.WHITE if layer == Kit.FRONT else Kit.tone(awakened_form), alpha * sin(u * PI) * (0.75 if layer == Kit.FRONT else 0.45)))
		Ribbon.draw(canvas, points, widths, tint, band)

## Long thin rays radiating from `at` (additive layers only).
func rays(canvas: Node2D, at: Vector2, seed: int, count: int, length: float, alpha: float, tint: Color, spread: float = TAU, heading: float = 0.0) -> void:
	for n in range(count):
		var direction := Vector2.from_angle(heading - spread * 0.5 + spread * (n + rand(seed, n + 90) * 0.6) / count)
		var reach := length * lerpf(0.5, 1.0, rand(seed, n + 110))
		Ribbon.draw(canvas, PackedVector2Array([at + direction * reach * 0.15, at + direction * reach * 0.55, at + direction * reach]),
			PackedFloat32Array([2.2, 1.3, 0.0]), PackedColorArray([Color(Kit.BLUSH, 0.8 * alpha), Color(tint, 0.55 * alpha), Color(tint, 0.0)]), band)

## The yellow-white cross flash of a clean hit: two long thin streaks crossing
## through `at` (LIGHT).
func cross(canvas: Node2D, at: Vector2, size: float, alpha: float, seed: int) -> void:
	if alpha <= 0.01:
		return
	var tilt := lerpf(-0.35, 0.35, rand(seed, 1))
	for side: float in [-1.0, 1.0]:
		var axis := Vector2.from_angle(tilt + side * lerpf(0.45, 0.7, rand(seed, 2 + int(side))))
		Ribbon.draw(canvas, PackedVector2Array([at - axis * size, at, at + axis * size]), PackedFloat32Array([0.0, 2.6, 0.0]),
			PackedColorArray([Color(Kit.FLASH, 0.0), Color(Kit.FLASH, alpha), Color(Kit.FLASH, 0.0)]), band)
	if glow != null:
		canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * size * 0.25, Vector2.ONE * size * 0.5), false, Color(Kit.FLASH, 0.45 * alpha))

## A white manga impact star (star.png) with its soft black ink rim (FRONT).
func star(canvas: Node2D, layer: int, at: Vector2, size: float, alpha: float, seed: int) -> void:
	if layer != Kit.FRONT or star_sheet == null or alpha <= 0.01:
		return
	var cell := star_sheet.get_width() / 2.0
	var column := float(int(rand(seed, 3) * 2.0) % 2) * cell
	canvas.draw_set_transform_matrix(base * Transform2D(rand(seed, 4) * TAU, Vector2.ONE, 0.0, at))
	canvas.draw_texture_rect_region(star_sheet, Rect2(-Vector2.ONE * size, Vector2.ONE * size * 2.0), Rect2(column, 0.0, cell, cell), Color(1, 1, 1, alpha))
	canvas.draw_set_transform_matrix(base)

## A column of fire standing on `foot` (local, y = floor): broad flame tongues
## rising and swaying, packed side by side, `height` tall and `width` wide;
## `phase` sways them.
func pillar(canvas: Node2D, layer: int, foot: Vector2, height: float, width: float, alpha: float, awakened_form: bool, seed: int, phase: float) -> void:
	if alpha <= 0.01 or height < 2.0:
		return
	if layer == Kit.GLOW and glow != null:
		canvas.draw_texture_rect(glow, Rect2(foot + Vector2(-width * 1.4, -height * 0.95), Vector2(width * 2.8, height * 1.05)), false, Color(Kit.deep(awakened_form), 0.45 * alpha))
	for k in range(9):
		var across := (float(k) + 0.5) / 9.0 - 0.5
		var x0 := foot.x + across * width + (rand(seed, k) - 0.5) * width * 0.15
		# Tallest in the middle, lower toward the edges.
		var tall := height * lerpf(0.6, 1.0, rand(seed, k + 10)) * (1.0 - 0.45 * absf(across) * 2.0)
		var lean := -across * width * 0.3 + (rand(seed, k + 20) - 0.5) * width * 0.3
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		var alphas := PackedFloat32Array()
		for n in range(10):
			var u := n / 9.0
			var wave := sin(u * 3.0 + phase * 6.0 + k) * width * 0.1 * u
			points.append(Vector2(x0 + lean * u * u + wave, foot.y + 2.0 - tall * u))
			widths.append(width * 0.42 * lerpf(1.0, 0.3, u))
			alphas.append(alpha)
		flame(canvas, layer, points, widths, alphas, awakened_form, k)

## A whirl of fire round a vertical axis on `foot` (爆炎裂): a core of rising
## flame tongues wrapped in broad flame streaks that run round it in rising,
## flattened turns, the near side brighter and wider, the funnel widening as it
## climbs; a yellow-white line of light runs up its middle.
func tornado(canvas: Node2D, layer: int, foot: Vector2, height: float, radius: float, spin: float, alpha: float, awakened_form: bool, seed: int) -> void:
	if alpha <= 0.01:
		return
	if layer == Kit.GLOW and glow != null:
		canvas.draw_texture_rect(glow, Rect2(foot + Vector2(-radius * 2.0, -height * 1.05), Vector2(radius * 4.0, height * 1.15)), false, Color(Kit.deep(awakened_form), 0.55 * alpha))
	# Far half of the turns first (under the core), then the core, then the near half.
	for near in [false, true]:
		if near:
			pillar(canvas, layer, foot, height * 0.95, radius * 1.1, alpha, awakened_form, seed + 77, spin * 0.05)
		for k in range(14):
			var rise := (float(k) + 0.5) / 14.0
			var y := foot.y - height * rise
			var r := radius * lerpf(0.7, 1.35, rise) * lerpf(0.85, 1.1, rand(seed, k))
			var a0 := spin * (1.0 + 0.12 * k) + rand(seed, k + 10) * TAU
			var points := PackedVector2Array()
			var widths := PackedFloat32Array()
			var alphas := PackedFloat32Array()
			for n in range(14):
				var u := n / 13.0
				var a := a0 + u * 2.2
				var front := sin(a)
				if (front >= 0.0) != near:
					# Keep this half's points only; the strip breaks across the other half.
					if points.size() >= 2:
						flame(canvas, layer, points, widths, alphas, awakened_form, k)
					points = PackedVector2Array()
					widths = PackedFloat32Array()
					alphas = PackedFloat32Array()
					continue
				points.append(Vector2(foot.x + cos(a) * r, y + front * r * 0.3 - u * 8.0))
				widths.append(lerpf(10.0, 24.0, sin(u * PI)) * lerpf(0.75, 1.15, (front + 1.0) * 0.5))
				alphas.append(alpha * lerpf(0.55, 1.0, (front + 1.0) * 0.5))
			if points.size() >= 2:
				flame(canvas, layer, points, widths, alphas, awakened_form, k)
	if layer == Kit.LIGHT:
		Ribbon.draw(canvas, PackedVector2Array([foot + Vector2(0.0, 6.0), foot + Vector2(0.0, -height * 0.5), foot + Vector2(0.0, -height * 1.1)]),
			PackedFloat32Array([0.0, 2.6, 0.0]), PackedColorArray([Color(Kit.FLASH, 0.0), Color(Kit.FLASH, alpha), Color(Kit.FLASH, 0.0)]), band)

## The 爆血 dome (爆血踵落): an onion of fire `size` wide round `foot`.
## Tongues of flame of uneven height rise out of the floor, bulge outward and
## curl in toward a ragged crown, some licking up past it; those facing us are
## broad and bright, those at the rim narrow, those behind dim. A hot glow fills
## it and white-hot cracks run up the tongues. `age` (0..1 over its life) grows
## the tongues out of the floor, makes them flicker, then burns them away from
## the roots up.
func dome(canvas: Node2D, layer: int, foot: Vector2, size: float, alpha: float, awakened_form: bool, seed: int, age: float) -> void:
	if alpha <= 0.01 or size < 2.0:
		return
	var tall := size * 1.6
	if layer == Kit.GLOW and glow != null:
		canvas.draw_texture_rect(glow, Rect2(foot + Vector2(-size * 1.6, -tall * 1.2), Vector2(size * 3.2, tall * 1.35)), false, Color(Kit.deep(awakened_form), 0.6 * alpha))
	if layer == Kit.LIGHT and glow != null:
		canvas.draw_texture_rect(glow, Rect2(foot + Vector2(-size * 0.9, -tall * 0.85), Vector2(size * 1.8, tall * 0.85)), false, Color(Kit.tone(awakened_form), 0.45 * alpha))
	var count := 30
	var flicker := floori(age * 24.0)
	for pass_index in range(2):
		# Back segments first (dim), then the front ones over them.
		var front_pass := pass_index == 1
		for k in range(count):
			var behind := rand(seed, k + 90) < 0.3
			if behind == front_pass:
				continue
			# Uneven spacing round the onion (sorted by k, jittered), never a neat fan.
			var longitude := lerpf(-PI * 0.5, PI * 0.5, clampf((float(k) + (rand(seed, k) - 0.5) * 1.6) / (count - 1.0), 0.0, 1.0))
			var facing := cos(longitude)
			var s := sin(longitude)
			var delay := rand(seed, k + 50) * 0.12
			var reveal := clampf((age - delay) / 0.18, 0.0, 1.0)
			var burn := clampf((age - 0.55 - delay) / 0.4, 0.0, 1.0)
			if reveal <= 0.0 or burn >= 1.0:
				continue
			var reach := lerpf(0.75, 1.35, rand(seed, k + 20)) * (1.0 + 0.04 * sin(age * 30.0 + k))
			var sway := sin(age * 14.0 + k * 1.7) * size * 0.06
			var root := foot + Vector2(s * size * lerpf(0.3, 0.7, rand(seed, k + 30)), 3.0)
			var control := foot + Vector2(s * size * lerpf(0.95, 1.3, rand(seed, k + 10)), -tall * lerpf(0.35, 0.6, rand(seed, k + 60)))
			var top := foot + Vector2(s * size * lerpf(0.0, 0.4, rand(seed, k + 70)) + sway, -tall * reach)
			var points := PackedVector2Array()
			var widths := PackedFloat32Array()
			var alphas := PackedFloat32Array()
			var shade := (0.45 if behind else 1.0) * lerpf(0.55, 1.0, facing)
			var thick := size * lerpf(0.24, 0.62, rand(seed, k + 40)) * lerpf(0.55, 1.0, facing)
			for n in range(16):
				var u := lerpf(burn, reveal, n / 15.0)
				points.append(root.lerp(control, u).lerp(control.lerp(top, u), u))
				widths.append(thick * lerpf(1.0, 0.2, u))
				alphas.append(alpha * shade * (1.0 - 0.25 * u) * smoothstep(0.0, 0.15, n / 15.0))
			flame(canvas, layer, points, widths, alphas, awakened_form, k + flicker % 2)
			if layer == Kit.LIGHT and not behind and k % 3 == 0:
				# White-hot cracks running up the fire, jumping as it flickers.
				var crack := PackedVector2Array()
				for n in range(9):
					var u := lerpf(maxf(burn, 0.1), reveal * 0.85, n / 8.0)
					var p := root.lerp(control, u).lerp(control.lerp(top, u), u)
					crack.append(p + Vector2((rand(seed, k * 13 + n + flicker) - 0.5) * 7.0, 0.0))
				canvas.draw_polyline(crack, Color(Kit.WHITE, 0.6 * alpha * facing), 1.2, true)

## A dark crater on the floor with cracks; `ember` lights its middle pink (the
## fire still burning in it). FLOOR layer for the scar, LIGHT for the ember.
func crater(canvas: Node2D, layer: int, at: Vector2, radius: float, alpha: float, seed: int, ember: float = 0.0, awakened_form: bool = false) -> void:
	if alpha <= 0.01:
		return
	if layer == Kit.LIGHT:
		if glow != null and ember > 0.01:
			canvas.draw_texture_rect(glow, Rect2(at - Vector2(radius * 0.7, radius * 0.7 * Kit.FLOOR_SQUASH * 1.6), Vector2(radius * 1.4, radius * 1.4 * Kit.FLOOR_SQUASH * 1.6)), false,
				Color(Kit.tone(awakened_form), 0.6 * ember * alpha))
		return
	if layer != Kit.FLOOR:
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
	canvas.draw_colored_polygon(inner, Color(Kit.SCORCH.darkened(0.5), 0.45 * alpha))
	for n in range(7):
		var a := TAU * (n + rand(seed, n + 40) * 0.5) / 7.0
		var from := at + Vector2(cos(a) * radius * 0.9, sin(a) * radius * 0.9 * Kit.FLOOR_SQUASH)
		var to := at + Vector2(cos(a) * radius * lerpf(1.3, 1.8, rand(seed, n + 50)), sin(a) * radius * lerpf(1.3, 1.8, rand(seed, n + 50)) * Kit.FLOOR_SQUASH)
		canvas.draw_line(from, to, Color(Kit.CRATER, 0.7 * alpha), 1.0, true)

## Claw scratches torn into the floor ahead of `at` (local, y = floor): `count`
## thin crimson gashes laid nearly flat, glowing pink inside (FLOOR + LIGHT).
func scratches(canvas: Node2D, layer: int, at: Vector2, length: float, count: int, alpha: float, seed: int, awakened_form: bool) -> void:
	if alpha <= 0.01 or (layer != Kit.FLOOR and layer != Kit.LIGHT):
		return
	for k in range(count):
		var x := at.x + (rand(seed, k) - 0.3) * length * 1.2
		var y := at.y + (rand(seed, k + 10) - 0.5) * 3.0
		var span := length * lerpf(0.4, 0.8, rand(seed, k + 20))
		var lean := (rand(seed, k + 30) - 0.5) * 0.5
		var from := Vector2(x - span * 0.5, y + lean * 2.0)
		var to := Vector2(x + span * 0.5, y - lean * 2.0)
		var points := PackedVector2Array([from, from.lerp(to, 0.5), to])
		if layer == Kit.FLOOR:
			Ribbon.draw(canvas, points, PackedFloat32Array([0.0, 3.2, 0.0]), PackedColorArray([Color(Kit.SCORCH, alpha), Color(Kit.SCORCH, alpha), Color(Kit.SCORCH, alpha)]), band)
		else:
			Ribbon.draw(canvas, points, PackedFloat32Array([0.0, 1.4, 0.0]), PackedColorArray([Color(Kit.tone(awakened_form), 0.0), Color(Kit.tone(awakened_form), 0.8 * alpha),
				Color(Kit.tone(awakened_form), 0.0)]), band)

## A burnt streak along the floor from `from_x` to `to_x` (FLOOR layer), glowing
## along its middle while `ember` > 0 (LIGHT).
func scorch(canvas: Node2D, layer: int, from_x: float, to_x: float, alpha: float, seed: int, ember: float = 0.0, awakened_form: bool = false) -> void:
	if absf(to_x - from_x) < 4.0 or alpha <= 0.01:
		return
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(14):
		var u := n / 13.0
		points.append(Vector2(lerpf(from_x, to_x, u), -0.5 + (rand(seed, n) - 0.5) * 1.2))
		widths.append(7.0 * sin(clampf(u, 0.04, 0.96) * PI) * lerpf(0.7, 1.15, rand(seed, n + 20)))
		tint.append(Color(Kit.SCORCH, 0.65 * alpha))
	if layer == Kit.FLOOR:
		Ribbon.draw(canvas, points, widths, tint, band)
	elif layer == Kit.LIGHT and ember > 0.01:
		Ribbon.draw(canvas, points, _scaled(widths, 0.35), _tinted(tint, Color(Kit.tone(awakened_form), ember / 0.65)), band)

## The floor breaking round `at` (local, y = floor) where a blow drives into it:
## broken slabs of stone (rocks.png cells) tip up out of the ground away from the
## blow and settle back, lit pink from below by the fire, with a hot glow in the
## cracks (GLOW). `grow` (0..1..0) raises and lowers them; the back row draws
## under the fighters (FLOOR), the front row over them (FRONT).
func rubble(canvas: Node2D, layer: int, at: Vector2, size: float, grow: float, seed: int, awakened_form: bool, count: int = 8) -> void:
	if grow <= 0.01:
		return
	if layer == Kit.GLOW:
		if glow != null:
			canvas.draw_texture_rect(glow, Rect2(at + Vector2(-size * 1.3, -size * 0.45), Vector2(size * 2.6, size * 0.9)), false, Color(Kit.tone(awakened_form), 0.3 * grow))
		return
	if (layer != Kit.FLOOR and layer != Kit.FRONT) or rocks == null:
		return
	var cell := rocks.get_width() / 4.0
	for n in range(count):
		var back := n % 2 == 0
		if back != (layer == Kit.FLOOR):
			continue
		var u := (n + 0.5) / count
		var x := at.x + lerpf(-size, size, u) + (rand(seed, n + 5) - 0.5) * size * 0.2
		var w := size * lerpf(0.6, 0.9, rand(seed, n + 10)) * (1.0 - 0.4 * absf(u - 0.5) * 2.0)
		var h := w * lerpf(0.65, 0.95, rand(seed, n + 20))
		var lean := (u - 0.5) * 1.3 + (rand(seed, n + 30) - 0.5) * 0.5
		var lift := h * lerpf(0.15, 0.55, rand(seed, n + 40)) * grow
		var pivot := Vector2(x, at.y + (-1.0 if back else 2.0) - lift)
		var tile := int(rand(seed, n + 50) * 16.0)
		var region := Rect2(float(tile % 4) * cell, float(tile / 4) * cell, cell, cell)
		var tint := Kit.ROCK.lerp(Kit.ROCK_LIT, 0.45 if back else 0.3).darkened(0.15 * rand(seed, n + 60))
		canvas.draw_set_transform_matrix(base * Transform2D(lean * grow, Vector2(1.0, grow), 0.0, pivot))
		canvas.draw_texture_rect_region(rocks, Rect2(-w * 0.5, -h * 0.85, w, h), region, tint)
	canvas.draw_set_transform_matrix(base)

## Blood gathering for a special, strength `k` (fighter-local): a dark crimson
## glow round her, a pink-white orb at `centre` inside a ring of black-red ink
## spikes, and her drawing flushed pink.
func activation(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D, k: float, seed: int, awakened_form: bool, centre: Vector2 = Vector2(0.0, -40.0)) -> void:
	if k <= 0.01:
		return
	var size := drawn(f)
	centre *= size
	match layer:
		Kit.GLOW:
			if glow != null:
				canvas.draw_texture_rect(glow, Rect2(centre - Vector2.ONE * 46.0 * size, Vector2.ONE * 92.0 * size), false, Color(Kit.BLOOD, 0.55 * k))
		Kit.FRONT:
			for n in range(14):
				var a := TAU * (n + rand(seed, n) * 0.6) / 14.0
				var direction := Vector2.from_angle(a)
				var from := centre + direction * 13.0 * size
				var to := centre + direction * lerpf(24.0, 40.0, rand(seed, n + 20)) * lerpf(0.7, 1.0, k) * size
				var side := direction.orthogonal() * lerpf(2.0, 3.6, rand(seed, n + 40))
				canvas.draw_colored_polygon(PackedVector2Array([from - side, to, from + side]), Color(Kit.INK, 0.8 * k))
		Kit.LIGHT:
			if glow != null:
				canvas.draw_texture_rect(glow, Rect2(centre - Vector2.ONE * 15.0 * size, Vector2.ONE * 30.0 * size), false, Color(Kit.WHITE, 0.7 * k))
				canvas.draw_texture_rect(glow, Rect2(centre - Vector2.ONE * 30.0 * size, Vector2.ONE * 60.0 * size), false, Color(Kit.tone(awakened_form), 0.6 * k))
			body_flash(canvas, f, actor, Color(Kit.tone(awakened_form), 0.4 * k))

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
		var offset := Vector2(cos(a) * 1.8, sin(a) * 1.4 - lerpf(0.8, 2.6, rand(seed, n)))
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

## Fighter-local point or direction to world, for anything with x, y, facing
## (points scale with her drawing, see `body_scale`).
func world(frame: Variant, local: Vector2) -> Vector2:
	var size := body_scale()
	return Vector2(frame.x + local.x * size * frame.facing, frame.y + local.y * size)

static func world_dir(frame: Variant, local: Vector2) -> Vector2:
	return Vector2(local.x * frame.facing, local.y)

## Deterministic 0..1 noise (the same hash as the other rebuilt effects).
static func rand(seed: int, n: int) -> float:
	var h := (seed * 73856093) ^ (n * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
