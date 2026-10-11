extends Node2D
## Tanjiro's elemental effects after the Hinokami Chronicles look: cel-shaded
## water strands with ukiyo-e foam, with Hinokami Kagura flame woven in while
## he is awakened. Shapes follow the move clock and the drawn blade; particles
## and bursts advance only with the presentation time EffectsView passes in, so
## hitstop, super freeze, pause and KO freezes hold the whole picture. Combat
## state is only ever read.
const Ribbon = preload("res://scripts/presentation/vfx/vfx_ribbon.gd")
const Pool = preload("res://scripts/presentation/vfx/vfx_pool.gd")
const Blade = preload("res://scripts/presentation/vfx/blade_track.gd")
const MIX_SHADER = preload("res://scripts/presentation/vfx/shaders/erode_mix.gdshader")
const ADD_SHADER = preload("res://scripts/presentation/vfx/shaders/erode_add.gdshader")
const ART := "res://art/effects/tanjiro/"
const TRACKS := "res://art/characters/tanjiro/"
## Moves drawn here; the rest of the kit still uses EffectsView until rebuilt.
const MOVES := {"tanjiro_236A": "water_slash", "tanjiro_236C": "water_slash"}
## Layers in draw order. WATER and SOLID sit one z below EffectsView so a struck
## fighter (raised to the effects z) stays readable over the body of the water;
## FRONT carries contact splashes and spray, which belong in front of everyone.
enum {WATER, SOLID, FRONT, FLAME, LIGHT}
## Foam sheet cells.
const CURL_CELLS := [0, 2, 7, 8, 12, 15]
const SPRAY_CELLS := [1, 3, 5, 6, 10, 11]
const CLOUD_CELLS := [4, 14]
const PETAL_CELLS := [0, 2, 4, 9, 10, 11, 13]
const SPARK_CELLS := [1, 5, 14, 15]
## Strand bundle of the cut, inner to outer: radial offset and width (fractions
## of the crescent thickness), tail/head trims, tint, texture rows, flow speed.
const STRANDS := [
	{"offset": -0.40, "width": 0.34, "from": 0.10, "to": 0.92, "tint": Color(0.74, 0.8, 1.0), "rows": [0.5, 0.82], "flow": 1.4},
	{"offset": -0.16, "width": 0.46, "from": 0.00, "to": 0.97, "tint": Color(0.9, 0.94, 1.0), "rows": [0.38, 0.74], "flow": 1.05},
	{"offset": 0.10, "width": 0.5, "from": 0.05, "to": 1.0, "tint": Color(1, 1, 1), "rows": [0.28, 0.64], "flow": 0.85},
	{"offset": 0.36, "width": 0.42, "from": 0.2, "to": 1.0, "tint": Color(1.06, 1.06, 1.06), "rows": [0.04, 0.5], "flow": 0.7},
]
## Frayed threads trailing off the tail of the cut.
const FRAYS := [{"offset": -0.62, "width": 0.13, "to": 0.34}, {"offset": -0.05, "width": 0.11, "to": 0.28}, {"offset": 0.58, "width": 0.12, "to": 0.4}]
const WATER_GLOW := Color(0.22, 0.52, 1.0)
const FIRE_GLOW := Color(1.0, 0.42, 0.12)
var combat: RefCounted
var camera: RefCounted
var actors: Array = []
var glow: Texture2D
## Sub-tick reveal for smooth high refresh rates; captures and tests turn it off.
var interpolate: bool = true
var frac: float = 0.0
var time: float = 0.0
var textures: Dictionary = {}
var band: GradientTexture2D
var dot: Texture2D
var drops := Pool.new(1, 1, 320)
var foam := Pool.new(4, 4, 120)
var petals := Pool.new(4, 4, 140)
var mist := Pool.new(1, 1, 200)
var bursts: Array[Dictionary] = []
var layers: Array[Node2D] = []
var _ticks: Dictionary = {}
var _projectiles: Dictionary = {}
## Local-to-canvas transform of the fighter or projectile being drawn.
var _base := Transform2D.IDENTITY

func _ready() -> void:
	for id in ["water-strands", "fire-strands", "water-crescent", "water-crescent-heavy", "water-impact", "water-foam", "fire-petals", "noise"]:
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
	for spec in [["TanjiroWater", MIX_SHADER, -1, false], ["TanjiroSolid", null, -1, false], ["TanjiroFront", null, 0, false],
			["TanjiroFlame", ADD_SHADER, 0, true], ["TanjiroLight", null, 0, true]]:
		layers.append(_layer(spec[0], spec[1], spec[2], spec[3]))

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

