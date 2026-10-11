extends Node2D
## Attack effects follow the actual move phase without changing combat timing.
# Sword ribbons follow the drawn blade. Skill reach is guided by move.box;
# lightning keeps its pointed silhouette and a softer movement wake. Impacts
# layer a light core, star streaks and per-character motes; every particle list
# freezes with `freeze` and expires well within half a second.
const Kit = preload("res://scripts/ui/kit.gd")
const TanjiroVfx = preload("res://scripts/presentation/vfx/tanjiro_vfx.gd")
## Character flavor for blade trails and impact motes.
const FLAVORS := {"tanjiro": "water", "zenitsu": "thunder", "nezuko": "blood", "akaza": "compass"}
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
var pulses: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var streaks: Array[Dictionary] = []
var shards: Array[Dictionary] = []
var motes: Array[Dictionary] = []
var screen_flash: float = 0.0
var glow: GradientTexture2D
var time: float = 0
var trauma: float = 0
var freeze: bool = false
var playback_speed: float = 1.0
var textures: Dictionary = {}
var body_layer: Node2D
## Fighter views by slot, for effects that follow the drawn blade.
var actors: Array = []
## Rebuilt character effects draw their own moves; everything else stays here.
var tanjiro: Node2D

func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	for id in ["water-slash", "water-wheel", "thunder", "impact", "water-dragon", "sun-flame-arc", "water-slash-body", "water-wheel-body", "thunder-body", "water-dragon-body", "sun-flame-arc-body", "water-slash-projectile", "water-slash-projectile-body", "water-slash-spray", "water-slash-spray-body"]:
		var path: String = "res://art/effects/%s.png" % id
		if ResourceLoader.exists(path):
			textures[id] = load(path)
	for move: Resource in combat.moves.values():
		if move.presentation == null: continue
		for key: String in [move.presentation.texture_key, move.presentation.projectile_texture_key, move.presentation.sigil_texture_key]:
			if key.is_empty(): continue
			for suffix in ["", "-body"]:
				var path: String = "res://art/effects/" + key + suffix + ".png"
				if ResourceLoader.exists(path): textures[key + suffix] = load(path)
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0)])
	falloff.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	glow = GradientTexture2D.new()
	glow.gradient = falloff
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = 128
	glow.height = 128
	body_layer = Node2D.new()
	body_layer.z_index = -1
	body_layer.material = CanvasItemMaterial.new()
	body_layer.draw.connect(_draw_body)
	add_child(body_layer)
	tanjiro = TanjiroVfx.new()
	tanjiro.name = "TanjiroVfx"
	tanjiro.combat = combat
	tanjiro.camera = camera
	tanjiro.actors = actors
	tanjiro.glow = glow
	add_child(tanjiro)

func _rebuilt(move: Resource) -> bool:
	return tanjiro != null and tanjiro.handles(move)

func consume(events: Array) -> void:
	if tanjiro != null:
		tanjiro.consume(events)
	# A tech also emits clash for the combat contract; render one clear escape cue.
	var tech := events.any(func(event: Dictionary) -> bool: return event.type == "throw_tech")
	for event: Dictionary in events:
		if event.type == "round_end":
			if not event.get("knockout", false):
				reset_effects()
			break # Queue a redraw even while the lethal frame is frozen.
		if event.type == "throw_tech":
			pulses.append({"kind":"tech", "at":event.position, "life":0.30, "duration":0.30, "color":Color("a8f3ef")})
			continue
		if event.type == "meter_empty" or (event.type == "meter" and int(event.amount) < 0):
			var f = combat.fighters[event.attacker]
			pulses.append({"kind":"empty" if event.type == "meter_empty" else "spend", "at":Vector2(f.x,f.y-4), "life":0.32, "duration":0.32,
				"color":Color("ed7f89") if event.type == "meter_empty" else Color("edd7a2")})
			continue
		if event.type not in ["hit", "throw", "block", "clash"] or (tech and event.type == "clash"):
			continue
		var blocked: bool = event.type in ["block", "clash"]
		var move: Resource = combat.moves.get(event.get("move", ""))
		var segment: int = event.get("segment", 0)
		var repeated: bool = move != null and move.hit_count() > 1 and segment > 0 and segment < move.hit_count() - 1
		var intensity := 0.42 if repeated else (0.70 if move != null and move.kind == "light" else 1.0)
		var effect_scale: float = move.presentation.particle_scale if move != null and move.presentation != null else 1.0
		intensity *= effect_scale
		var color := Color("9ccbdd") if blocked else (Color("f9a075") if event.type == "throw" else Color("ffe1a2"))
		if not blocked and move != null and move.presentation != null and move.kind in ["skill","super","max"]:
			color = move.presentation.color.lightened(0.35)
		for n in range(5 if repeated else (7 if blocked else int(12*effect_scale))):
			var angle: float = float(n) * 2.399 + time
			var speed: float = (28 + n % 5 * 12) * intensity
			sparks.append({"at": event.position, "velocity": Vector2(cos(angle), sin(angle)) * speed, "life": 0.12 + n % 3 * 0.035, "color": color, "length": 1 + n % 3})
		while sparks.size() > 112:
			sparks.pop_front()
		# Rebuilt character effects draw their own contact light; keep the shared
		# records (and their timing) but render them quietly underneath.
		var quiet: bool = move != null and _rebuilt(move)
		rings.append({"at": event.position, "life":0.18, "color":color, "block":blocked, "throw":event.type == "throw", "intensity":intensity,
			"facing":int(combat.fighters[event.attacker].facing) if event.has("attacker") else 1, "quiet":quiet})
		if rings.size() > 5:
			rings.pop_front()
		trauma = maxf(trauma, (0.04 if blocked else 0.16) * intensity)
		var attacker = combat.fighters[event.attacker] if event.has("attacker") else null
		var facing: int = int(attacker.facing) if attacker != null else 1
		if event.type == "clash":
			flashes.append({"at": event.position, "life": 0.16, "duration": 0.16, "radius": 30.0 * intensity, "color": Color("fff0c2")})
			_spawn_streaks(event.position, 10, 26.0 * intensity, 1.2, Color("ffe2a0"), 0.15, facing, true)
		elif blocked:
			flashes.append({"at": event.position, "life": 0.12, "duration": 0.12, "radius": 20.0 * intensity, "color": Kit.GUARD})
			shards.append({"at": event.position, "life": 0.2, "duration": 0.2, "facing": facing, "intensity": intensity})
		else:
			var heavy: bool = move != null and move.kind in ["heavy", "skill", "super", "max"]
			_spawn_hit(event.position, color, intensity, repeated, heavy, facing, _flavor(attacker), move != null and move.is_super(), quiet)
			if event.type == "throw":
				for n in range(6):
					var side := -1.0 if n % 2 == 0 else 1.0
					motes.append({"kind": "dust", "at": event.position + Vector2(side * 4, 6), "velocity": Vector2(side * (24 + n * 6), -6),
						"life": 0.32, "duration": 0.32, "size": 3.0 + n % 3, "color": Color(0.8, 0.82, 0.86)})
	while pulses.size() > 6:
		pulses.pop_front()
	while flashes.size() > 10:
		flashes.pop_front()
	while streaks.size() > 80:
		streaks.pop_front()
	while shards.size() > 4:
		shards.pop_front()
	while motes.size() > 120:
		motes.pop_front()
	queue_redraw()
	if body_layer != null:
		body_layer.queue_redraw()

