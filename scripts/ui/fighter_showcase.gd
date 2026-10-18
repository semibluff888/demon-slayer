extends Control
## Character-select side panel. Behind: accent ink, haori pattern and the element crest.
## Middle: the looping cut-out showcase clip (SelectVideo), flush with the screen edge and
## mirrored for P2; characters without a clip fall back to portrait.png. In front: the
## legibility wash, epithet / element / role / awakening lines and the 就绪 seal. The random
## cell and 「敬请期待」 placeholders get their own emblems; a random lock spins a short
## avatar roulette first. The name itself stays a Label owned by the menu.
const Kit = preload("res://scripts/ui/kit.gd")
const SelectVideo = preload("res://scripts/ui/select_video.gd")
const VIDEO := Rect2(0, 144, 384, 576)
const ROULETTE := 0.7
var slot: int = 0
var kind: String = "character"
var visual: Resource
var definition: Resource
var ready_state: bool = false
var active: bool = false
var rolled: bool = false
## Avatars cycled by the random emblem and the roulette (roster order).
var avatars: Array[Texture2D] = []
var display_font: Font
var title_font: Font
var body_font: Font
var time: float = 0.0
var change_time: float = 1.0
var ready_time: float = 1.0
var video: Control
var front: Control
## The menu's name Label; hidden while a random lock is still spinning.
var name_label: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(1280, 720)
	video = SelectVideo.new()
	video.position = _video_rect().position
	add_child(video)
	front = Control.new()
	front.name = "ShowcaseFront"
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.size = size
	front.draw.connect(_draw_front)
	add_child(front)

func _ready() -> void:
	video.set_mirror(slot == 1)
	video.position = _video_rect().position

func configure(next_kind: String, next_visual: Resource, next_definition: Resource, is_ready: bool, is_active: bool,
		is_rolled: bool = false) -> void:
	if next_kind != kind or (next_kind == "character" and next_visual != visual):
		change_time = 0.0
	if is_ready and not ready_state:
		ready_time = 0.0
	kind = next_kind
	visual = next_visual
	definition = next_definition
	ready_state = is_ready
	active = is_active
	rolled = is_rolled and is_ready
	_sync_video()
	queue_redraw()
	front.queue_redraw()

func rolling() -> bool:
	return rolled and ready_time < ROULETTE

## Whether the current pick is shown by its clip (rather than the portrait or an emblem).
func shows_clip() -> bool:
	return kind == "character" and not rolling() and SelectVideo.has_clip(visual)

func _sync_video() -> void:
	video.show_character(visual if shows_clip() else null)

func _process(delta: float) -> void:
	time += delta
	change_time += delta
	var was_rolling := rolling()
	ready_time += delta
	if was_rolling and not rolling():
		change_time = 0.0
		_sync_video()
	var enter := Kit.ease_out(change_time / 0.28)
	video.position = _video_rect().position + Vector2((1.0 - enter) * (-40.0 if slot == 0 else 40.0), 0)
	video.modulate = Color.WHITE if active or ready_state else Color(0.86, 0.87, 0.92)
	if name_label != null:
		name_label.modulate.a = 0.0 if rolling() else 1.0
	queue_redraw()
	front.queue_redraw()

func _video_rect() -> Rect2:
	return VIDEO if slot == 0 else Rect2(1280.0 - VIDEO.end.x, VIDEO.position.y, VIDEO.size.x, VIDEO.size.y)

func _mirror(points: PackedVector2Array) -> PackedVector2Array:
	return points if slot == 0 else Kit.mirror_x(points)

func _x(x: float) -> float:
	return x if slot == 0 else 1280.0 - x

## What the panel presents: a random lock keeps the random panel until the roulette lands.
func _shown_kind() -> String:
	return "random" if rolling() else kind

func _accent() -> Color:
	return visual.accent if _shown_kind() == "character" and visual != null else Kit.GOLD