func reset() -> void:
	for pool in [drops, foam, petals, mist]:
		pool.clear()
	bursts.clear()
	_ticks.clear()
	_projectiles.clear()
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
	_track_projectiles()
	for pool in [drops, foam, petals, mist]:
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
		var attacker = combat.fighters[event.attacker]
		var heavy: bool = move.id.ends_with("C")
		var hybrid := _awakened(event.attacker)
		var at: Vector2 = event.position
		var facing := float(attacker.facing)
		var seed: int = attacker.attack_instance * 977 + int(event.get("segment", 0)) * 31
		if event.type == "hit":
			# Hitstop holds these on their first frame, so that frame must already read.
			bursts.append({"kind": "splash", "at": at, "age": 0.0, "life": 0.32, "size": 58.0 if heavy else 48.0, "facing": facing, "spin": _rand(seed, 1) * 0.3 - 0.15})
			bursts.append({"kind": "cross", "at": at, "age": 0.0, "life": 0.14, "size": 150.0 if heavy else 128.0, "facing": facing})
			bursts.append({"kind": "ring", "at": at, "age": 0.0, "life": 0.22, "size": 34.0 if heavy else 28.0, "hybrid": hybrid})
			_droplets(at, 30 if heavy else 24, Vector2(facing, -0.2), 90.0, 230.0, seed)
			_foam_burst(at, 7 if heavy else 5, Vector2(facing, -0.3), 50.0, 110.0, seed + 3)
			_mist(at, 5, 26.0, seed + 5)
			if hybrid:
				_petals(at, 18, 120.0, seed + 9)
		else:
			bursts.append({"kind": "splash", "at": at, "age": 0.0, "life": 0.28, "size": 40.0, "facing": facing, "spin": 0.0})
			_droplets(at, 12, Vector2(-facing, -0.5), 60.0, 140.0, seed)
	redraw()

func _emit_fighter(f: RefCounted) -> void:
	if not handles(f.move) or not combat.presents_attack(f.slot) or f.slot >= actors.size():
		_ticks.erase(f.slot)
		return
	var last: Array = _ticks.get(f.slot, [-1, -1])
	var from: int = int(last[1]) + 1 if int(last[0]) == f.attack_instance else 0
	for tick in range(from, f.move_frame + 1):
		_emit_slash(f, actors[f.slot], tick)
	_ticks[f.slot] = [f.attack_instance, f.move_frame]