func reset_effects() -> void:
	sparks.clear()
	rings.clear()
	pulses.clear()
	flashes.clear()
	streaks.clear()
	shards.clear()
	motes.clear()
	screen_flash = 0
	trauma = 0
	time = 0
	if tanjiro != null:
		tanjiro.reset()

func _process(delta: float) -> void:
	delta *= playback_speed
	if freeze:
		return
	time += delta
	if tanjiro != null:
		tanjiro.frac = Engine.get_physics_interpolation_fraction() if tanjiro.interpolate else 0.0
		tanjiro.advance(delta)
	trauma = maxf(0, trauma - delta * 1.6)
	for spark: Dictionary in sparks:
		spark.life -= delta
		spark.at += spark.velocity * delta
		spark.velocity.y += 110 * delta
	sparks = sparks.filter(func(p: Dictionary) -> bool: return p.life > 0)
	for ring: Dictionary in rings:
		ring.life -= delta
	rings = rings.filter(func(p: Dictionary) -> bool: return p.life > 0)
	for pulse: Dictionary in pulses:
		pulse.life -= delta
	pulses = pulses.filter(func(p: Dictionary) -> bool: return p.life > 0)
	for list in [flashes, streaks, shards]:
		for item: Dictionary in list:
			item.life -= delta
	flashes = flashes.filter(func(p: Dictionary) -> bool: return p.life > 0)
	streaks = streaks.filter(func(p: Dictionary) -> bool: return p.life > 0)
	shards = shards.filter(func(p: Dictionary) -> bool: return p.life > 0)
	for mote: Dictionary in motes:
		mote.life -= delta
		mote.at += mote.velocity * delta
		mote.velocity.y += float({"drop": 260.0, "petal": -40.0, "dust": -10.0}.get(mote.kind, 0.0)) * delta
		mote.velocity *= 1.0 - minf(0.9, delta * (3.0 if mote.kind == "dust" else 0.8))
	motes = motes.filter(func(p: Dictionary) -> bool: return p.life > 0)
	screen_flash = maxf(0, screen_flash - delta / 0.09)
	queue_redraw()
	if body_layer != null:
		body_layer.queue_redraw()

func _effect(id: String, bounds: Rect2, color: Color = Color.WHITE, uv_rotation: float = 0.0, flip_h: bool = false) -> void:
	if not textures.has(id):
		return
	if is_zero_approx(uv_rotation) and not flip_h:
		draw_texture_rect(textures[id], bounds, false, color)
		return
	# Rotate inside the attack envelope instead of rotating a quad past its edges.
	var corners := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for corner in corners:
		vertices.append(bounds.position + corner * bounds.size)
		uvs.append(effect_uv(corner, uv_rotation, flip_h))
	draw_polygon(vertices, PackedColorArray([color]), uvs, textures[id])

func _lightning(tail: Vector2, tip: Vector2, width: float, color: Color, tail_opacity: float = 1.0) -> void:
	if not textures.has("thunder"):
		return
	# Preserve the original texture: branches at the tail, a needle at the front.
	var direction := (tip - tail).normalized()
	var normal := Vector2(-direction.y, direction.x) * width * 0.5
	var vertices := PackedVector2Array([tail - normal, tip - normal, tip + normal, tail + normal])
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var faded := Color(color, color.a * tail_opacity)
	draw_polygon(vertices, PackedColorArray([faded, color, color, faded]), uvs, textures.thunder)

func _thunder_dash(attack: Rect2, strength: float) -> void:
	# The spear ends at the active forward reach; the broad rear wake conveys speed.
	var tip := Vector2(attack.end.x, attack.get_center().y)
	var length := attack.size.x + 28
	_lightning(tip - Vector2(length, 0), tip, attack.size.y * 0.75, Color(1, 0.95, 0.72, strength), 0.25)

