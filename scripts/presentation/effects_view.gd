extends Node2D
## Attack effects follow the actual move phase without changing combat timing.
# Sword ribbons follow the drawn blade. Skill reach is guided by move.box;
# lightning keeps its pointed silhouette and a softer movement wake.
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
var time: float = 0
var trauma: float = 0
var freeze: bool = false
var textures: Dictionary = {}
var body_layer: Node2D

func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	for id in ["water-slash", "water-wheel", "thunder", "impact", "water-dragon", "sun-flame-arc", "water-slash-body", "water-wheel-body", "thunder-body", "water-dragon-body", "sun-flame-arc-body"]:
		var path: String = "res://art/effects/%s.png" % id
		if ResourceLoader.exists(path):
			textures[id] = load(path)
	body_layer = Node2D.new()
	body_layer.z_index = -1
	body_layer.material = CanvasItemMaterial.new()
	body_layer.draw.connect(_draw_body)
	add_child(body_layer)

func consume(events: Array) -> void:
	# A tech also emits clash for the combat contract; render one clear escape cue.
	var tech := events.any(func(event: Dictionary) -> bool: return event.type == "throw_tech")
	for event: Dictionary in events:
		if event.type == "round_end":
			reset_effects()
			return
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
		rings.append({"at": event.position, "life":0.18, "color":color, "block":blocked, "throw":event.type == "throw", "intensity":intensity,
			"facing":int(combat.fighters[event.attacker].facing) if event.has("attacker") else 1})
		if rings.size() > 5:
			rings.pop_front()
		trauma = maxf(trauma, (0.04 if blocked else 0.16) * intensity)
	while pulses.size() > 6:
		pulses.pop_front()
	queue_redraw()
	if body_layer != null:
		body_layer.queue_redraw()

func reset_effects() -> void:
	sparks.clear()
	rings.clear()
	pulses.clear()
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
	for pulse: Dictionary in pulses:
		pulse.life -= delta
	pulses = pulses.filter(func(p: Dictionary) -> bool: return p.life > 0)
	queue_redraw()
	if body_layer != null:
		body_layer.queue_redraw()

func _effect(id: String, bounds: Rect2, color: Color = Color.WHITE, uv_rotation: float = 0.0) -> void:
	if not textures.has(id):
		return
	if is_zero_approx(uv_rotation):
		draw_texture_rect(textures[id], bounds, false, color)
		return
	# Rotate inside the attack envelope instead of rotating a quad past its edges.
	var corners := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for corner in corners:
		vertices.append(bounds.position + corner * bounds.size)
		uvs.append((corner - Vector2.ONE * 0.5).rotated(uv_rotation) + Vector2.ONE * 0.5)
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