func _emit_slash(f: RefCounted, actor: Node2D, tick: int) -> void:
	var move: Resource = f.move
	var heavy: bool = move.id.ends_with("C")
	var hybrid: bool = actor.form_active()
	var seed: int = f.attack_instance * 131 + f.slot * 7919 + tick * 17
	var start: int = move.startup
	if tick >= 3 and tick < start:
		# Beads of water drawn in toward the blade while it is raised.
		var blade := _blade(actor, actor.move_clip_frame(tick) if actor.clip == move.clip_id() else actor.frame_index)
		if blade.size() == 2:
			for n in range(3):
				var target := blade[0].lerp(blade[1], 0.3 + 0.65 * _rand(seed, n))
				var offset := Vector2.from_angle(_rand(seed, n + 3) * TAU) * (10.0 + 8.0 * _rand(seed, n + 5))
				drops.spawn(_world(f, target + offset), _world_dir(f, -offset) / 0.2, 0.2, lerpf(1.4, 2.4, _rand(seed, n + 7)), 0, Color(1, 1, 1, 0.95))
	var arc := _slash_arc(actor, heavy)
	if tick == start:
		# The cut flings spray off its outer edge along the swing.
		for n in range(34 if heavy else 26):
			var u := 0.15 + 0.85 * _rand(seed, n)
			var angle: float = lerpf(arc.a0, arc.a1, u)
			var local := _arc_point(arc, u, _width(u, heavy) * lerpf(0.1, 0.55, _rand(seed, n + 20)))
			var velocity := Vector2(-sin(angle), cos(angle)) * lerpf(80.0, 230.0, _rand(seed, n + 40)) + Vector2.from_angle(angle) * lerpf(30.0, 110.0, _rand(seed, n + 80))
			drops.spawn(_world(f, local), _world_dir(f, velocity), lerpf(0.3, 0.55, _rand(seed, n + 120)), lerpf(1.6, 3.6, _rand(seed, n + 160)), 0, Color.WHITE,
				340.0, 0.8, 0.0, 0.0, 0.7, 0.9)
		for n in range(8 if heavy else 6):
			var u := 0.55 + 0.45 * _rand(seed, n + 200)
			var angle: float = lerpf(arc.a0, arc.a1, u)
			foam.spawn(_world(f, _arc_point(arc, u, _width(u, heavy) * 0.45)), _world_dir(f, Vector2(-sin(angle), cos(angle)) * 70.0 + Vector2.from_angle(angle) * 40.0),
				lerpf(0.25, 0.4, _rand(seed, n + 220)), lerpf(5.0, 8.0, _rand(seed, n + 240)) * (1.2 if heavy else 1.0), SPRAY_CELLS[n % SPRAY_CELLS.size()], Color.WHITE,
				200.0, 1.5, _rand(seed, n + 260) * TAU, _rand(seed, n + 280) * 6.0 - 3.0, 0.8)
		# Spray kicked up along the ground in front of the stance.
		var reach := 74.0 if heavy else 58.0
		for n in range(14):
			drops.spawn(_world(f, Vector2(lerpf(6.0, reach, _rand(seed, n + 400)), -1.0)), _world_dir(f, Vector2(lerpf(20.0, 70.0, _rand(seed, n + 420)), -lerpf(40.0, 120.0, _rand(seed, n + 440)))),
				lerpf(0.3, 0.5, _rand(seed, n + 460)), lerpf(1.5, 3.0, _rand(seed, n + 480)), 0, Color.WHITE, 380.0, 0.5, 0.0, 0.0, 0.7, 0.8)
		if hybrid:
			for n in range(16):
				var u := 0.15 + 0.85 * _rand(seed, n + 500)
				var angle: float = lerpf(arc.a0, arc.a1, u)
				petals.spawn(_world(f, _arc_point(arc, u, 0.0)), _world_dir(f, Vector2.from_angle(angle) * lerpf(40.0, 90.0, _rand(seed, n + 520)) + Vector2(0, -30)),
					lerpf(0.45, 0.75, _rand(seed, n + 540)), lerpf(5.0, 9.0, _rand(seed, n + 560)), PETAL_CELLS[n % PETAL_CELLS.size()], Color.WHITE, -40.0, 1.5,
					_rand(seed, n + 580) * TAU, _rand(seed, n + 600) * 8.0 - 4.0, 0.7)
	if tick > start + 2 and tick <= start + 17:
		# The crescent breaks into droplets where it erodes, tail first.
		var u := clampf(float(tick - start - 3) / 14.0, 0.0, 1.0)
		var angle: float = lerpf(arc.a0, arc.a1, u)
		var outward := Vector2.from_angle(angle)
		for n in range(4):
			var local := _arc_point(arc, u, _width(u, heavy) * (_rand(seed, n) - 0.5))
			drops.spawn(_world(f, local), _world_dir(f, outward * lerpf(10.0, 50.0, _rand(seed, n + 10)) + Vector2(-sin(angle), cos(angle)) * 30.0),
				lerpf(0.3, 0.5, _rand(seed, n + 20)), lerpf(1.3, 2.6, _rand(seed, n + 30)), 0, Color.WHITE, 260.0, 0.8)
		if tick % 2 == 0:
			foam.spawn(_world(f, _arc_point(arc, u, 0.0)), _world_dir(f, outward * 20.0 + Vector2(0, 15)), 0.32, lerpf(4.0, 6.5, _rand(seed, 40)),
				(CLOUD_CELLS + SPRAY_CELLS)[tick % 8], Color.WHITE, 120.0, 2.0, _rand(seed, 41) * TAU, 0.0, 0.7)
			mist.spawn(_world(f, _arc_point(arc, u, 0.0)), _world_dir(f, outward * 14.0), 0.4, 8.0, 0, Color(0.85, 0.95, 1.0, 0.3), 0.0, 2.0, 0.0, 0.0, 1.8)
		if hybrid:
			petals.spawn(_world(f, _arc_point(arc, u, 0.0)), _world_dir(f, outward * 30.0 + Vector2(0, -25)), 0.5, 5.5, PETAL_CELLS[tick % PETAL_CELLS.size()], Color.WHITE,
				-50.0, 1.5, _rand(seed, 70) * TAU, 5.0, 0.7)
			petals.spawn(_world(f, _arc_point(arc, u, 2.0)), _world_dir(f, outward * 50.0 + Vector2(0, -40)), 0.38, 3.5, SPARK_CELLS[tick % SPARK_CELLS.size()], Color.WHITE,
				-80.0, 1.0, _rand(seed, 71) * TAU, 0.0, 0.6)

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
			_emit_wave(p, move, tick, age)
		_projectiles[key] = {"age": age, "x": p.x, "y": p.y, "facing": int(p.facing), "move": p.move, "owner": int(p.owner), "instance": int(p.instance)}
	for key: String in _projectiles.keys():
		if not seen.has(key):
			_dissipate(_projectiles[key])
			_projectiles.erase(key)

