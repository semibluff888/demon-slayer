extends Control
## Character-select hero panel: accent ink, haori pattern and crest watermark
## behind a slanted portrait, plus the epithet, element seal, role and
## awakening lines. The name itself stays a Label owned by the menu.
const Kit = preload("res://scripts/ui/kit.gd")
var slot: int = 0
var visual: Resource
var definition: Resource
var ready_state: bool = false
var active: bool = false
var display_font: Font
var title_font: Font
var body_font: Font
var time: float = 0.0
var change_time: float = 1.0
var ready_time: float = 1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(1280, 720)

func configure(next_visual: Resource, next_definition: Resource, is_ready: bool, is_active: bool) -> void:
	if next_visual != visual:
		change_time = 0.0
	if is_ready and not ready_state:
		ready_time = 0.0
	visual = next_visual
	definition = next_definition
	ready_state = is_ready
	active = is_active
	queue_redraw()

func _process(delta: float) -> void:
	time += delta
	change_time += delta
	ready_time += delta
	queue_redraw()

func _mirror(points: PackedVector2Array) -> PackedVector2Array:
	return points if slot == 0 else Kit.mirror_x(points)

func _x(x: float) -> float:
	return x if slot == 0 else 1280.0 - x

func _draw() -> void:
	if visual == null:
		return
	var accent: Color = visual.accent
	var enter := Kit.ease_out(change_time / 0.28)
	# Accent ink sweep behind the hero.
	var sweep := _mirror(PackedVector2Array([Vector2(0, 110), Vector2(610, 96), Vector2(520, 560), Vector2(0, 600)]))
	var colors := PackedColorArray()
	for point in sweep:
		var outer := 1.0 - absf(point.x - 640.0) / 640.0
		colors.append(Color(accent.darkened(0.35), 0.38 * (1.0 - outer * 0.85)))
	draw_polygon(sweep, colors)
	var frame := Rect2(24, 96, 560, 432)
	var shape := _mirror(Kit.slant(frame, 80))
	var area := Kit.bounds(shape)
	Kit.pattern(self, area, Kit.pattern_for(visual.character_id), Color(accent, 0.07), 26, shape)
	var glyph := Kit.crest_glyph(visual.element_name)
	Kit.text_aligned(self, display_font, glyph, Vector2(_x(300), 420), 330, Color(accent, 0.09), 1)
	if visual.portrait != null:
		var texture: Texture2D = visual.portrait
		var height: float = texture.get_height() * 0.74
		var width: float = minf(texture.get_width(), height * area.size.x / area.size.y)
		var center: float = visual.menu_focus_x * texture.get_width()
		var left := clampf(center - width * 0.5, 0, texture.get_width() - width)
		var region := Rect2(left / texture.get_width(), 0, width / texture.get_width(), height / texture.get_height())
		var faces_right := slot == 0
		var slide := (1.0 - enter) * (-40.0 if slot == 0 else 40.0)
		var moved := PackedVector2Array()
		for point in shape:
			moved.append(point + Vector2(slide, 0))
		var fade := Color(1, 1, 1, enter) if active or ready_state else Color(0.86, 0.87, 0.92, enter)
		Kit.clipped_texture(self, texture, shape, Rect2(area.position + Vector2(slide, 0), area.size), region,
			faces_right != visual.portrait_faces_right, fade)
	# Legibility fade under the name block and a gilt edge along the slant.
	var foot := _mirror(PackedVector2Array([Vector2(0, 380), Vector2(560, 380), Vector2(520, 640), Vector2(0, 640)]))
	Kit.gradient_fill(self, foot, Color(Kit.INK_900, 0), Color(Kit.INK_900, 0.94))
	var edge := _mirror(PackedVector2Array([frame.end - Vector2(0, frame.size.y) + Vector2(80, 0), frame.end - Vector2(80, 0)]))
	draw_line(edge[0], edge[1], Color(Kit.GOLD, 0.75), 2.0, true)
	draw_line(edge[0] + Vector2(6 if slot == 0 else -6, 0), edge[1] + Vector2(6 if slot == 0 else -6, 0), Color(accent, 0.6), 1.0, true)
	_draw_info(accent)
	if ready_state:
		var stamp := Kit.ease_out_back(ready_time / 0.3, 2.2)
		var scale := lerpf(1.8, 1.0, stamp)
		var at := Vector2(_x(470), 470)
		draw_set_transform(at, -0.22 if slot == 0 else 0.22, Vector2.ONE * scale)
		Kit.seal(self, Rect2(-46, -46, 92, 92), display_font, "就绪", Kit.CRIMSON, Kit.PAPER, clampf(ready_time / 0.12, 0, 1) * 0.94)
		draw_set_transform(Vector2.ZERO)

func _draw_info(accent: Color) -> void:
	var align := 0 if slot == 0 else 2
	var x := _x(40)
	Kit.text_aligned(self, body_font, visual.epithet, Vector2(x, 528), 16, Kit.PAPER_DIM, align, 3)
	var element: String = visual.element_name
	var seal := Rect2(x if slot == 0 else x - 26, 544, 26, 26)
	Kit.seal(self, seal, display_font, Kit.crest_glyph(element), Kit.CRIMSON)
	Kit.text_aligned(self, title_font, element, Vector2(x + (36 if slot == 0 else -36), 564), 16, accent.lightened(0.3), align, 3)
	if definition != null:
		var role: String = definition.get("role") if definition.get("role") != null else ""
		if not role.is_empty():
			Kit.text_aligned(self, body_font, "定位  " + role, Vector2(x, 596), 14, Kit.MUTED, align, 3)
		var awakening: Resource = definition.get("awakening")
		if awakening != null:
			Kit.text_aligned(self, body_font, "觉醒  " + str(awakening.display_name), Vector2(x, 620), 14, awakening.color.lightened(0.2), align, 3)
