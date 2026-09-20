extends Node2D
const Arena = preload("res://scripts/arena_rules.gd")
## One continuous painting: moon, reflections, architecture and floor stay registered.
var visual: Resource
var camera: RefCounted
var time: float = 0.0
var menu_mode: bool = false
var freeze: bool = false
var layers: Array[Sprite2D] = []
var atmosphere: Node2D
var particles: Array[Dictionary] = []
var glow: GradientTexture2D

func _ready() -> void:
	for i in range(visual.layers.size()):
		var layer := Sprite2D.new()
		layer.centered = false
		if visual != null and i < visual.layers.size():
			layer.texture = visual.layers[i]
		if layer.texture != null:
			layer.scale = visual.render_size / layer.texture.get_size()
		layer.position = Vector2(640 - visual.render_size.x * 0.5, -36)
		add_child(layer)
		layers.append(layer)
	var light := Gradient.new()
	light.colors = PackedColorArray([Color(1, 1, 1, 0.65), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
	light.offsets = PackedFloat32Array([0, 0.35, 1])
	glow = GradientTexture2D.new()
	glow.gradient = light
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1, 0.5)
	glow.width = 128
	glow.height = 128
	atmosphere = Node2D.new()
	atmosphere.z_index = 13
	atmosphere.draw.connect(_draw_atmosphere)
	add_child(atmosphere)
	var rng := RandomNumberGenerator.new()
	rng.seed = 709
	for i in range(30):
		particles.append({"x": rng.randf_range(0, 1280), "y": rng.randf_range(30, 720), "speed": rng.randf_range(9, 23), "phase": rng.randf_range(0, TAU), "size": rng.randf_range(1.2, 3)})

func _process(delta: float) -> void:
	if freeze:
		return
	time += delta
	sync_camera()
	atmosphere.queue_redraw()

func _draw_atmosphere() -> void:
	for particle: Dictionary in particles:
		var x: float = fposmod(particle.x + time * particle.speed, 1320) - 20
		var y: float = fposmod(particle.y + time * particle.speed * 0.24, 750) - 15
		var angle: float = sin(time * 0.7 + particle.phase)
		atmosphere.draw_set_transform(Vector2(x, y), angle * 2)
		atmosphere.draw_colored_polygon(PackedVector2Array([Vector2(-particle.size, 0), Vector2(0, -particle.size * 0.55), Vector2(particle.size, 0), Vector2(0, particle.size * 0.65)]), Color(0.77, 0.71, 0.96, 0.3 + (angle + 1) * 0.11))
	atmosphere.draw_set_transform(Vector2.ZERO)
	# Three low-opacity soft bands; no expensive full-screen postprocessing.
	for i in range(3):
		var drift := sin(time * 0.06 + i * 2.1) * 112
		atmosphere.draw_texture_rect(glow, Rect2(-140 + i * 502 + drift, 482 + i % 2 * 61, 802, 134), false, Color(0.52, 0.62, 0.85, 0.085))

func draw_foreground(_canvas: Node2D) -> void:
	pass # Foreground is painted into the continuous scene; no cutout overlays.

func sync_camera() -> void:
	if visual == null:
		return
	var center: float = Arena.CENTER if menu_mode or camera == null else camera.center_x
	var shake: Vector2 = Vector2.ZERO if menu_mode or camera == null else camera.shake
	var shift := (center - Arena.CENTER) * Arena.ZOOM
	for i in range(layers.size()):
		layers[i].position = Vector2(640 - visual.render_size.x * 0.5 - shift * visual.parallax_factors[i], -36) + shake