func _iai_slash(attack: Rect2, strength: float) -> void:
	# Keep a straight 45-degree upstroke. Move it outward along the blade and
	# shorten it so the broad base clears the feet; only the fine tip glows past reach.
	var center := attack.get_center() + Vector2(12, 4)
	var direction := Vector2(1, -1).normalized()
	var half_length := attack.size.y * 0.51
	_lightning(center - direction * half_length, center + direction * half_length,
		attack.size.x * 0.4, Color(1, 0.89, 0.59, strength * 0.9))

func _draw_normal_cut(id: String, progress: float, tint: Color = Color(0.53, 0.73, 1.0), flavor: String = "neutral") -> void:
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
	var opacity := 0.5 + sin(progress * PI) * 0.5
	_draw_cut_ribbon(points, normals, taper, 7.5 if heavy else 4.8, Color(tint, opacity * 0.13))
	_draw_cut_ribbon(points, normals, taper, 3.4 if heavy else 2.2, Color(tint.lightened(0.3), opacity * 0.4))
	_draw_cut_ribbon(points, normals, taper, 1.2 if heavy else 0.75, Color(1.0, 0.98, 0.92, opacity * 0.86))
	var head: Vector2 = points[int(CUT_SEGMENTS * 0.86)]
	_glow_at(head, 9.0 if heavy else 6.0, Color(tint.lightened(0.4), opacity * 0.42))
	_cut_flavor(flavor, points, normals, progress, tint, heavy)

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