func _draw() -> void:
	var accent := _accent()
	var outer := 0.0 if slot == 0 else 1.0
	# Accent ink rising from the outer screen edge, gone before the grid.
	Kit.shade(self, Rect2(0.0 if slot == 0 else 850.0, 96, 430, 624), Color(accent.darkened(0.35), 0.42),
		func(u: float, v: float) -> float: return pow(1.0 - absf(u - outer), 1.4) * clampf(v * 3.0, 0, 1), 10, 8)
	var panel := _mirror(PackedVector2Array([Vector2(0, 120), Vector2(400, 120), Vector2(362, 720), Vector2(0, 720)]))
	var area := Kit.bounds(panel)
	if _shown_kind() == "character" and visual != null:
		Kit.pattern(self, area, Kit.pattern_for(visual.character_id), Color(accent, 0.06), 26, panel)
		Kit.text_aligned(self, display_font, Kit.crest_glyph(visual.element_name), Vector2(_x(196), 470), 300, Color(accent, 0.1), 1)
	else:
		Kit.pattern(self, area, "seigaiha", Color(Kit.GOLD, 0.04), 26, panel)
	var edge := _mirror(PackedVector2Array([Vector2(400, 120), Vector2(362, 720)]))
	Kit.rule(self, edge[0], edge[1], Color(Kit.GOLD, 0.35), 1.0)
	if kind == "character" and not shows_clip() and not rolling() and visual != null and visual.portrait != null:
		_draw_portrait()

## Fallback for characters without a select clip: the full-body portrait's upper part.
func _draw_portrait() -> void:
	var texture: Texture2D = visual.portrait
	var rect := _video_rect()
	var enter := Kit.ease_out(change_time / 0.28)
	var height: float = texture.get_height() * 0.74
	var width: float = minf(texture.get_width(), height * rect.size.x / rect.size.y)
	var center: float = visual.menu_focus_x * texture.get_width()
	var left := clampf(center - width * 0.5, 0, texture.get_width() - width)
	var region := Rect2(left / texture.get_width(), 0, width / texture.get_width(), height / texture.get_height())
	var shown := Rect2(rect.position + Vector2((1.0 - enter) * (-40.0 if slot == 0 else 40.0), 0), rect.size)
	var fade := Color(1, 1, 1, enter) if active or ready_state else Color(0.86, 0.87, 0.92, enter)
	var corners := PackedVector2Array([shown.position, Vector2(shown.end.x, shown.position.y), shown.end, Vector2(shown.position.x, shown.end.y)])
	Kit.clipped_texture(self, texture, corners, shown, region, (slot == 0) != visual.portrait_faces_right, fade)

func _draw_front() -> void:
	var accent := _accent()
	var outer := 0.0 if slot == 0 else 1.0
	# Legibility wash under the name block: soft on every side, no box edge.
	Kit.shade(front, Rect2(0.0 if slot == 0 else 790.0, 400, 490, 320), Color(Kit.INK_900, 0.94),
		func(u: float, v: float) -> float: return clampf(v * 1.6, 0, 1) * clampf(1.25 - absf(u - outer) * 1.4, 0, 1), 10, 6)
	if _shown_kind() == "random":
		_draw_random_emblem()
	elif kind == "empty":
		_draw_empty_emblem()
	_draw_info(accent)
	if ready_state and not rolling():
		var since := ready_time - (ROULETTE if rolled else 0.0)
		var stamp := Kit.ease_out_back(since / 0.3, 2.2)
		var scale := lerpf(1.8, 1.0, stamp)
		front.draw_set_transform(Vector2(_x(330), 236), -0.22 if slot == 0 else 0.22, Vector2.ONE * scale)
		Kit.seal(front, Rect2(-46, -46, 92, 92), display_font, "就绪", Kit.CRIMSON, Kit.PAPER, clampf(since / 0.12, 0, 1) * 0.94)
		front.draw_set_transform(Vector2.ZERO)

func _circle(center: Vector2, radius: float, steps: int = 40) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(steps):
		points.append(center + Vector2.from_angle(TAU * i / steps) * radius)
	return points