func _emit_wave(p: Dictionary, move: Resource, tick: int, age: int) -> void:
	var heavy: bool = move.id.ends_with("C")
	var hybrid := _awakened(int(p.owner))
	var seed: int = int(p.instance) * 613 + tick * 29
	var facing := float(p.facing)
	var height := _wave_height(heavy)
	var at := Vector2(float(p.x) - float(p.vx) * (age - tick), float(p.y))
	# Spray off the crest and droplets falling from the base as it travels.
	for n in range(3):
		var y := (_rand(seed, n) - 0.5) * height * 0.85
		drops.spawn(at + Vector2(facing * height * 0.05, y), Vector2(facing * lerpf(-40.0, 30.0, _rand(seed, n + 3)), -lerpf(0.0, 70.0, _rand(seed, n + 6))),
			lerpf(0.25, 0.45, _rand(seed, n + 9)), lerpf(1.3, 2.8, _rand(seed, n + 12)), 0, Color.WHITE, 360.0, 0.6, 0.0, 0.0, 0.7, 0.6)
	mist.spawn(at + Vector2(-facing * height * 0.2, (_rand(seed, 20) - 0.5) * height * 0.7), Vector2(-facing * lerpf(10.0, 30.0, _rand(seed, 21)), 0.0),
		0.3, lerpf(6.0, 10.0, _rand(seed, 22)), 0, Color(0.85, 0.95, 1.0, 0.3), 0.0, 1.5, 0.0, 0.0, 1.6)
	if tick % 4 == 0:
		foam.spawn(at + Vector2(-facing * 3.0, height * 0.32), Vector2(facing * lerpf(-10.0, 20.0, _rand(seed, 30)), -lerpf(10.0, 40.0, _rand(seed, 31))),
			0.35, lerpf(4.0, 6.0, _rand(seed, 32)) * (1.2 if heavy else 1.0), SPRAY_CELLS[tick % SPRAY_CELLS.size()], Color.WHITE, 300.0, 0.5, _rand(seed, 33) * TAU, 2.0, 0.8)
	if hybrid:
		petals.spawn(at + Vector2(-facing * height * 0.2, (_rand(seed, 40) - 0.5) * height * 0.6), Vector2(-facing * lerpf(20.0, 50.0, _rand(seed, 41)), -lerpf(10.0, 40.0, _rand(seed, 42))),
			0.4, lerpf(4.0, 7.0, _rand(seed, 43)), (PETAL_CELLS + SPARK_CELLS)[tick % 11], Color.WHITE, -60.0, 1.2, _rand(seed, 44) * TAU, 4.0, 0.7)

func _dissipate(record: Dictionary) -> void:
	var at := Vector2(float(record.x), float(record.y))
	var seed: int = int(record.instance) * 389
	var heavy: bool = String(record.move).ends_with("C")
	_droplets(at, 22 if heavy else 16, Vector2(record.facing, 0), 50.0, 140.0, seed)
	_foam_burst(at, 5 if heavy else 4, Vector2(record.facing, 0), 30.0, 70.0, seed + 1)
	_mist(at, 6, 30.0, seed + 3)
	if _awakened(int(record.owner)):
		_petals(at, 6, 60.0, seed + 7)

func _droplets(at: Vector2, count: int, bias: Vector2, slow: float, fast: float, seed: int) -> void:
	for n in range(count):
		var direction := (Vector2.from_angle(_rand(seed, n) * TAU) + bias * 0.9).normalized()
		drops.spawn(at, direction * lerpf(slow, fast, _rand(seed, n + 50)), lerpf(0.3, 0.55, _rand(seed, n + 100)), lerpf(1.5, 3.4, _rand(seed, n + 150)), 0, Color.WHITE,
			380.0, 0.6, 0.0, 0.0, 0.7, 0.8)

func _foam_burst(at: Vector2, count: int, bias: Vector2, slow: float, fast: float, seed: int) -> void:
	for n in range(count):
		var direction := (Vector2.from_angle(_rand(seed, n) * TAU) + bias * 0.8).normalized()
		foam.spawn(at, direction * lerpf(slow, fast, _rand(seed, n + 50)), lerpf(0.25, 0.4, _rand(seed, n + 100)), lerpf(6.0, 10.0, _rand(seed, n + 150)),
			(SPRAY_CELLS + CURL_CELLS)[n % 12], Color.WHITE, 220.0, 1.5, _rand(seed, n + 200) * TAU, _rand(seed, n + 250) * 6.0 - 3.0, 0.8)

func _mist(at: Vector2, count: int, speed: float, seed: int) -> void:
	for n in range(count):
		mist.spawn(at, Vector2.from_angle(_rand(seed, n) * TAU) * speed * lerpf(0.5, 1.0, _rand(seed, n + 20)), 0.45, lerpf(9.0, 14.0, _rand(seed, n + 40)), 0,
			Color(0.85, 0.95, 1.0, 0.35), 0.0, 2.0, 0.0, 0.0, 1.8)

func _petals(at: Vector2, count: int, speed: float, seed: int) -> void:
	for n in range(count):
		petals.spawn(at, Vector2.from_angle(_rand(seed, n) * TAU) * speed * lerpf(0.4, 1.0, _rand(seed, n + 20)) + Vector2(0, -20), lerpf(0.4, 0.7, _rand(seed, n + 40)),
			lerpf(5.0, 9.0, _rand(seed, n + 60)), (PETAL_CELLS + SPARK_CELLS)[n % 11], Color.WHITE, -40.0, 1.5, _rand(seed, n + 80) * TAU, _rand(seed, n + 100) * 8.0 - 4.0, 0.7)

