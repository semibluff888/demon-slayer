extends Control
## Full-screen animated sumi backdrop with drifting embers for menu screens.
## Decorative only: ignores the mouse and never takes focus.
const Kit = preload("res://scripts/ui/kit.gd")
const SHADER = preload("res://scripts/ui/shaders/ink_wash.gdshader")
var time: float = 0.0
var ember_color := Color(1.0, 0.74, 0.42)
var _white: ImageTexture
var _motes: Node2D
var _seeds: Array[Dictionary] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(1280, 720)
	var wash := ShaderMaterial.new()
	wash.shader = SHADER
	material = wash
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	_motes = Node2D.new()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_motes.material = additive
	_motes.draw.connect(_draw_motes)
	add_child(_motes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9127
	for i in range(36):
		_seeds.append({"x": rng.randf_range(0, 1280), "y": rng.randf_range(0, 760), "speed": rng.randf_range(10, 34),
			"phase": rng.randf_range(0, TAU), "size": rng.randf_range(1.0, 2.8)})

func set_tints(left: Color, right: Color, strength: float = 0.55) -> void:
	var wash := material as ShaderMaterial
	wash.set_shader_parameter("tint_left", left)
	wash.set_shader_parameter("tint_right", right)
	wash.set_shader_parameter("tint_strength", strength)

func _process(delta: float) -> void:
	time += delta
	(material as ShaderMaterial).set_shader_parameter("phase", time + 7.0)
	_motes.queue_redraw()

func _draw() -> void:
	draw_texture_rect(_white, Rect2(Vector2.ZERO, size), false)

func _draw_motes() -> void:
	for mote: Dictionary in _seeds:
		var y: float = fposmod(float(mote.y) - time * float(mote.speed), 780.0) - 30.0
		var x: float = float(mote.x) + sin(time * 0.6 + float(mote.phase)) * 18.0
		var flicker := 0.55 + 0.45 * sin(time * 3.1 + float(mote.phase) * 3.0)
		var life := clampf(y / 720.0, 0, 1)
		var color := Color(ember_color, 0.22 * flicker * life)
		_motes.draw_circle(Vector2(x, y), float(mote.size) * 2.6, Color(color, color.a * 0.35), true, -1, true)
		_motes.draw_circle(Vector2(x, y), float(mote.size), color, true, -1, true)
