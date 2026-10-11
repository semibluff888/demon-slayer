extends Node2D
## Runs from observed combat ticks, including super-freeze ticks. No rule writes.
const Style = preload("res://scripts/presentation/battle_style.gd")
const Kit = preload("res://scripts/ui/kit.gd")
const Brush = preload("res://scripts/ui/brush_stroke.gd")
const LINES = preload("res://scripts/ui/shaders/speed_lines.gdshader")
const TITLE_SIZE: int = 36
## Unillustrated titles are set in brush calligraphy at this native size.
const FALLBACK_SIZE: int = 58
const FALLBACK_HEIGHT: float = 78.0
const TITLE_LIFETIME: float = 1.12
# Upper portrait includes the complete hair, face, chin and earrings.
const FACE_REGION := Rect2(96, 0, 832, 752)
var combat: RefCounted
var catalog: RefCounted
var camera: RefCounted
var paused: bool = false:
	set(value):
		if paused == value:
			return
		paused = value
		queue_redraw()
		if titles != null:
			titles.queue_redraw()
		if combat != null:
			_sync_cut_ins()
var active: Array[Dictionary] = []
var seen: Array[int] = [-1, -1]
var dim_amount: float = 0.0
var dimmer: Node2D
var energy: Node2D
var elemental_textures: Dictionary = {}
var cut_in_textures: Dictionary = {}
var spheres: Array[ColorRect] = []
var focus_lines: ColorRect
var bands: Array = []
var titles: Node2D
var vignette: GradientTexture2D
var focus_color := Color.WHITE
var focus_center := Vector2(640, 360)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var shade := Gradient.new()
	shade.colors = PackedColorArray([Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.82), Color(1, 1, 1, 1)])
	shade.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vignette = GradientTexture2D.new()
	vignette.gradient = shade
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.1, 0.5)
	vignette.width = 256
	vignette.height = 144
	for id in ["water-wheel","sun-flame-arc"]:
		var path: String = "res://art/effects/"+str(id)+".png"
		if ResourceLoader.exists(path): elemental_textures[id] = load(path)
	for move: Resource in combat.moves.values():
		if move.presentation == null: continue
		var path: String = move.presentation.cut_in_path
		if not path.is_empty() and ResourceLoader.exists(path): cut_in_textures[move.id] = load(path)
		for key: String in [move.presentation.texture_key, move.presentation.sigil_texture_key]:
			if ResourceLoader.exists("res://art/effects/" + key + ".png"):
				elemental_textures[key] = load("res://art/effects/" + key + ".png")
	dimmer = Node2D.new()
	dimmer.z_index = -19
	dimmer.draw.connect(_draw_dimmer)
	add_child(dimmer)
	# Focus lines share the dimmer depth: over the stage, behind the fighters.
	focus_lines = ColorRect.new()
	focus_lines.size = Vector2(1280, 720)
	focus_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lines := ShaderMaterial.new()
	lines.shader = LINES
	lines.set_shader_parameter("inner", 0.16)
	lines.set_shader_parameter("density", 120.0)
	focus_lines.material = lines
	focus_lines.visible = false
	dimmer.add_child(focus_lines)
	energy = Node2D.new()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	energy.material = additive
	energy.draw.connect(_draw_energy)
	add_child(energy)
	for slot in range(2):
		var sphere := ColorRect.new()
		sphere.size = Vector2(184,184)
		sphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sphere_material := ShaderMaterial.new()
		sphere_material.shader = load("res://scripts/presentation/energy_sphere.gdshader")
		sphere.material = sphere_material
		sphere.visible = false
		energy.add_child(sphere)
		spheres.append(sphere)
	for slot in range(2):
		var band := Brush.new(2.3 + slot * 5.7)
		band.name = "CutInBand%d" % slot
		band.set_param("taper", 0.5)
		band.visible = false
		add_child(band)
		bands.append(band)
	titles = Node2D.new()
	titles.name = "Titles"
	titles.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	titles.draw.connect(_draw_titles)
	add_child(titles)