# --- Drawing ---------------------------------------------------------------------

func _paint(canvas: Node2D, layer: int) -> void:
	if camera == null or combat == null:
		return
	if combat.phase in ["fight", "round_end"]:
		for f in combat.fighters:
			if handles(f.move) and combat.presents_attack(f.slot) and f.slot < actors.size():
				_base = Transform2D(0.0, Vector2(camera.zoom * f.facing, camera.zoom), 0.0, camera.point(Vector2(f.x, f.y)))
				canvas.draw_set_transform_matrix(_base)
				_draw_water_slash(canvas, layer, f, actors[f.slot])
		for p: Dictionary in combat.projectiles:
			var move: Resource = combat.moves.get(p.move)
			if handles(move):
				_base = Transform2D(0.0, Vector2(camera.zoom * float(p.facing), camera.zoom), 0.0, camera.point(Vector2(p.x, p.y)))
				canvas.draw_set_transform_matrix(_base)
				_draw_wave(canvas, layer, p, move)
	canvas.draw_set_transform(Vector2.ZERO)
	var to_screen := Callable(camera, "point")
	match layer:
		FRONT:
			_draw_bursts(canvas, "splash")
			foam.draw(canvas, textures.get("water-foam"), to_screen, camera.zoom)
			petals.draw(canvas, textures.get("fire-petals"), to_screen, camera.zoom)
			drops.draw(canvas, dot, to_screen, camera.zoom)
		LIGHT:
			mist.draw(canvas, glow, to_screen, camera.zoom)
			_draw_bursts(canvas, "light")

func _draw_water_slash(canvas: Node2D, layer: int, f: RefCounted, actor: Node2D) -> void:
	var move: Resource = f.move
	var heavy: bool = move.id.ends_with("C")
	var hybrid: bool = actor.form_active()
	var t := float(f.move_frame) + frac
	var start := float(move.startup)
	# Water gathers along the raised blade, then leaves with the cut.
	var gather := clampf((t - 2.0) / 5.0, 0.0, 1.0) * (1.0 - clampf(t - start, 0.0, 1.0))
	if gather > 0.0:
		_blade_water(canvas, layer, actor, gather, hybrid)
	if layer == LIGHT:
		# Activation glint on the body, as each breathing form begins.
		var flash := sin(clampf((t - start + 4.0) / 5.0, 0.0, 1.0) * PI)
		if flash > 0.02:
			_body_flash(canvas, f, actor, Color(0.30, 0.55, 1.0) * flash * 0.85)
	var head := clampf((t - start + 0.5) / 1.5, 0.0, 1.0)
	var tail := clampf((t - start - 3.0) / 14.0, 0.0, 1.25)
	if head <= 0.0 or tail >= 1.2:
		return
	var arc := _slash_arc(actor, heavy)
	var length: float = arc.length
	match layer:
		WATER:
			for strand: Dictionary in STRANDS:
				_strand(canvas, arc, heavy, head, tail, strand.offset, strand.width, strand.from, strand.to, strand.tint, strand.rows,
					length / 1.15, -time * float(strand.flow) + float(strand.offset))
				if hybrid and strand.offset < 0.0:
					# Hinokami Kagura flame braided between the water strands, opaque so
					# red and blue stay distinct instead of washing out to white.
					_strand(canvas, arc, heavy, head, tail + 0.05, float(strand.offset) + 0.17, 0.62, float(strand.from) + 0.08, float(strand.to) - 0.04,
						Color(1, 1, 1), [0.3, 0.7], length / 1.4, -time * 1.9 + float(strand.offset), textures.get("fire-strands"))
			for fray: Dictionary in FRAYS:
				_strand(canvas, arc, heavy, head, tail - 0.1, fray.offset, fray.width, 0.0, fray.to, Color(0.95, 0.98, 1.0), [0.4, 0.8], length / 2.0, -time * 1.6 + float(fray.offset))
			if hybrid:
				_strand(canvas, arc, heavy, head, tail + 0.1, 0.5, 0.34, 0.28, 1.0, Color(1, 1, 1), [0.25, 0.75], length / 1.8, -time * 2.2, textures.get("fire-strands"))
			_ground_streak(canvas, layer, t - start, heavy)
		SOLID:
			_foam_crest(canvas, arc, heavy, head, tail)
		FLAME:
			# Pale sword light just outside the water, as in the reference.
			var rim := PackedVector2Array()
			var rim_widths := PackedFloat32Array()
			var rim_tint := PackedColorArray()
			for n in range(40):
				var u := head * n / 39.0
				rim.append(_arc_point(arc, u, _width(u, heavy) * 0.5 + 2.2))
				rim_widths.append(3.6 * sin(clampf(u, 0.02, 0.98) * PI))
				rim_tint.append(Color(0.6, 0.72, 0.9, smoothstep(tail - 0.3, tail, u)))
			Ribbon.draw(canvas, rim, rim_widths, rim_tint, band)
		LIGHT:
			var soft := PackedVector2Array()
			var soft_widths := PackedFloat32Array()
			var soft_tint := PackedColorArray()
			# Blue light even when awakened: orange added over blue water washes it pale.
			for n in range(40):
				var u := head * n / 39.0
				soft.append(_arc_point(arc, u, 0.0))
				soft_widths.append(_width(u, heavy) * 2.4)
				soft_tint.append(Color(WATER_GLOW, (0.14 if hybrid else 0.2) * smoothstep(tail - 0.22, tail + 0.02, u)))
			Ribbon.draw(canvas, soft, soft_widths, soft_tint, band)
			_ground_streak(canvas, layer, t - start, heavy)

