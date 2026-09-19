extends Node2D
## Attack effects follow the actual move phase without changing combat timing.
# Curved sword sweeps are presentation coordinates relative to the feet, facing right.
# Keep them independent of the rectangular hitboxes used by combat.
const CUT_CURVES := {
	"stand_light": [Vector2(13, -43), Vector2(38, -60), Vector2(61, -40)],
	"stand_heavy": [Vector2(9, -70), Vector2(96, -65), Vector2(45, -16)],
	"crouch_light": [Vector2(13, -20), Vector2(40, -34), Vector2(56, -15)],
	"crouch_heavy": [Vector2(9, -19), Vector2(45, -33), Vector2(71, -6)],
	"air_light": [Vector2(11, -45), Vector2(65, -43), Vector2(42, -5)],
	"air_heavy": [Vector2(5, -62), Vector2(87, -51), Vector2(43, 2)],
}
const CUT_SEGMENTS: int = 32

var camera: RefCounted
var combat: RefCounted
var sparks: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var time: float = 0
var trauma: float = 0
var freeze: bool = false
var textures: Dictionary = {}

func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	for id in ["water-slash", "water-wheel", "thunder", "impact"]:
		var path: String = "res://art/effects/%s.png" % id
		if ResourceLoader.exists(path):
			textures[id] = load(path)

func consume(events: Array) -> void:
	for event: Dictionary in events:
		if event.type not in ["hit", "throw", "block", "clash"]:
			continue
		var blocked: bool = event.type in ["block", "clash"]
		var color := Color("9ccbdd") if blocked else (Color("f9a075") if event.type == "throw" else Color("ffe1a2"))
		for n in range(12 if not blocked else 7):
			var angle: float = float(n) * 2.399 + time
			var speed: float = 35 + n % 5 * 17
			sparks.append({"at": event.position, "velocity": Vector2(cos(angle), sin(angle)) * speed, "life": 0.15 + n % 3 * 0.06, "color": color, "length": 2 + n % 4})
		while sparks.size() > 72:
			sparks.pop_front()
		rings.append({"at": event.position, "life": 0.22, "color": color, "block": blocked, "throw": event.type == "throw"})
		if rings.size() > 8:
			rings.pop_front()
		trauma = maxf(trauma, 0.09 if blocked else 0.23)

func reset_effects() -> void:
	sparks.clear()
	rings.clear()
	trauma = 0
	time = 0

func _process(delta: float) -> void:
	if freeze:
		return
	time += delta
	trauma = maxf(0, trauma - delta * 1.6)
	for spark: Dictionary in sparks:
		spark.life -= delta
		spark.at += spark.velocity * delta
		spark.velocity.y += 110 * delta
	sparks = sparks.filter(func(p: Dictionary) -> bool: return p.life > 0)
	for ring: Dictionary in rings:
		ring.life -= delta
	rings = rings.filter(func(p: Dictionary) -> bool: return p.life > 0)
	queue_redraw()

func _effect(id: String, bounds: Rect2, color: Color = Color.WHITE) -> void:
	if textures.has(id):
		draw_texture_rect(textures[id], bounds, false, color)

func _draw_normal_cut(id: String, progress: float) -> void:
	if not CUT_CURVES.has(id):
		return
	var curve: Array = CUT_CURVES[id]
	var start: Vector2 = curve[0]
	var control: Vector2 = curve[1]
	var end: Vector2 = curve[2]
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var taper := PackedFloat32Array()
	# Advance a short ribbon along a quadratic curve, with pointed, fading ends.
	for i in range(CUT_SEGMENTS + 1):
		var along := float(i) / CUT_SEGMENTS
		var t := lerpf(lerpf(0.0, 0.20, progress), lerpf(0.70, 1.0, progress), along)
		points.append(start.lerp(control, t).lerp(control.lerp(end, t), t))
		var tangent := (control - start).lerp(end - control, t).normalized()
		var amount := sin(along * PI) if i > 0 and i < CUT_SEGMENTS else 0.0
		normals.append(tangent.orthogonal() * amount)
		taper.append(sqrt(amount))
	var heavy := id.ends_with("heavy")
	var opacity := 0.45 + sin(progress * PI) * 0.55
	_draw_cut_ribbon(points, normals, taper, 4.0 if heavy else 2.4, Color(0.53, 0.73, 1.0, opacity * 0.09))
	_draw_cut_ribbon(points, normals, taper, 1.7 if heavy else 0.9, Color(0.75, 0.88, 1.0, opacity * 0.27))
	_draw_cut_ribbon(points, normals, taper, 0.55 if heavy else 0.32, Color(1.0, 0.97, 0.86, opacity * 0.64))