func _ellipse(bounds: Rect2, start: float, length: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for n in range(37):
		var angle := start + length * n / 36.0
		points.append(bounds.get_center() + Vector2(cos(angle),sin(angle)) * bounds.size * 0.5)
	draw_polyline(points, color, width, true)

func effect_uv(corner: Vector2, angle: float, flip_h: bool) -> Vector2:
	var uv := (corner - Vector2.ONE * 0.5).rotated(angle) + Vector2.ONE * 0.5
	if flip_h:
		uv.x = 1.0 - uv.x
	return uv

func element_angle(move: Resource, progress: float, segment: int = 0) -> float:
	# Most blood profiles mirror the authored crest into local forward. Rising
	# reverses both the UV angle and source reflection to mirror the whole arc.
	# The outer fighter transform then handles either facing direction.
	match move.presentation.effect_motion:
		"forward": return lerpf(-0.12, 0.12, progress)
		"rising": return -lerpf(0.65, 1.35, progress) # Mirror the already-rotated arc in local X.
		"sweep": return lerpf(-0.70, 0.70, progress)
		"burst": return lerpf(-0.20, 0.20, progress)
		"flurry": return lerpf(-0.55, 0.55, progress) * (1 if segment % 2 == 0 else -1)
	return 0.0

func _profile_shape(move: Resource) -> String:
	return move.presentation.shape if move.presentation != null else move.effect()

func _charge(fighter: RefCounted, color: Color) -> void:
	var move: Resource = fighter.move
	if not move.is_super() or fighter.move_frame >= move.startup:
		return
	var max_move: bool = move.kind == "max"
	var ready: float = 1.0 - float(combat.super_freeze) / maxi(1,move.freeze_frames)
	var radius := 19.0 + ready * (13.0 if max_move else 7.0)
	_ellipse(Rect2(-radius,-7,radius*2,11), -0.5, PI*1.5, Color(color,0.45),1.0)
	if max_move:
		_ellipse(Rect2(-radius-4,-10,radius*2+8,17),1.8,PI*1.4,Color(color.lightened(0.6),0.34),0.7)
		for side in [-1,1]:
			draw_line(Vector2(side*12,-12),Vector2(side*18,-38),Color(color,0.18),1.0,true)
	# Rotating ground sigil: outer ring with notches and an inner counter ring.
	var spin := ready * (2.4 if max_move else 1.6)
	var sigil := Vector2(radius * 1.3, 5.5)
	_ellipse(Rect2(-sigil.x, -sigil.y, sigil.x * 2, sigil.y * 2), spin, TAU, Color(color.lightened(0.3), 0.32 + ready * 0.3), 0.7)
	_ellipse(Rect2(-sigil.x * 0.7, -sigil.y * 0.7, sigil.x * 1.4, sigil.y * 1.4), -spin, PI * 1.6, Color(color, 0.3), 0.5)
	for n in range(12):
		var a := spin + n * TAU / 12
		var on := Vector2(cos(a) * sigil.x, sin(a) * sigil.y)
		draw_line(on, on * 1.12, Color(color.lightened(0.5), 0.5 * ready), 0.6, true)

func _water_dragon(attack: Rect2, progress: float, segment: int, color: Color) -> void:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var taper := PackedFloat32Array()
	for n in range(41):
		var u := n / 40.0
		var angle := u * TAU + segment * 0.8 - progress * 1.1
		points.append(Vector2(lerpf(attack.position.x,attack.end.x-5,u),attack.get_center().y+sin(angle)*attack.size.y*0.31))
		normals.append(Vector2(-cos(angle)*0.25,1).normalized())
		taper.append(sin(u*PI)*0.8+0.15)
	_draw_cut_ribbon(points,normals,taper,6.0,Color(color,0.24))
	_draw_cut_ribbon(points,normals,taper,2.0,Color(color.lightened(0.5),0.48))
	_draw_cut_ribbon(points,normals,taper,0.55,Color("defbff"))
	var head: Vector2 = points[-3]
	_effect("water-slash",Rect2(head-Vector2(12,12),Vector2(18,24)),Color(color,0.45),PI)

func _draw_attack(fighter: RefCounted) -> void:
	var move: Resource = fighter.move
	var color: Color = move.presentation.color if move.presentation != null else Color("c4e7ff")
	var tint := _accent(fighter)
	var flavor := _flavor(fighter)
	_charge(fighter,color)
	var segment: int = move.segment(fighter.move_frame)
	if segment < 0:
		return
	var progress: float = move.segment_progress(fighter.move_frame)
	var attack: Rect2 = move.box
	var shape := _profile_shape(move)
	var strength: float = (0.62 + sin(progress * PI) * 0.32) * (move.presentation.glow_strength if move.presentation != null else 0.55)
	match shape:
		"blood", "shockwave":
			var key: String = move.presentation.texture_key
			var bounds := attack.grow(3)
			if move.projectile_speed > 0: bounds = Rect2(16,-47,29,28)
			_effect(key,bounds,Color(color,0.30),element_angle(move,progress,segment),move.presentation.texture_flip_h)
			_element_motes(bounds,progress,color,18 if move.is_super() else 8)
			if shape == "blood":
				_embers(bounds,progress,Color(1.0,0.45,0.66),12 if move.is_super() else 6)
			else:
				_compass_ring(bounds.get_center(),bounds.size.length()*(0.18+progress*0.22),progress,color)
			if not move.presentation.sigil_texture_key.is_empty():
				_effect(move.presentation.sigil_texture_key,Rect2(-45,-9,90,18),Color(color,0.32))
		"water_slash":
			# The detached projectile is the only hitbox. A small spray marks release.
			_effect("water-slash-spray",Rect2(13,-43,30,20),Color(1,1,1,0.28*(1-progress*0.5)))
		"water_wheel":
			_effect("water-wheel",attack.grow(5),Color(color,strength*0.45),progress*TAU)
			_element_motes(attack,progress,color,16)
			_ellipse(attack.grow(-3),progress*TAU,PI*1.35,Color(color.lightened(0.5),0.62),1.4)
			_droplets(attack,progress,color,14)
		"water_vortex":
			var plane := Rect2(attack.position.x-6,-48,attack.size.x+12,44)
			_effect("water-wheel",plane,Color(color,0.28),progress*TAU)
			_ellipse(plane.grow(-2),progress*TAU,PI*1.55,Color(color.lightened(0.45),0.57),1.7)
			_ellipse(Rect2(plane.position+Vector2(7,-7),plane.size-Vector2(14,4)),-progress*TAU,PI,Color(color,0.25),0.8)
			_droplets(plane,progress,color,16)
		"water_dragon":
			_water_dragon(attack,progress,segment,color)
			_element_motes(attack,progress,color,24)
			_droplets(attack,progress,color,22)
			_effect("water-dragon",attack.grow(7),Color(color,0.20))
		"sun_arc", "flame":
			_effect("sun-flame-arc",attack.grow(10),Color(1,0.67,0.35,0.24),-0.75+progress*TAU)
			var angle := -1.7+progress*TAU
			_ellipse(attack.grow(-5),angle-0.25,PI*1.65,Color(0.95,0.13,0.025,0.27),5.0)
			_ellipse(attack.grow(-6),angle,PI*1.45,Color(1,0.46,0.075,0.64),2.7)
			_ellipse(attack.grow(-7),angle+0.08,PI*1.15,Color(1,0.87,0.46,0.85),0.9)
			for n in range(16):
				var a := angle+n*0.5
				var at := attack.get_center()+Vector2(cos(a),sin(a))*attack.size*0.40
				draw_line(at,at-Vector2(cos(a),sin(a))*3,Color(1,0.60,0.1,0.4),1.0,true)
			_embers(attack,progress,Color(1.0,0.62,0.22),14)
		"body":
			_draw_body_strike(attack,progress,tint,flavor)
		"thunder":
			_thunder_dash(attack,strength)
			_element_motes(attack,progress,color,10)
			_crackle(attack,progress,color,2)
		"iai":
			_iai_slash(attack,strength)
			_crackle(attack,progress,color,2)
		"iai_return":
			var center := attack.get_center()
			_lightning(Vector2(attack.position.x,center.y+8),Vector2(attack.end.x,center.y-7 if segment==0 else center.y+3),15,Color(color,strength),0.35)
		"sixfold":
			var height: float = [-0.18,0.18,-0.28,0.0,0.24,-0.05][segment % 6]
			var tip := Vector2(attack.end.x,attack.get_center().y+height*attack.size.y)
			_lightning(Vector2(attack.position.x-12,attack.get_center().y-height*12),tip,18,Color(color,strength),0.32)
			_crackle(attack,progress,color,2)
		"godspeed":
			var y: float = attack.get_center().y
			_element_motes(attack,progress,color,26)
			_lightning(Vector2(attack.position.x-18,y+3),Vector2(attack.end.x,y-3),23,Color(color,0.55),0.23)
			_lightning(Vector2(attack.position.x,y+13),Vector2(attack.end.x-3,y-7),9,Color(1,0.79,0.35,0.42),0.20)
			_crackle(attack,progress,color,3)
		"blade":
			_draw_normal_cut(move.effect(),progress,tint,flavor)
		_:
			_draw_normal_cut(move.effect(),progress,tint,flavor)

func _draw() -> void:
	if camera == null or combat == null:
		return
	if combat.phase in ["fight", "round_end"]:
		for fighter in combat.fighters:
			if fighter.move == null or not combat.presents_attack(fighter.slot) or _rebuilt(fighter.move):
				continue
			draw_set_transform(camera.point(Vector2(fighter.x,fighter.y)),0,Vector2(camera.zoom*fighter.facing,camera.zoom))
			_draw_attack(fighter)
		for projectile in combat.projectiles:
			var move: Resource = combat.moves[projectile.move]
			if _rebuilt(move):
				continue
			draw_set_transform(camera.point(Vector2(projectile.x,projectile.y)),0,Vector2(camera.zoom*projectile.facing,camera.zoom))
			var bounds: Rect2 = move.projectile_box
			var key := _projectile_key(move)
			# Authored vertical foam crest, without distorting the old horizontal slash.
			_effect(key,bounds,Color(0.78,0.95,1,0.28),PI if key=="water-slash" else 0.0)
			_glow_at(bounds.get_center(),bounds.size.length()*0.6,Color(0.55,0.85,1,0.18))
			var wake: float = move.projectile_lifetime - projectile.life
			for n in range(6):
				var drift := fposmod(wake*0.9+n/6.0,1.0)
				var at := Vector2(bounds.position.x-drift*16,lerpf(bounds.position.y+3,bounds.end.y-3,_hash(n+1.0)))
				draw_circle(at,0.5+_hash(n+3.0)*0.6,Color(0.8,0.96,1,(1-drift)*0.5),true,-1,true)
			if key != "water-slash":
				var age: float = move.projectile_lifetime - projectile.life
				for n in range(3):
					var drift := fposmod(age*0.08+n/3.0,1.0)
					var at := Vector2(bounds.position.x-drift*6,lerpf(bounds.position.y+5,bounds.end.y-5,n/2.0))
					draw_line(at,at+Vector2(1.7,0.6),Color(0.77,0.96,1,(1-drift)*0.20),0.65,true)
	draw_set_transform(Vector2.ZERO)
	for spark: Dictionary in sparks:
		var at: Vector2 = camera.point(spark.at)
		var color: Color = spark.color
		color.a = clampf(spark.life/0.18,0,0.7)
		draw_line(at,at-spark.velocity.normalized()*spark.length*camera.zoom,color,1.0,true)
	for ring: Dictionary in rings:
		var at: Vector2 = camera.point(ring.at)
		var amount: float = 1.0-ring.life/0.18
		var color: Color = ring.color
		color.a = (1-amount)*0.55*ring.intensity*(0.35 if ring.get("quiet",false) else 1.0)
		if not ring.block:
			var diameter: float = (24+amount*17)*camera.zoom*ring.intensity
			_effect("impact",Rect2(at-Vector2.ONE*diameter/2,Vector2.ONE*diameter),color)
		else:
			var angle: float = PI if ring.facing > 0 else 0.0
			draw_arc(at,(5+amount*6)*camera.zoom,angle-1.1,angle+1.1,20,color,1.5,true)
		if ring.throw:
			draw_arc(at,(8+amount*14)*camera.zoom,0,TAU,28,color,1.0,true)
	for pulse: Dictionary in pulses:
		var at: Vector2 = camera.point(pulse.at)
		var progress: float = 1-pulse.life/pulse.duration
		var color: Color = Color(pulse.color,(1-progress)*0.70)
		if pulse.kind == "tech":
			for side in [-1,1]:
				var end: Vector2 = at+Vector2(side*(9+progress*13)*camera.zoom,0)
				draw_line(at+Vector2(side*4*camera.zoom,0),end,color,1.6,true)
				draw_arc(end,4*camera.zoom,-1.0,1.0,12,color,1.0,true)
		elif pulse.kind == "spend":
			_ellipse(Rect2(at-Vector2(24,3)*camera.zoom,Vector2(48,6)*camera.zoom),0,TAU,color,1.0)
		else:
			for n in range(3):
				draw_line(at+Vector2(-8+n*6,-3)*camera.zoom,at+Vector2(-8+n*6,-7)*camera.zoom,color,1.7,true)
	_draw_impacts()

func _element_motes(attack: Rect2, progress: float, color: Color, count: int) -> void:
	for n in range(count):
		var a := n*2.399+progress*2.2
		var outward := 0.43+progress*0.18
		var at := attack.get_center()+Vector2(cos(a),sin(a))*attack.size*outward
		var alpha := sin(progress*PI)*(0.25+n%3*0.13)
		draw_line(at,at-Vector2(cos(a),sin(a))*(2+n%4),Color(color.lightened(0.55),alpha),0.8+n%2*0.4,true)

func _draw_body() -> void:
	if camera == null or combat == null or combat.phase not in ["fight", "round_end"]:
		return
	for fighter in combat.fighters:
		var move: Resource = fighter.move
		if move == null or not combat.presents_attack(fighter.slot) or move.segment(fighter.move_frame) < 0 or move.presentation == null or _rebuilt(move):
			continue
		var profile: Resource = move.presentation
		var shape := _profile_shape(move)
		var key: String = profile.texture_key + "-body"
		if not textures.has(key):
			continue
		var progress: float = move.segment_progress(fighter.move_frame)
		var opacity: float = profile.body_opacity * (0.76 + sin(progress * PI) * 0.24)
		var attack: Rect2 = move.box
		var bounds := attack
		var angle := 0.0
		body_layer.draw_set_transform(camera.point(Vector2(fighter.x,fighter.y)),0,Vector2(camera.zoom*fighter.facing,camera.zoom))
		match shape:
			"blood", "shockwave":
				bounds = Rect2(16,-47,29,28) if move.projectile_speed > 0 else attack.grow(3)
				angle = element_angle(move,progress,move.segment(fighter.move_frame))
			"water_slash":
				bounds = Rect2(13,-43,30,20)
				opacity *= 0.68 * (1-progress*0.5)
			"water_wheel":
				bounds = attack.grow(4)
				angle = progress * TAU
			"water_vortex":
				bounds = Rect2(attack.position.x-6,-48,attack.size.x+12,44)
				angle = progress*TAU
			"water_dragon":
				bounds = attack.grow(5)
			"sun_arc", "flame":
				bounds = attack.grow(8)
				angle = -0.75 + progress * TAU
			"thunder", "godspeed", "sixfold", "iai", "iai_return":
				var center := attack.get_center()
				var tip := Vector2(attack.end.x,center.y)
				var tail := Vector2(attack.position.x-18,center.y)
				var thickness := 28.0 if shape=="godspeed" else 22.0
				if shape=="iai":
					tail = center + Vector2(-attack.size.y*0.33,attack.size.y*0.33)
					tip = center + Vector2(attack.size.y*0.33,-attack.size.y*0.33)
				elif shape=="sixfold":
					var sign_y: float = [-1.0,1.0,-0.7,0.0,0.7,-0.2][move.segment(fighter.move_frame)%6]
					tail.y += sign_y*10
					tip.y -= sign_y*12
				elif shape=="iai_return":
					tail.y+=8
					tip.y-=7
				_body_ribbon(key,tail,tip,thickness,Color(1,1,1,opacity))
				continue
			_:
				continue
		_body_texture(key,bounds,opacity,angle,profile.texture_flip_h)
	for projectile in combat.projectiles:
		var move: Resource = combat.moves[projectile.move]
		if _rebuilt(move):
			continue
		body_layer.draw_set_transform(camera.point(Vector2(projectile.x,projectile.y)),0,Vector2(camera.zoom*projectile.facing,camera.zoom))
		var key := _projectile_key(move)
		_body_texture(key+"-body",move.projectile_box,0.96,PI if key=="water-slash" else 0.0)
	body_layer.draw_set_transform(Vector2.ZERO)

func _projectile_key(move: Resource) -> String:
	if move.presentation != null and not move.presentation.projectile_texture_key.is_empty():
		return move.presentation.projectile_texture_key
	return "water-slash"

func _body_texture(key: String, bounds: Rect2, alpha: float, angle: float = 0.0, flip_h: bool = false) -> void:
	if not textures.has(key):
		return
	var corners := PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for corner in corners:
		vertices.append(bounds.position+corner*bounds.size)
		uvs.append(effect_uv(corner, angle, flip_h))
	body_layer.draw_polygon(vertices,PackedColorArray([Color(1,1,1,alpha)]),uvs,textures[key])

func _body_ribbon(key: String, tail: Vector2, tip: Vector2, width: float, color: Color) -> void:
	var normal := (tip-tail).normalized().orthogonal()*width*0.5
	body_layer.draw_polygon(PackedVector2Array([tail-normal,tip-normal,tip+normal,tail+normal]),
		PackedColorArray([Color(color,color.a*0.30),color,color,Color(color,color.a*0.30)]),
		PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]),textures[key])