func consume(events: Array) -> void:
	for event: Dictionary in events:
		if event.type == "round_end" and not event.get("knockout", false):
			reset_effects()
			return
		if event.type != "super":
			continue
		var slot: int = event.attacker
		var f = combat.fighters[slot]
		if seen[slot] == f.attack_instance:
			continue
		seen[slot] = f.attack_instance
		active = active.filter(func(cue: Dictionary) -> bool: return int(cue.slot) != slot)
		var move: Resource = combat.moves[event.move]
		active.append({"slot":slot,"side":activation_side(slot),"instance":f.attack_instance,"move":move,"start":combat.ticks,"age":0.0,"duration":move.freeze_frames/60.0,"max":move.presentation.super_tier==2 if move.presentation != null else move.kind=="max"})
	_refresh()

func reset_effects() -> void:
	active.clear()
	seen.assign([-1,-1])
	dim_amount = 0
	for sphere in spheres: sphere.visible = false
	if focus_lines != null:
		focus_lines.visible = false
	for band in bands: band.visible = false
	queue_redraw()
	if dimmer != null:
		dimmer.queue_redraw()
	if energy != null:
		energy.queue_redraw()
	if titles != null:
		titles.queue_redraw()

func _process(_delta: float) -> void:
	if paused:
		return
	if combat == null or combat.phase not in ["fight", "round_end"]:
		if not active.is_empty():
			reset_effects()
		return
	_refresh()

func _refresh() -> void:
	dim_amount = 0
	for sphere in spheres: sphere.visible = false
	var remaining: Array[Dictionary] = []
	for cue: Dictionary in active:
		cue.age = maxf(0, float(combat.presentation_time_ticks() - int(cue.start))/60.0)
		var f = combat.fighters[int(cue.slot)]
		if cue.age >= TITLE_LIFETIME or f.state in ["hit","knockdown","thrown"] or f.attack_instance != cue.instance:
			continue
		remaining.append(cue)
		if camera != null and spheres.size()==2 and cue.age<float(cue.duration)+0.23:
			var sphere: ColorRect = spheres[int(cue.slot)]
			sphere.visible = true
			sphere.position = camera.point(Vector2(f.x+f.facing*6,f.y-39))-sphere.size/2
			var color: Color = cue.move.presentation.color if cue.move.presentation != null else Style.GOLD
			if cue.move.presentation != null and cue.move.presentation.shape=="godspeed": color = Color("65bdff")
			sphere.material.set_shader_parameter("element_color",color)
			sphere.material.set_shader_parameter("progress",float(cue.age)/float(cue.duration))
			sphere.material.set_shader_parameter("fade",1.0-clampf((float(cue.age)-float(cue.duration))/0.23,0,1))
		var fade := clampf(1.0-(float(cue.age)-float(cue.duration))/0.16,0,1)
		var strength := fade*(0.80 if cue.max else 0.66)
		if strength >= dim_amount and camera != null:
			focus_color = cue.move.presentation.color if cue.move.presentation != null else Style.GOLD
			focus_center = camera.point(Vector2(f.x+f.facing*6,f.y-39))
		dim_amount = maxf(dim_amount,strength)
	active = remaining
	_sync_cut_ins()
	queue_redraw()
	if dimmer != null:
		dimmer.queue_redraw()
	if energy != null:
		energy.queue_redraw()
	if titles != null:
		titles.queue_redraw()

func _draw_dimmer() -> void:
	# Radial falloff keeps the activation area readable while the stage sinks.
	if dim_amount>0:
		dimmer.draw_texture_rect(vignette,Rect2(-40,-40,1360,800),false,Color(0.004,0.007,0.018,dim_amount))

## Focus lines and cut-in bands follow the strongest active cue.
func _sync_cut_ins() -> void:
	if focus_lines == null:
		return
	focus_lines.visible = dim_amount > 0.01 and not paused
	if focus_lines.visible:
		var lines := focus_lines.material as ShaderMaterial
		lines.set_shader_parameter("intensity", clampf(dim_amount / 0.8, 0, 1))
		lines.set_shader_parameter("center", focus_center / Vector2(1280, 720))
		lines.set_shader_parameter("tint", Color(focus_color.lightened(0.4), 0.3))
		lines.set_shader_parameter("phase", float(combat.presentation_time_ticks()) / 60.0 if combat != null else 0.0)
	var both := active.size() > 1
	for slot in range(bands.size()):
		bands[slot].visible = false
	for cue: Dictionary in active:
		var band = bands[int(cue.slot)]
		var age: float = cue.age
		var alpha := clampf((TITLE_LIFETIME - age) / 0.22, 0, 1)
		var title := title_bounds(cue, both)
		var row := title.grow_individual(90, 10, 90, 10)
		if cue.max and age < 0.48:
			row = row.merge(face_bounds(cue, both).grow(12))
		var color: Color = cue.move.presentation.color if cue.move.presentation != null else Style.GOLD
		band.visible = alpha > 0 and not paused
		band.configure(row, Color(color.darkened(0.62), 0.88 * alpha), 18.0, Kit.ease_out(age / 0.12), int(cue.side) > 0)

