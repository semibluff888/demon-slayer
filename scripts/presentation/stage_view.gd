extends Node2D
## Five local painted layers. Static surfaces are cached by Sprite2D, not redrawn as geometry.
var visual: Resource
var camera: RefCounted
var time: float = 0.0
var menu_mode: bool = false
var freeze: bool = false
var layers: Array[Sprite2D] = []
var lanterns: Array[Sprite2D] = []
var atmosphere: Node2D
var particles: Array[Dictionary] = []
var glow: GradientTexture2D

func _ready() -> void:
	for i in range(5):
		var layer := Sprite2D.new()
		layer.centered = false
		if visual != null and i < visual.layers.size():
			layer.texture = visual.layers[i]
		if layer.texture != null:
			layer.scale = Vector2(1408, 792) / layer.texture.get_size()
		layer.position = Vector2(-64, -36)
		layer.z_index = 12 if i == 4 else 0
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
	for at in [Vector2(69, 395), Vector2(1202, 395)]:
		var lantern := Sprite2D.new()
		lantern.texture = glow
		lantern.position = at
		lantern.scale = Vector2(1.9, 1.8)
		lantern.modulate = Color(1, 0.64, 0.3, 0.13)
		add_child(lantern)
		lanterns.append(lantern)
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
	var center: float = 320 if menu_mode or camera == null else camera.center_x
	for i in range(layers.size()):
		# Temple and floor share a transform so architectural contact never separates.
		var factor: float = [0.04, 0.12, 0.22, 0.12, 0.28][i]
		var shift := (center - 320) * factor
		var drift := sin(time * 0.075) * (2.5 if i == 2 else 0.7) if menu_mode else 0.0
		layers[i].position = Vector2(-64 - shift + drift, -36)
	for i in range(lanterns.size()):
		lanterns[i].modulate.a = 0.12 + sin(time * 1.4 + i * 1.8) * 0.018
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
	pass # Foreground Sprite2D uses z_index=12 to avoid rebuilding an identical draw list.