# --- Impact layers and character flavor ------------------------------------------

static func _hash(n: float) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)

func _accent(fighter: RefCounted) -> Color:
	var definition: Resource = combat.definition(fighter)
	if fighter.awakening_ticks > 0 and definition.awakening != null:
		return definition.awakening.color
	return definition.accent

func _flavor(fighter: RefCounted) -> String:
	return FLAVORS.get(str(fighter.character), "neutral") if fighter != null else "neutral"

func _glow_at(at: Vector2, radius: float, color: Color) -> void:
	if glow != null and radius > 0 and color.a > 0:
		draw_texture_rect(glow, Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2), false, color)

func _spawn_streaks(at: Vector2, count: int, length: float, line_width: float, color: Color, life: float, facing: int, around: bool, quiet: bool = false) -> void:
	for n in range(count):
		var spread := (_hash(n * 1.7 + at.x * 0.13 + at.y) - 0.5) * (TAU if around or n % 3 == 0 else 2.4)
		streaks.append({"at": at, "angle": (0.0 if facing > 0 else PI) + spread,
			"length": length * (0.6 + _hash(n + at.y * 0.7) * 0.8), "width": line_width, "life": life, "duration": life, "color": color, "quiet": quiet})

func _spawn_hit(at: Vector2, color: Color, intensity: float, repeated: bool, heavy: bool, facing: int, flavor: String, super_move: bool, quiet: bool = false) -> void:
	var life := 0.2 if heavy else 0.14
	flashes.append({"at": at, "life": life, "duration": life, "radius": (16.0 if repeated else (27.0 if heavy else 19.0)) * intensity, "color": color.lightened(0.2), "quiet": quiet})
	_spawn_streaks(at, 4 if repeated else (11 if heavy else 7), (18.0 if repeated else (32.0 if heavy else 24.0)) * intensity,
		(1.5 if heavy else 1.1) * intensity, color.lightened(0.35), life, facing, false, quiet)
	var count := 3 if repeated else (8 if heavy else 5)
	for n in range(count):
		var lift := -40.0 - _hash(n + at.x) * 70.0
		var push := float(facing) * (20.0 + _hash(n * 3.1 + at.y) * 60.0) * (1.0 if n % 3 else -0.5)
		match flavor:
			"water":
				motes.append({"kind": "drop", "at": at, "velocity": Vector2(push, lift), "life": 0.3, "duration": 0.3,
					"size": 1.2 + _hash(n + 5.0) * 1.0, "color": Color(0.72, 0.93, 1.0)})
			"thunder":
				motes.append({"kind": "bolt", "at": at, "velocity": Vector2(push, lift * 0.5).normalized() * 14.0, "life": 0.12, "duration": 0.12,
					"size": 8.0 + _hash(n + 2.0) * 8.0, "color": Color(1.0, 0.94, 0.6)})
			"blood":
				motes.append({"kind": "petal", "at": at, "velocity": Vector2(push * 0.6, lift * 0.6), "life": 0.32, "duration": 0.32,
					"size": 1.4 + _hash(n + 7.0), "color": Color(1.0, 0.5, 0.72)})
	if flavor == "compass" and not repeated:
		motes.append({"kind": "ring", "at": at, "velocity": Vector2.ZERO, "life": 0.22, "duration": 0.22, "size": 5.0 * intensity, "color": Color(0.55, 0.88, 1.0)})
	if super_move and not repeated:
		screen_flash = 1.0