func _draw_cut_ribbon(points: PackedVector2Array, normals: PackedVector2Array, taper: PackedFloat32Array, width: float, color: Color) -> void:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# A bright center fades to transparent edges across the ribbon's width.
	# This avoids the stair-stepped outlines of thin filled polygons at game scale.
	for i in range(points.size()):
		for side in [-1, 0, 1]:
			vertices.append(points[i] + normals[i] * width * side)
			colors.append(Color(color, color.a * taper[i] if side == 0 else 0.0))
		if i == 0:
			continue
		for strip in range(2):
			var first := (i - 1) * 3 + strip
			indices.append_array(PackedInt32Array([first, first + 1, first + 3, first + 1, first + 4, first + 3]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, vertices, colors)

func _draw() -> void:
	if camera == null or combat == null:
		return
	for fighter in combat.fighters:
		# Round-end poses retain their move frame; their sword effects must not linger.
		if combat.phase != "fight" or fighter.move == null or not fighter.hitbox().has_area():
			continue
		var facing: float = fighter.facing
		var origin: Vector2 = camera.point(Vector2(fighter.x, fighter.y))
		draw_set_transform(origin, 0, Vector2(camera.zoom * facing, camera.zoom))
		var progress: float = float(fighter.move_frame - fighter.move.startup) / maxi(1, fighter.move.active - 1)
		var strength := 0.57 + sin(progress * PI) * 0.40
		match fighter.move.id:
			"water_slash":
				_effect("water-slash", Rect2(0, -71 + progress * 8, 112, 75), Color(0.85, 0.98, 1, strength))
			"water_wheel":
				var center: Vector2 = camera.point(Vector2(fighter.x + 28 * facing, fighter.y - 46))
				draw_set_transform(center, progress * 1.3 * facing, Vector2(camera.zoom * facing, camera.zoom))
				_effect("water-wheel", Rect2(-46, -46, 92, 92), Color(0.88, 0.99, 1, strength))
			"thunder":
				_effect("thunder", Rect2(-101, -66, 194, 68), Color(1, 0.95, 0.72, strength))
				draw_line(Vector2(-70, -5), Vector2(61, -5), Color(1, 0.72, 0.2, 0.43), 0.8, true)
			"iai":
				draw_set_transform(camera.point(Vector2(fighter.x + 32 * facing, fighter.y - 43)), -0.9 * facing, Vector2(camera.zoom * facing, camera.zoom))
				_effect("thunder", Rect2(-46, -15, 92, 30), Color(1, 0.89, 0.59, strength * 0.82))
			_:
				_draw_normal_cut(fighter.move.id, progress)
	draw_set_transform(Vector2.ZERO)
	for spark: Dictionary in sparks:
		var at: Vector2 = camera.point(spark.at)
		var color: Color = spark.color
		color.a = clampf(spark.life / 0.15, 0, 1)
		var direction: Vector2 = spark.velocity.normalized()
		draw_line(at, at - direction * spark.length * camera.zoom, color, 1.2, true)
	for ring: Dictionary in rings:
		var at: Vector2 = camera.point(ring.at)
		var amount: float = 1.0 - ring.life / 0.22
		var color: Color = ring.color
		color.a = (1 - amount) * 0.75
		if not ring.block:
			var diameter: float = (36 + amount * 31) * camera.zoom
			_effect("impact", Rect2(at - Vector2.ONE * diameter / 2, Vector2.ONE * diameter), color)
		else:
			draw_arc(at, (6 + amount * 12) * camera.zoom, -1.4, 1.4, 25, color, 2, true)
		if ring.throw:
			draw_arc(at, (9 + amount * 18) * camera.zoom, 0, TAU, 32, color, 1.1, true)