## One brush strand of the crescent: tapered at both ends, trimmed to its own
## share of the arc, eroding with the cut.
func _strand(canvas: Node2D, arc: Dictionary, heavy: bool, head: float, tail: float, offset: float, width: float, from: float, to: float,
		tint: Color, rows: Array, u_scale: float, u_offset: float, texture: Texture2D = null) -> void:
	var end := minf(head, to)
	if end <= from + 0.02:
		return
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var colors := PackedColorArray()
	var count := 32
	for n in range(count):
		var u := lerpf(from, end, n / (count - 1.0))
		var s := (u - from) / maxf(to - from, 0.001)
		var thickness := _width(u, heavy)
		points.append(_arc_point(arc, u, thickness * offset))
		widths.append(thickness * width * pow(sin(clampf(s, 0.02, 0.98) * PI), 0.6))
		colors.append(Color(tint, smoothstep(tail - 0.22, tail + 0.02, u)))
	Ribbon.draw(canvas, points, widths, colors, texture if texture != null else textures.get("water-strands"), u_scale, u_offset, rows[0], rows[1])

## Ukiyo-e foam curls riding the leading edge of the cut.
func _foam_crest(canvas: Node2D, arc: Dictionary, heavy: bool, head: float, tail: float) -> void:
	var sheet: Texture2D = textures.get("water-foam")
	if sheet == null:
		return
	var cell := sheet.get_size() / 4.0
	var count := 9 if heavy else 7
	for n in range(count):
		var u := 0.42 + 0.56 * n / (count - 1.0)
		if u > head:
			break
		var presence := smoothstep(tail - 0.2, tail + 0.02, u)
		if presence <= 0.05:
			continue
		var thickness := _width(u, heavy)
		var at := _arc_point(arc, u, thickness * 0.42)
		var angle: float = lerpf(arc.a0, arc.a1, u) + PI * 0.5
		var size := (thickness * 0.62 + 4.0) * lerpf(0.6, 1.0, presence)
		var index: int = CURL_CELLS[n % CURL_CELLS.size()]
		var origin := Vector2(index % 4, index / 4) * cell
		canvas.draw_set_transform_matrix(_base * Transform2D(angle, at))
		canvas.draw_texture_rect_region(sheet, Rect2(-size * 0.5, -size * 0.7, size, size), Rect2(origin, cell), Color(1, 1, 1, presence))
	canvas.draw_set_transform_matrix(_base)

## Thin water (and flame, when awakened) along the drawn blade.
func _blade_water(canvas: Node2D, layer: int, actor: Node2D, amount: float, hybrid: bool) -> void:
	var blade := _blade(actor, actor.frame_index)
	if blade.size() != 2:
		return
	var direction := (blade[1] - blade[0]).normalized()
	var points := Ribbon.smooth(PackedVector2Array([blade[0].lerp(blade[1], 0.15), blade[0].lerp(blade[1], 0.6), blade[1] + direction * 3.0]), 4)
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(points.size()):
		var u := float(n) / (points.size() - 1)
		widths.append(3.6 * amount * sin(clampf(u, 0.05, 0.95) * PI))
		tint.append(Color(1, 1, 1, amount))
	match layer:
		WATER:
			Ribbon.draw(canvas, points, widths, tint, textures.get("water-strands"), 14.0, -time * 2.5, 0.25, 0.9)
		FLAME:
			if hybrid:
				var thin := PackedFloat32Array()
				for w in widths:
					thin.append(w * 0.8)
				Ribbon.draw(canvas, points, thin, tint, textures.get("fire-strands"), 12.0, -time * 3.0)
		LIGHT:
			var wide := PackedFloat32Array()
			var soft := PackedColorArray()
			for n in range(points.size()):
				wide.append(widths[n] * 3.0)
				soft.append(Color(FIRE_GLOW if hybrid else WATER_GLOW, 0.35 * amount))
			Ribbon.draw(canvas, points, wide, soft, band)