func _draw_impacts() -> void:
	for flash: Dictionary in flashes:
		var at: Vector2 = camera.point(flash.at)
		var amount: float = 1.0 - flash.life / flash.duration
		var radius: float = flash.radius * camera.zoom * (0.55 + amount * 0.6)
		var alpha: float = (1.0 - amount) * (0.3 if flash.get("quiet", false) else 0.95)
		_glow_at(at, radius, Color(flash.color, alpha))
		_glow_at(at, radius * 0.38, Color(1, 1, 1, alpha))
	for streak: Dictionary in streaks:
		if streak.get("quiet", false):
			continue
		var at: Vector2 = camera.point(streak.at)
		var amount: float = 1.0 - streak.life / streak.duration
		var direction := Vector2.from_angle(streak.angle)
		var reach: float = streak.length * camera.zoom
		var start := at + direction * reach * (0.12 + amount * 0.3)
		var tip := at + direction * reach * (0.5 + amount * 0.5)
		var normal: Vector2 = direction.orthogonal() * float(streak.width) * camera.zoom * (1.0 - amount * 0.7)
		draw_colored_polygon(PackedVector2Array([start + normal, tip, start - normal]), Color(streak.color, (1.0 - amount) * 0.9))
	for shard: Dictionary in shards:
		var at: Vector2 = camera.point(shard.at)
		var amount: float = 1.0 - shard.life / shard.duration
		var toward: float = PI if int(shard.facing) > 0 else 0.0
		var alpha: float = (1.0 - amount) * float(shard.intensity)
		# Translucent hex shield facing the attacker, then layered rims.
		var shield := PackedVector2Array([at])
		for k in range(5):
			shield.append(at + Vector2.from_angle(toward - 1.1 + k * 0.55) * (9.0 + amount * 9.0) * camera.zoom)
		draw_colored_polygon(shield, Color(Kit.GUARD, alpha * 0.16))
		for n in range(3):
			var radius: float = (7.0 + n * 3.0 + amount * 9.0) * camera.zoom
			draw_arc(at, radius, toward - 1.15, toward + 1.15, 6, Color(Kit.GUARD.lightened(0.2), alpha * (0.95 - n * 0.25)), 3.0 - n * 0.7, true)
		for n in range(5):
			var a := toward + (n - 2) * 0.42
			var from: Vector2 = at + Vector2.from_angle(a) * (6.0 + amount * 6.0) * camera.zoom
			draw_line(from, from + Vector2.from_angle(a) * (3.0 + amount * 5.0) * camera.zoom, Color(0.85, 0.95, 1.0, alpha * 0.8), 1.2, true)
	for mote: Dictionary in motes:
		var at: Vector2 = camera.point(mote.at)
		var alpha: float = clampf(mote.life / mote.duration, 0, 1)
		var color: Color = mote.color
		match mote.kind:
			"drop":
				draw_circle(at, float(mote.size) * camera.zoom * 0.5, Color(color, alpha * 0.85), true, -1, true)
			"petal":
				draw_colored_polygon(Kit.diamond_points(at, float(mote.size) * camera.zoom * 0.5, 1.7), Color(color, alpha))
			"bolt":
				var velocity: Vector2 = mote.velocity
				var direction: Vector2 = velocity.normalized() if velocity.length() > 0 else Vector2.RIGHT
				var points := PackedVector2Array([at])
				for k in range(1, 5):
					var jitter := (_hash(k + float(mote.size) * 3.0 + floorf(time * 30.0)) - 0.5) * 6.0
					points.append(at + direction * float(mote.size) * camera.zoom * k / 4.0 + direction.orthogonal() * jitter)
				draw_polyline(points, Color(color, alpha), 1.4, true)
			"ring":
				var radius: float = (float(mote.size) + (1.0 - alpha) * 12.0) * camera.zoom
				draw_arc(at, radius, 0, TAU, 40, Color(color, alpha * 0.8), 1.6, true)
				for n in range(8):
					var direction := Vector2.from_angle(n * TAU / 8 + (1.0 - alpha))
					draw_line(at + direction * radius * 0.55, at + direction * radius * 1.15, Color(color, alpha * 0.7), 1.2, true)
			"dust":
				draw_circle(at, float(mote.size) * camera.zoom * (1.6 - alpha * 0.6), Color(color, alpha * 0.12), true, -1, true)
	if screen_flash > 0:
		draw_rect(Rect2(-40, -40, 1360, 800), Color(1.0, 0.96, 0.88, 0.12 * screen_flash))

