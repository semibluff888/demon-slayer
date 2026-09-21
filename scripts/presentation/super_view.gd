extends Node2D
## Runs from observed combat ticks, including super-freeze ticks. No rule writes.
const Style = preload("res://scripts/presentation/battle_style.gd")
const TITLE_SIZE: int = 36
const TITLE_LIFETIME: float = 1.12
var combat: RefCounted
var catalog: RefCounted
var camera: RefCounted
var paused: bool = false
var active: Array[Dictionary] = []
var seen: Array[int] = [-1, -1]
var dim_amount: float = 0.0
var dimmer: Node2D
var energy: Node2D
var elemental_textures: Dictionary = {}
var spheres: Array[ColorRect] = []

func _ready() -> void:
	for id in ["water-wheel","sun-flame-arc"]:
		var path: String = "res://art/effects/"+str(id)+".png"
		if ResourceLoader.exists(path): elemental_textures[id] = load(path)
	dimmer = Node2D.new()
	dimmer.z_index = -19
	dimmer.draw.connect(_draw_dimmer)
	add_child(dimmer)
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

func consume(events: Array) -> void:
	for event: Dictionary in events:
		if event.type == "round_end":
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
		active.append({"slot":slot,"instance":f.attack_instance,"move":move,"start":combat.ticks,"age":0.0,"duration":move.freeze_frames/60.0,"max":move.presentation.super_tier==2 if move.presentation != null else move.kind=="max"})
	_refresh()

func reset_effects() -> void:
	active.clear()
	seen.assign([-1,-1])
	dim_amount = 0
	for sphere in spheres: sphere.visible = false
	queue_redraw()
	if dimmer != null:
		dimmer.queue_redraw()
	if energy != null:
		energy.queue_redraw()

func _process(_delta: float) -> void:
	if paused:
		return
	if combat == null or combat.phase != "fight":
		if not active.is_empty():
			reset_effects()
		return
	_refresh()

func _refresh() -> void:
	dim_amount = 0
	for sphere in spheres: sphere.visible = false
	var remaining: Array[Dictionary] = []
	for cue: Dictionary in active:
		cue.age = maxf(0, float(combat.ticks - int(cue.start))/60.0)
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
		dim_amount = maxf(dim_amount,fade*(0.80 if cue.max else 0.66))
	active = remaining
	queue_redraw()
	if dimmer != null:
		dimmer.queue_redraw()
	if energy != null:
		energy.queue_redraw()

func _draw_dimmer() -> void:
	if dim_amount>0:
		dimmer.draw_rect(Rect2(0,0,1280,720),Color(0.004,0.007,0.018,dim_amount))

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
		var tex_key := "sun-flame-arc" if shape=="sun_arc" else "water-wheel"
		if shape in ["water_dragon","sun_arc"] and elemental_textures.has(tex_key):
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

func _draw() -> void:
	if catalog == null:
		return
	var both := active.size()>1
	for cue: Dictionary in active:
		var slot: int = cue.slot
		var age: float = cue.age
		var alpha := minf(1,(TITLE_LIFETIME-age)/0.22)
		var color: Color = cue.move.presentation.color if cue.move.presentation != null else Style.GOLD
		var visual = catalog.characters[combat.fighters[slot].character]
		var y := 137.0 + (slot*73 if both else 0)
		if cue.max and age<0.48 and visual.battle_portrait != null:
			var cut_alpha := minf(1,(0.48-age)/0.16)*0.88
			var slide := (1.0-clampf(age/0.10,0,1))*70.0
			var x := 31.0-slide if slot==0 else 948.0+slide
			Style.ink(self,Rect2(x,y-10,300,128),Color(color.darkened(0.8),cut_alpha))
			draw_set_transform(Vector2(x if slot==0 else x+300,y),0,Vector2(1 if slot==0 else -1,1))
			draw_texture_rect_region(visual.battle_portrait,Rect2(0,0,300,110),Rect2(140,130,745,395),Color(1,1,1,cut_alpha))
			draw_set_transform(Vector2.ZERO)
			for n in range(5):
				draw_line(Vector2(x+20,y+16+n*19),Vector2(x+277,y+6+n*19),Color(color,cut_alpha*0.25),1,true)
		var value: String = cue.move.display_name
		var width: float = catalog.title_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,TITLE_SIZE).x
		var x := 640.0-width*0.5
		Style.ink(self,Rect2(x-30,y,width+60,58),Color(0.015,0.022,0.04,alpha*0.89))
		draw_line(Vector2(x-12,y+56),Vector2(x+width+12,y+56),Color(color,alpha*0.90),2,true)
		Style.text(self,catalog.title_font,value,Vector2(x,y+40),TITLE_SIZE,Color(Style.PAPER,alpha),4)
		Style.diamond(self,Vector2(x-17,y+27),4,Color(color,alpha))
		Style.diamond(self,Vector2(x+width+17,y+27),4,Color(color,alpha))