## Ink ring with a gilt 「？」; roster avatars flicker inside. While a random lock resolves
## the flicker slows down like a roulette.
func _draw_random_emblem() -> void:
	var center := Vector2(_x(192), 340)
	var enter := Kit.ease_out(change_time / 0.28)
	front.draw_circle(center, 132, Color(Kit.INK_900, 0.55 * enter), true, -1, true)
	if not avatars.is_empty():
		var step: int
		if rolling():
			var t := ready_time / ROULETTE
			step = int(18.0 * (1.0 - pow(1.0 - t, 2.2)))
		else:
			step = int(time / 0.16)
		var texture: Texture2D = avatars[posmod(step, avatars.size())]
		var face := _circle(center, 112)
		var box := Rect2(center - Vector2.ONE * 112, Vector2.ONE * 224)
		Kit.clipped_texture(front, texture, face, box, Kit.cover_region(texture, box.size, Vector2(0.5, 0.42)), slot == 1,
			Color(1, 1, 1, (0.85 if rolling() else 0.22) * enter))
	var spin := time * (5.0 if rolling() else 0.6)
	for i in range(4):
		var from := spin + i * TAU / 4.0
		front.draw_arc(center, 124, from, from + 1.1, 24, Color(Kit.GOLD, 0.7 * enter), 3.0, true)
	front.draw_arc(center, 136, 0, TAU, 72, Color(Kit.INK_900, 0.9 * enter), 6.0, true)
	if not rolling():
		Kit.text_aligned(front, display_font, "？", center + Vector2(0, 64), 180, Color(Kit.GOLD_HI, enter), 1, 8, Color(Kit.CRIMSON_DEEP, 0.9))

func _draw_empty_emblem() -> void:
	var center := Vector2(_x(192), 330)
	var enter := Kit.ease_out(change_time / 0.28)
	Kit.diamond(front, center, 96, Color(Kit.INK_900, 0.6 * enter))
	Kit.diamond(front, center, 96, Color(Kit.GOLD, 0.45 * enter), false, 1.5)
	Kit.diamond(front, center, 84, Color(Kit.GOLD, 0.2 * enter), false, 1.0)
	Kit.text_aligned(front, display_font, "待", center + Vector2(0, 30), 84, Color(Kit.PAPER_DIM, 0.75 * enter), 1)

func _draw_info(accent: Color) -> void:
	var align := 0 if slot == 0 else 2
	var x := _x(28)
	var epithet := ""
	var glyph := ""
	var element := ""
	var lines: Array = []
	var shown := _shown_kind()
	match shown:
		"random":
			epithet = "命运由天而定"
			glyph = "随"
			element = "随机角色"
			lines = [["定位  确认后随机决定一名角色", Kit.MUTED]]
		"empty":
			epithet = "新的角色即将登场"
			glyph = "待"
			element = "尚未开放"
		_:
			if visual == null:
				return
			epithet = visual.epithet
			element = visual.element_name
			glyph = Kit.crest_glyph(element)
			if definition != null:
				var role: String = definition.get("role") if definition.get("role") != null else ""
				if not role.is_empty():
					lines.append(["定位  " + role, Kit.MUTED])
				var awakening: Resource = definition.get("awakening")
				if awakening != null:
					lines.append(["觉醒  " + str(awakening.display_name), awakening.color.lightened(0.2)])
	Kit.text_aligned(front, body_font, epithet, Vector2(x, 478), 16, Kit.PAPER_DIM, align, 3)
	var seal := Rect2(x if slot == 0 else x - 26, 556, 26, 26)
	Kit.seal(front, seal, display_font, glyph, Kit.CRIMSON if shown == "character" else Kit.CRIMSON_DEEP)
	Kit.text_aligned(front, title_font, element, Vector2(x + (36 if slot == 0 else -36), 576), 16,
		accent.lightened(0.3) if shown == "character" else Kit.GOLD_HI, align, 3)
	for i in range(lines.size()):
		Kit.text_aligned(front, body_font, lines[i][0], Vector2(x, 606 + i * 22), 14, lines[i][1], align, 3)