func _draw_energy() -> void:
	if camera == null:
		return
	for cue: Dictionary in active:
		var age: float = cue.age
		var duration: float = cue.duration
		if age>duration+0.23:
			continue
		var f = combat.fighters[int(cue.slot)]
		var center: Vector2 = camera.point(Vector2(f.x+f.facing*6,f.y-39))
		var color: Color = cue.move.presentation.color if cue.move.presentation != null else Style.GOLD
		var charge := clampf(age/duration,0,1)
		var burst := clampf((age-duration)/0.23,0,1)
		var max_cue: bool = cue.max
		var radius := lerpf(62.0 if max_cue else 46.0,26.0,charge) if age<=duration else 26.0+burst*130.0
		var opacity := 1.0-burst
		for n in range(7,0,-1):
			var r := radius*float(n)/4.0
			energy.draw_circle(center,r,Color(color,opacity*0.018*(8-n)),true,-1,true)
		var shape: String = cue.move.presentation.shape if cue.move.presentation != null else ""
		var tex_key: String = cue.move.presentation.texture_key if shape in ["blood", "shockwave"] else ("sun-flame-arc" if shape=="sun_arc" else "water-wheel")
		if shape in ["water_dragon","sun_arc","blood","shockwave"] and elemental_textures.has(tex_key):
			energy.draw_set_transform(center,age*4.5)
			energy.draw_texture_rect(elemental_textures[tex_key],Rect2(-radius*1.4,-radius*1.4,radius*2.8,radius*2.8),false,Color(1,1,1,opacity*0.72))
			energy.draw_set_transform(Vector2.ZERO)
		else:
			for branch in range(6):
				var points := PackedVector2Array()
				for n in range(5):
					var angle := branch*TAU/6+n*0.10+sin(age*18+branch)*0.4
					var rr := radius*(0.88+n*0.13+sin(n*17.3+age*45+branch)*0.09)
					points.append(center+Vector2(cos(angle),sin(angle))*rr)
				energy.draw_polyline(points,Color(1,0.78,0.28,opacity*0.8),1.6,true)
		energy.draw_circle(center,8+charge*9,Color(color.lightened(0.75),opacity*0.65),true,-1,true)
		energy.draw_arc(center,radius,age*9,age*9+TAU*0.88,64,Color(color,opacity*0.9),2.5,true)
		energy.draw_arc(center,radius*1.22,-age*12,-age*12+TAU*0.69,64,Color(color.lightened(0.6),opacity*0.55),1.3,true)
		for n in range(32 if max_cue else 22):
			var angle := n*2.399+age*1.6
			var offset := fposmod(n*0.173+charge*1.6,1.0)
			var distance := lerpf(135 if max_cue else 100,18,offset) if age<=duration else lerpf(25,170,burst)
			var direction := Vector2(cos(angle),sin(angle))
			var at := center+direction*distance*Vector2(1.0,0.72)
			energy.draw_line(at,at+direction*(5+offset*14),Color(color.lightened(0.45),opacity*offset*0.75),1.4,true)
		if age>=duration:
			energy.draw_line(center-Vector2(85*(1+burst),0),center+Vector2(85*(1+burst),0),Color(color.lightened(0.7),opacity*0.75),2.5,true)
			energy.draw_line(center-Vector2(0,40*(1+burst)),center+Vector2(0,40*(1+burst)),Color(color,opacity*0.4),1.3,true)

func title_texture(cue: Dictionary) -> Texture2D:
	return cue.move.presentation.title_texture if cue.move.presentation != null else null

