extends Control
## Character-select showcase clip: a looping stacked-alpha Theora video
## (tools/build_select_videos.py) composited by stacked_alpha.gdshader. The clip's decoded
## first frame stands in as a poster until the new stream has drawn, and the previous
## character's last frame fades out underneath. Fast cursor moves are debounced, so only
## the character the cursor rests on starts a decoder.
const SHADER = preload("res://scripts/ui/shaders/stacked_alpha.gdshader")
const DEBOUNCE := 0.18
const FADE := 0.28
## Headless runs keep the poster only (the decoder works there but slows every UI suite);
## tests that exercise real playback switch this on.
static var headless_playback := false
var player: VideoStreamPlayer
var poster: TextureRect
var outgoing: TextureRect
var visual: Resource
var mirror := false
var pending := -1.0
var fade_in := FADE
var fade_out := FADE

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(384, 576)
	outgoing = _layer(TextureRect.new())
	poster = _layer(TextureRect.new())
	player = _layer(VideoStreamPlayer.new())
	player.name = "ShowcaseVideo"
	player.expand = true
	player.loop = true
	player.volume = 0.0

func _layer(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.size = size
	if node is TextureRect:
		var rect := node as TextureRect
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
	var paint := ShaderMaterial.new()
	paint.shader = SHADER
	node.material = paint
	node.visible = false
	add_child(node)
	return node

func set_mirror(value: bool) -> void:
	mirror = value
	for node: Control in [outgoing, poster, player]:
		var paint := node.material as ShaderMaterial
		paint.set_shader_parameter("mirror", value)
		paint.set_shader_parameter("inner_right", not value)

## Shows `next`'s clip (null hides it). Repeated calls with the same character keep playing.
func show_character(next: Resource) -> void:
	if next == visual:
		return
	_retire()
	visual = next
	poster.visible = false
	player.visible = false
	pending = -1.0
	if has_clip(next):
		_apply_layout(poster, next)
		poster.texture = next.select_poster
		poster.visible = true
		pending = DEBOUNCE
		fade_in = 0.0
	_update_alpha()

static func has_clip(candidate: Resource) -> bool:
	return candidate != null and candidate.get("select_video") != null and candidate.get("select_poster") != null

func is_playing() -> bool:
	return player.visible and player.is_playing()

## Keeps the outgoing character's last drawn frame (or its poster) fading out underneath.
func _retire() -> void:
	var frame: Texture2D = null
	if player.visible and player.is_playing():
		frame = player.get_video_texture()
	elif poster.visible:
		frame = poster.texture
	player.stop()
	player.stream = null
	if frame != null and has_clip(visual):
		_apply_layout(outgoing, visual)
		outgoing.texture = frame
		outgoing.visible = true
		fade_out = 0.0
	else:
		outgoing.visible = false

func _apply_layout(node: Control, source: Resource) -> void:
	var layout: Dictionary = source.select_layout
	var frame: Array = layout.get("frame", [576, 864])
	var height: float = frame[1]
	var gutter: float = layout.get("gutter", 16)
	var total := height * 2.0 + gutter
	var paint := node.material as ShaderMaterial
	paint.set_shader_parameter("colour_end", height / total)
	paint.set_shader_parameter("matte_start", (height + gutter) / total)

func _start() -> void:
	pending = -1.0
	if not is_inside_tree() or not has_clip(visual):
		return
	_apply_layout(player, visual)
	player.stream = visual.select_video
	if DisplayServer.get_name() == "headless" and not headless_playback:
		return
	player.visible = true
	player.play()

func _process(delta: float) -> void:
	if pending >= 0.0:
		pending -= delta
		if pending < 0.0:
			_start()
	fade_in += delta
	fade_out += delta
	# The poster is the clip's first frame; drop it once the decoder has drawn.
	if poster.visible and player.visible and player.stream_position >= 1.0 / 24.0:
		poster.visible = false
	if outgoing.visible and fade_out >= FADE:
		outgoing.visible = false
		outgoing.texture = null
	_update_alpha()

func _update_alpha() -> void:
	var shown := clampf(fade_in / FADE, 0, 1)
	poster.modulate.a = shown
	player.modulate.a = shown
	outgoing.modulate.a = 1.0 - clampf(fade_out / FADE, 0, 1)