## Bright wash along the floor under the cut, eroding from behind.
func _ground_streak(canvas: Node2D, layer: int, age: float, heavy: bool) -> void:
	if age < 0.0 or age > 20.0:
		return
	var reach := (74.0 if heavy else 58.0) * clampf(age / 2.0 + 0.3, 0.0, 1.0)
	var tail := clampf((age - 4.0) / 16.0, 0.0, 1.2)
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(16):
		var u := n / 15.0
		points.append(Vector2(lerpf(-4.0, reach, u), -0.6 - sin(u * PI) * 0.8))
		widths.append((4.5 if heavy else 3.6) * sin(clampf(u, 0.04, 0.96) * PI))
		tint.append(Color(1.0, 1.0, 1.0, smoothstep(tail - 0.2, tail + 0.05, u)))
	if layer == WATER:
		Ribbon.draw(canvas, points, widths, tint, textures.get("water-strands"), 30.0, -time * 1.5, 0.2, 0.9)
	elif layer == LIGHT:
		var wide := PackedFloat32Array()
		var soft := PackedColorArray()
		for n in range(points.size()):
			wide.append(widths[n] * 2.6)
			soft.append(Color(0.45, 0.85, 1.0, 0.4 * tint[n].a))
		Ribbon.draw(canvas, points, wide, soft, band)

func _body_flash(canvas: Node2D, f: RefCounted, actor: Node2D, color: Color) -> void:
	if actor.texture == null:
		return
	canvas.draw_set_transform(camera.point(Vector2(f.x, f.y)), 0, Vector2(camera.zoom * actor.pose_facing(), camera.zoom))
	canvas.draw_texture_rect(actor.texture, actor.sprite_rect(), false, color)
	canvas.draw_set_transform_matrix(_base)

static func _wave_height(heavy: bool) -> float:
	return 64.0 if heavy else 54.0

## The released crescent wave, in projectile-local units (+x forward).
func _draw_wave(canvas: Node2D, layer: int, p: Dictionary, move: Resource) -> void:
	var heavy: bool = move.id.ends_with("C")
	var hybrid := _awakened(int(p.owner))
	var age := float(move.projectile_lifetime - int(p.life)) + frac
	var remaining := float(p.life) - frac
	var grow := 1.0 - pow(1.0 - clampf(age / 3.0, 0.0, 1.0), 3.0)
	var fade := clampf(remaining / 8.0, 0.0, 1.0)
	var height := _wave_height(heavy) * lerpf(0.55, 1.0, grow) * (1.0 + 0.04 * sin(time * 28.0)) * (1.0 + (1.0 - fade) * 0.2)
	var texture: Texture2D = textures.get("water-crescent-heavy" if heavy else "water-crescent")
	if texture == null:
		return
	var width := height * texture.get_width() / texture.get_height()
	var traveled := absf(float(p.vx)) * age
	var floor_y: float = combat.FLOOR_Y - float(p.y)
	match layer:
		WATER:
			# Strands streaming off the back of the wave.
			for k in range(4):
				var y := (-0.36 + 0.24 * k) * height
				var length := minf(12.0 + age * 3.0, 36.0) * (0.7 + 0.15 * k)
				var points := PackedVector2Array([Vector2(-width * 0.25, y), Vector2(-width * 0.25 - length * 0.5, y + 1.5), Vector2(-width * 0.25 - length, y + 3.0)])
				Ribbon.draw(canvas, points, PackedFloat32Array([3.4, 2.2, 0.2]), PackedColorArray([Color(1, 1, 1, fade), Color(1, 1, 1, fade), Color(1, 1, 1, fade * 0.4)]),
					textures.get("water-strands"), 22.0, -time * 3.0 + k * 0.3, 0.3, 0.9)
			_wave_trail(canvas, layer, traveled, floor_y, fade)
		SOLID:
			canvas.draw_texture_rect(texture, Rect2(-width * 0.62, -height * 0.5, width, height), false, Color(1, 1, 1, fade))
		FRONT:
			if hybrid:
				# Flame braided through the wave, opaque so it reads as fire on water.
				for k in range(2):
					var core := Ribbon.arc(Vector2(-height * (0.52 + 0.08 * k), 0.0), Vector2(height * (0.5 + 0.06 * k), height * 0.44), -0.9, 0.9, 18)
					var widths := PackedFloat32Array()
					var tint := PackedColorArray()
					for n in range(core.size()):
						widths.append(height * (0.1 - 0.03 * k) * sin(clampf(n / 17.0, 0.05, 0.95) * PI))
						tint.append(Color(1, 1, 1, fade))
					Ribbon.draw(canvas, core, widths, tint, textures.get("fire-strands"), height * 0.9, -time * (2.0 + k), 0.12, 0.88)
		LIGHT:
			canvas.draw_texture_rect(glow, Rect2(-height * 0.7, -height * 0.65, height * 1.3, height * 1.3), false, Color(FIRE_GLOW if hybrid else WATER_GLOW, 0.3 * fade))
			_wave_trail(canvas, layer, traveled, floor_y, fade)