func title_bounds(cue: Dictionary, both: bool = false) -> Rect2:
	var limit := Vector2(560, 104) if both else Vector2(660, 152)
	var y := 112.0 + int(cue.slot) * 116 if both else 126.0
	var texture := title_texture(cue)
	var native_size := texture.get_size() if texture != null else Vector2(_title_font().get_string_size(cue.move.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FALLBACK_SIZE).x, FALLBACK_HEIGHT)
	var fit := minf(limit.x / maxf(1, native_size.x), limit.y / maxf(1, native_size.y))
	var drawn_size := native_size * minf(1, fit)
	var entry := pow(1.0 - clampf(float(cue.age) / 0.10, 0, 1), 3)
	var slide := entry * (28.0 * int(cue.side))
	return Rect2(Vector2(640 - drawn_size.x * 0.5 + slide, y + (limit.y - drawn_size.y) * 0.5), drawn_size)

func activation_side(slot: int) -> int:
	# Lock the actual screen half at activation, including when both fighters
	# are near the same arena edge. A rushing MAX must not move its own cut-in.
	var fighter = combat.fighters[slot]
	var screen_x: float = camera.point(Vector2(fighter.x, fighter.y)).x if camera != null else 640.0 + (fighter.x - 480.0) * 3.0
	if not is_equal_approx(screen_x, 640.0):
		return -1 if screen_x < 640.0 else 1
	return -fighter.facing

func face_source(texture: Texture2D) -> Rect2:
	return Rect2(FACE_REGION.position * texture.get_size() / 1024.0, FACE_REGION.size * texture.get_size() / 1024.0)

func face_bounds(cue: Dictionary, both: bool = false) -> Rect2:
	var title := title_bounds(cue, both)
	var height := 104.0 if both else 152.0
	var size := Vector2(height * FACE_REGION.size.x / FACE_REGION.size.y, height)
	var x := title.position.x - 24.0 - size.x if int(cue.side) < 0 else title.end.x + 24.0
	return Rect2(Vector2(x, title.get_center().y - height * 0.5), size)

func _title_font() -> Font:
	var display: Font = catalog.get("display_font")
	return display if display != null else catalog.title_font

func _draw_titles() -> void:
	if catalog == null or paused:
		return
	var both := active.size() > 1
	for cue: Dictionary in active:
		var slot: int = cue.slot
		var age: float = cue.age
		var alpha := clampf((TITLE_LIFETIME - age) / 0.22, 0, 1)
		var visual = catalog.characters[combat.fighters[slot].character]
		var cut_in: Texture2D = cut_in_textures.get(cue.move.id, visual.battle_portrait)
		var color: Color = cue.move.presentation.color if cue.move.presentation != null else Style.GOLD
		if cue.max and age < 0.48 and cut_in != null:
			var cut_alpha := clampf((0.48 - age) / 0.16, 0, 1)
			var face := face_bounds(cue, both)
			var lean := face.size.x * 0.14
			var shape := PackedVector2Array([face.position + Vector2(lean, 0), Vector2(face.end.x, face.position.y),
				face.end - Vector2(lean, 0), Vector2(face.position.x, face.end.y)])
			var source := face_source(cut_in)
			var region := Rect2(source.position / cut_in.get_size(), source.size / cut_in.get_size())
			titles.draw_colored_polygon(shape, Color(color.darkened(0.6), 0.92 * cut_alpha))
			# Both source portraits face right; turn the right-side cut-in inward.
			Kit.clipped_texture(titles, cut_in, shape, face, region, int(cue.side) > 0, Color(1, 1, 1, cut_alpha))
			for n in range(5):
				var y := face.position.y + face.size.y * (0.18 + n * 0.17)
				var reach := face.size.x * (0.25 + 0.1 * (n % 3))
				var from := face.position.x if int(cue.side) < 0 else face.end.x
				var direction := 1.0 if int(cue.side) < 0 else -1.0
				titles.draw_line(Vector2(from, y), Vector2(from + direction * reach, y), Color(color.lightened(0.6), 0.35 * cut_alpha), 1.5, true)
			Kit.frame(titles, shape, Kit.GOLD, cut_alpha, 4.0, 1.6)
		var bounds := title_bounds(cue, both)
		var texture := title_texture(cue)
		if texture != null:
			titles.draw_texture_rect(texture, bounds, false, Color(1, 1, 1, alpha))
		else:
			var font_size := maxi(12, int(FALLBACK_SIZE * bounds.size.y / FALLBACK_HEIGHT))
			Kit.text(titles, _title_font(), cue.move.display_name, bounds.position + Vector2(0, bounds.size.y * 0.8), font_size,
				Color(Kit.GOLD_HI, alpha), 7, Color(color.darkened(0.75), 0.95))