func _ellipse(bounds: Rect2, start: float, length: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for n in range(37):
		var angle := start + length * n / 36.0
		points.append(bounds.get_center() + Vector2(cos(angle),sin(angle)) * bounds.size * 0.5)
	draw_polyline(points, color, width, true)

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
	_charge(fighter,color)
	var segment: int = move.segment(fighter.move_frame)
	if segment < 0:
		return
	var progress: float = move.segment_progress(fighter.move_frame)
	var strength: float = (0.62 + sin(progress * PI) * 0.32) * (move.presentation.glow_strength if move.presentation != null else 0.55)
	var attack: Rect2 = move.box
	var shape := _profile_shape(move)
	match shape:
		"water_slash":
			# The detached projectile is the only hitbox. A small spray marks release.
			_effect("water-slash",Rect2(17,-45,22,24),Color(color,0.25),PI)
		"water_wheel":
			_effect("water-wheel",attack.grow(5),Color(color,strength*0.45),-progress*TAU)
			_element_motes(attack,progress,color,16)
			_ellipse(attack.grow(-3),-progress*TAU,PI*1.35,Color(color.lightened(0.5),0.62),1.4)
		"water_vortex":
			var plane := Rect2(attack.position.x-6,-48,attack.size.x+12,44)
			_effect("water-wheel",plane,Color(color,0.28),progress*TAU)
			_ellipse(plane.grow(-2),progress*TAU,PI*1.55,Color(color.lightened(0.45),0.57),1.7)
			_ellipse(Rect2(plane.position+Vector2(7,-7),plane.size-Vector2(14,4)),-progress*TAU,PI,Color(color,0.25),0.8)
		"water_dragon":
			_water_dragon(attack,progress,segment,color)
			_element_motes(attack,progress,color,24)
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
		"body":
			var at := Vector2(minf(attack.end.x-7,attack.get_center().x+3),attack.get_center().y)
			draw_arc(at,6+progress*3,-0.6,0.6,10,Color(color,0.24),0.7,true)
		"thunder":
			_thunder_dash(attack,strength)
			_element_motes(attack,progress,color,10)
		"iai":
			_iai_slash(attack,strength)
		"iai_return":
			var center := attack.get_center()
			_lightning(Vector2(attack.position.x,center.y+8),Vector2(attack.end.x,center.y-7 if segment==0 else center.y+3),15,Color(color,strength),0.35)
		"sixfold":
			var height: float = [-0.18,0.18,-0.28,0.0,0.24,-0.05][segment % 6]
			var tip := Vector2(attack.end.x,attack.get_center().y+height*attack.size.y)
			_lightning(Vector2(attack.position.x-12,attack.get_center().y-height*12),tip,18,Color(color,strength),0.32)
		"godspeed":
			var y: float = attack.get_center().y
			_element_motes(attack,progress,color,26)
			_lightning(Vector2(attack.position.x-18,y+3),Vector2(attack.end.x,y-3),23,Color(color,0.55),0.23)
			_lightning(Vector2(attack.position.x,y+13),Vector2(attack.end.x-3,y-7),9,Color(1,0.79,0.35,0.42),0.20)
		"blade":
			_draw_normal_cut(move.effect(),progress)
		_:
			_draw_normal_cut(move.effect(),progress)

func _draw() -> void:
	if camera == null or combat == null:
		return
	if combat.phase == "fight":
		for fighter in combat.fighters:
			if fighter.move == null:
				continue
			draw_set_transform(camera.point(Vector2(fighter.x,fighter.y)),0,Vector2(camera.zoom*fighter.facing,camera.zoom))
			_draw_attack(fighter)
		for projectile in combat.projectiles:
			draw_set_transform(camera.point(Vector2(projectile.x,projectile.y)),0,Vector2(camera.zoom*projectile.facing,camera.zoom))
			var bounds: Rect2 = combat.moves[projectile.move].projectile_box
			# A vertical crest stays inside the projectile's exact collision envelope.
			_effect("water-slash",bounds,Color(0.48,0.87,1,0.60),PI)
			_ellipse(bounds.grow(-1),-1.15,2.3,Color(0.82,0.98,1,0.68),1.0)
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
		color.a = (1-amount)*0.55*ring.intensity
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

func _element_motes(attack: Rect2, progress: float, color: Color, count: int) -> void:
	for n in range(count):
		var a := n*2.399+progress*2.2
		var outward := 0.43+progress*0.18
		var at := attack.get_center()+Vector2(cos(a),sin(a))*attack.size*outward
		var alpha := sin(progress*PI)*(0.25+n%3*0.13)
		draw_line(at,at-Vector2(cos(a),sin(a))*(2+n%4),Color(color.lightened(0.55),alpha),0.8+n%2*0.4,true)

func _draw_body() -> void:
	if camera == null or combat == null or combat.phase != "fight":
		return
	for fighter in combat.fighters:
		var move: Resource = fighter.move
		if move == null or move.segment(fighter.move_frame) < 0 or move.presentation == null:
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
			"water_slash":
				bounds = Rect2(12,-47,29,29)
				opacity *= 0.5
			"water_wheel":
				bounds = attack.grow(4)
				angle = -progress * TAU
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
		_body_texture(key,bounds,opacity,angle)
	for projectile in combat.projectiles:
		body_layer.draw_set_transform(camera.point(Vector2(projectile.x,projectile.y)),0,Vector2(camera.zoom*projectile.facing,camera.zoom))
		_body_texture("water-slash-body",combat.moves[projectile.move].projectile_box,0.93,PI)
	body_layer.draw_set_transform(Vector2.ZERO)

func _body_texture(key: String, bounds: Rect2, alpha: float, angle: float = 0.0) -> void:
	if not textures.has(key):
		return
	var corners := PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for corner in corners:
		vertices.append(bounds.position+corner*bounds.size)
		uvs.append((corner-Vector2.ONE*0.5).rotated(angle)+Vector2.ONE*0.5)
	body_layer.draw_polygon(vertices,PackedColorArray([Color(1,1,1,alpha)]),uvs,textures[key])

func _body_ribbon(key: String, tail: Vector2, tip: Vector2, width: float, color: Color) -> void:
	var normal := (tip-tail).normalized().orthogonal()*width*0.5
	body_layer.draw_polygon(PackedVector2Array([tail-normal,tip-normal,tip+normal,tail+normal]),
		PackedColorArray([Color(color,color.a*0.30),color,color,Color(color,color.a*0.30)]),
		PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]),textures[key])
