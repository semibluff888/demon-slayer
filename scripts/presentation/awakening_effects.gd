extends Node2D
## Actor-local, pose-aware compositing. This clock freezes with the fighter.
const FLOW = preload("res://scripts/presentation/awakening_flow.gdshader")
var actor: Node2D
var phase: float = 0.0
var selected: String = ""
var textures: Array[Texture2D] = []
var flow: ShaderMaterial

func _ready() -> void:
	show_behind_parent = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	flow = ShaderMaterial.new()
	flow.shader = FLOW
	material = flow

func reset() -> void:
	phase = 0
	queue_redraw()

func sync(delta: float, frozen: bool) -> void:
	if actor == null or actor.fighter == null:
		return
	var cid: String = actor.fighter.character
	visible = actor.form_active() and cid != "akaza"
	if selected != cid:
		selected = cid
		textures.clear()
		phase = 0
		for layer in ["aura","wisp","sweep","burst"]:
			var path := "res://art/characters/%s/awakening/fx-%s.png" % [cid,layer]
			textures.append(load(path) if ResourceLoader.exists(path) else null)
	if not frozen and visible:
		phase += delta
	if flow != null:
		flow.set_shader_parameter("phase",phase)
	queue_redraw()

func _layer(index: int, at: Vector2, size: Vector2, alpha: float, rotation: float = 0.0, mirror: bool = false) -> void:
	if index >= textures.size() or textures[index] == null or alpha <= 0:
		return
	draw_set_transform(at,rotation,Vector2(-1 if mirror else 1,1))
	draw_texture_rect(textures[index],Rect2(-size*0.5,size),false,Color(1,1,1,alpha))
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if not visible or actor == null or actor.texture == null:
		return
	var f = actor.fighter
	var bounds: Rect2 = actor.visual_bounds()
	var height := clampf(bounds.size.y,24,100)
	var center := bounds.get_center()
	var facing: int = actor.pose_facing()
	var fade := 1.0
	if f.awakening_ticks > 0 and f.awakening_ticks <= 120:
		fade = 0.65 + 0.35 * (0.5 + 0.5*sin(f.awakening_ticks*0.23))
	var breath := 0.94 + 0.06*sin(phase*4.2)
	# Ground layers disappear while airborne and follow the current pose height.
	if selected == "zenitsu":
		var flash := 0.38 + 0.22*pow(maxf(0,sin(phase*19.0)),3)
		_layer(0,Vector2(center.x,center.y),Vector2(55,height+12)*breath,flash*fade,0,int(phase*7)%2==1)
		if f.grounded:
			_layer(2,Vector2(0,-2),Vector2(61,16),0.62*fade,0,facing<0)
		if f.state in ["walk","dash"]:
			_layer(1,Vector2(-facing*18,-height*0.38),Vector2(36,24),0.40*fade,0,facing<0)
	elif selected == "nezuko":
		_layer(0,center+Vector2(0,5),Vector2(53,height+8)*breath,0.40*fade,0,facing<0)
		if f.grounded:
			_layer(2,Vector2(0,-2),Vector2(49,13),0.50*fade,0,facing<0)
		var hand := Vector2(facing*12,-height*0.57)
		if f.move != null and f.move.kind in ["light","heavy","skill"] and f.hitbox().has_area():
			hand = f.move.box.get_center()
			hand.x *= facing
		_layer(1,hand,Vector2(13,21)*breath,0.70*fade,0,facing<0)
	elif selected == "tanjiro":
		var cycle := fmod(phase*0.60,1.0)
		var mouth := Vector2(facing*6,bounds.position.y+height*0.21)
		if f.state in ["idle","walk","dash","crouch","block"] and f.throw_role.is_empty():
			_layer(1,mouth+Vector2(facing*(5+cycle*9),-cycle*3),Vector2(14+cycle*9,8+cycle*6),sin(cycle*PI)*0.47*fade,0,facing<0)
		_layer(0,Vector2(-facing*15,center.y+4),Vector2(15,height*0.84)*breath,0.16*fade,0,facing<0)
		if f.grounded:
			_layer(2,Vector2(0,-1),Vector2(49,12),0.24*fade,0,facing<0)
	if f.awakening_startup > 0 and f.state == "awakening":
		var duration := 6.0 if f.awakening_quick else 18.0
		var p: float = 1.0 - f.awakening_startup/duration
		var size := lerpf(38,92,p)
		_layer(3,center,Vector2(size,size*0.85),sin((0.12+p*0.88)*PI)*0.82*fade,0,facing<0)