func _cut_flavor(flavor: String, points: PackedVector2Array, normals: PackedVector2Array, progress: float, tint: Color, heavy: bool) -> void:
	var count := 7 if heavy else 4
	match flavor:
		"water":
			for i in range(count):
				var index := clampi(int((0.25 + i * 0.1) * CUT_SEGMENTS), 1, CUT_SEGMENTS - 1)
				var spread := 2.5 + progress * (7.0 + _hash(i) * 6.0)
				var side := 1.0 if i % 2 == 0 else -0.6
				var at: Vector2 = points[index] + normals[index].normalized() * spread * side + Vector2(0, progress * progress * 6.0 * _hash(i + 3.0))
				draw_circle(at, (0.55 + _hash(i + 7.0) * 0.6) * (1.0 - progress * 0.4), Color(0.8, 0.95, 1.0, 0.7 * (1.0 - progress)), true, -1, true)
		"thunder":
			var frame := floorf(time * 24.0)
			for i in range(3 if heavy else 2):
				var index := clampi(int((0.3 + i * 0.22) * CUT_SEGMENTS), 1, CUT_SEGMENTS - 2)
				var start: Vector2 = points[index]
				var across := (points[index + 1] - points[index - 1]).normalized().orthogonal()
				var bolt := PackedVector2Array([start])
				for k in range(1, 5):
					bolt.append(start + across * k * 2.6 + across.orthogonal() * (_hash(frame + i * 7.0 + k) - 0.5) * 4.0)
				draw_polyline(bolt, Color(1.0, 0.95, 0.65, 0.8 * (1.0 - progress * 0.5)), 0.6, true)
		"blood":
			for i in range(count):
				var index := clampi(int((0.2 + i * 0.11) * CUT_SEGMENTS), 1, CUT_SEGMENTS - 1)
				var at: Vector2 = points[index] + Vector2((_hash(i + 2.0) - 0.5) * 4.0, -progress * (6.0 + _hash(i) * 8.0))
				draw_colored_polygon(Kit.diamond_points(at, 0.9 + _hash(i + 5.0) * 0.8, 1.6), Color(1.0, 0.45, 0.65, 0.75 * (1.0 - progress)))