func _wave_trail(canvas: Node2D, layer: int, traveled: float, floor_y: float, fade: float) -> void:
	var span := minf(traveled + 6.0, 70.0)
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var tint := PackedColorArray()
	for n in range(12):
		var u := n / 11.0
		points.append(Vector2(lerpf(-span, 4.0, u), floor_y - 0.6))
		widths.append(3.2 * sin(clampf(u, 0.04, 0.96) * PI))
		tint.append(Color(1, 1, 1, smoothstep(0.0, 0.5, u) * fade))
	if layer == WATER:
		Ribbon.draw(canvas, points, widths, tint, textures.get("water-strands"), 26.0, -time * 2.0, 0.2, 0.9)
	else:
		var wide := PackedFloat32Array()
		var soft := PackedColorArray()
		for n in range(points.size()):
			wide.append(widths[n] * 2.8)
			soft.append(Color(0.45, 0.85, 1.0, 0.35 * tint[n].a))
		Ribbon.draw(canvas, points, wide, soft, band)

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
			var tone := Color(1.0, 0.62, 0.3) if burst.get("hybrid", false) else Color(0.8, 0.95, 1.0)
			var radius: float = (6.0 + burst.size * (1.0 - pow(1.0 - k, 2.0))) * zoom
			canvas.draw_arc(center, radius, 0.0, TAU, 48, Color(tone, (1.0 - k) * 0.75), lerpf(3.0, 0.6, k) * zoom, true)
			canvas.draw_texture_rect(glow, Rect2(center - Vector2.ONE * 11.0 * zoom, Vector2.ONE * 22.0 * zoom), false, Color(1, 1, 1, maxf(0.0, 1.0 - burst.age / 0.08) * 0.45))

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

# --- Geometry ---------------------------------------------------------------------

func _blade(actor: Node2D, index: int) -> PackedVector2Array:
	var directory := TRACKS + ("awakening/" if actor.uses_awakened_frames() else "")
	var pose := Blade.pose(directory, actor.clip, index)
	if pose.size() != 2:
		return PackedVector2Array()
	return PackedVector2Array([actor.canvas_to_local(pose[0]), actor.canvas_to_local(pose[1])])

## Overhead cut from the raised drawing to the low finish, centred between the
## two hilt positions so the water hugs the drawn sword in both forms.
func _slash_arc(actor: Node2D, heavy: bool) -> Dictionary:
	var directory := TRACKS + ("awakening/" if actor.uses_awakened_frames() else "")
	var raised := Blade.pose(directory, "water_slash", 2)
	var low := Blade.pose(directory, "water_slash", 3)
	var tip0 := Vector2(-27.5, -58.7)
	var tip1 := Vector2(39.6, -17.3)
	var pivot := Vector2(3.0, -44.0)
	if raised.size() == 2 and low.size() == 2:
		tip0 = actor.canvas_to_local(raised[1])
		tip1 = actor.canvas_to_local(low[1])
		pivot = (actor.canvas_to_local(raised[0]) + actor.canvas_to_local(low[0])) * 0.5
	var a0 := (tip0 - pivot).angle()
	var a1 := (tip1 - pivot).angle()
	while a1 <= a0:
		a1 += TAU
	var scale := 1.18 if heavy else 1.0
	var r0 := (tip0 - pivot).length() * scale
	var r1 := (tip1 - pivot).length() * scale
	return {"pivot": pivot, "a0": a0, "a1": a1, "r0": r0, "r1": r1, "length": (a1 - a0) * (r0 + r1) * 0.5 * 1.05}

func _arc_point(arc: Dictionary, u: float, offset: float) -> Vector2:
	var angle: float = lerpf(arc.a0, arc.a1, u)
	var radius: float = lerpf(arc.r0, arc.r1, u) * (1.0 + 0.1 * sin(u * PI)) + offset
	return arc.pivot + Vector2.from_angle(angle) * radius

## Crescent thickness: heavy toward the leading edge, never quite zero there.
func _width(u: float, heavy: bool) -> float:
	var body := pow(sin(clampf(u * 0.92 + 0.04, 0.0, 1.0) * PI), 0.5) * (0.35 + 0.65 * u)
	return (26.0 if heavy else 21.0) * body

func _awakened(slot: int) -> bool:
	return slot < actors.size() and actors[slot] != null and actors[slot].form_active()

func _world(f: RefCounted, local: Vector2) -> Vector2:
	return Vector2(f.x + local.x * f.facing, f.y + local.y)

func _world_dir(f: RefCounted, local: Vector2) -> Vector2:
	return Vector2(local.x * f.facing, local.y)

## Deterministic 0..1 noise so a replayed move always sheds the same particles.
static func _rand(seed: int, n: int) -> float:
	var h := (seed * 73856093) ^ (n * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