func _draw_body_strike(attack: Rect2, progress: float, tint: Color, flavor: String) -> void:
	var at := Vector2(minf(attack.end.x - 5, attack.get_center().x + 5), attack.get_center().y)
	var fade := 1.0 - progress
	var swing := sin(progress * PI)
	for n in range(3):
		var radius := 7.0 + n * 2.6 + progress * 3.0
		draw_arc(at - Vector2(3, 0), radius, -0.9 - n * 0.12, 0.9 + n * 0.12, 18, Color(tint, (0.42 - n * 0.11) * swing), 2.2 - n * 0.5, true)
	draw_arc(at - Vector2(3, 0), 6.0 + progress * 3.0, -0.75, 0.75, 14, Color(1, 0.98, 0.94, 0.7 * swing), 0.7, true)
	for n in range(3):
		var y := at.y + (n - 1) * 3.5
		draw_line(Vector2(attack.position.x - 4, y), Vector2(at.x - 8, y), Color(tint, 0.22 * swing), 0.6, true)
	_glow_at(at, 10.0, Color(tint.lightened(0.3), 0.35 * swing))
	if flavor == "compass":
		_compass_ring(at, 4.0 + progress * 9.0, progress, tint)
	elif flavor == "blood":
		for n in range(5):
			var a := -0.8 + n * 0.4
			draw_colored_polygon(Kit.diamond_points(at + Vector2(cos(a), sin(a)) * (5.0 + progress * 10.0), 1.0, 1.7), Color(1.0, 0.5, 0.7, 0.7 * fade))

func _droplets(area: Rect2, progress: float, color: Color, count: int) -> void:
	var center := area.get_center()
	for n in range(count):
		var a := n * 2.399 + progress * 1.4
		var at := center + Vector2(cos(a), sin(a)) * area.size * (0.45 + progress * 0.35 + _hash(n) * 0.15)
		at.y += progress * progress * 8.0 * _hash(n + 1.0)
		draw_circle(at, 0.5 + _hash(n + 3.0) * 0.9, Color(color.lightened(0.6), sin(progress * PI) * (0.4 + _hash(n + 2.0) * 0.4)), true, -1, true)

func _crackle(area: Rect2, progress: float, color: Color, bolts: int) -> void:
	var frame := floorf(time * 24.0)
	for b in range(bolts):
		var y := lerpf(area.position.y, area.end.y, _hash(b + frame * 0.37))
		var points := PackedVector2Array()
		for k in range(7):
			var x := lerpf(area.position.x, area.end.x, k / 6.0)
			points.append(Vector2(x, y + (_hash(frame + b * 11.0 + k) - 0.5) * minf(area.size.y * 0.14, 5.0)))
		draw_polyline(points, Color(color.lightened(0.55), 0.4 * sin(progress * PI) + 0.08), 0.5, true)

func _embers(area: Rect2, progress: float, color: Color, count: int) -> void:
	for n in range(count):
		var a := n * 2.399 + progress * 3.0
		var at := area.get_center() + Vector2(cos(a), sin(a)) * area.size * (0.3 + 0.3 * _hash(n))
		at.y -= progress * (6.0 + 10.0 * _hash(n + 4.0))
		draw_colored_polygon(Kit.diamond_points(at, 0.7 + _hash(n + 2.0), 1.6), Color(color.lightened(0.35), sin(progress * PI) * (0.5 + 0.4 * _hash(n + 1.0))))

func _compass_ring(at: Vector2, radius: float, progress: float, color: Color) -> void:
	draw_arc(at, radius, 0, TAU, 48, Color(color.lightened(0.4), 0.6 * (1.0 - progress)), 0.8, true)
	for n in range(8):
		var direction := Vector2.from_angle(n * TAU / 8 + progress)
		draw_line(at + direction * radius * (0.35 if n % 2 == 0 else 0.7), at + direction * radius * 1.15, Color(color.lightened(0.5), 0.7 * (1.0 - progress)), 0.6, true)
