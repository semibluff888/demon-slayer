extends Control
## Large stage preview with a slow push-in, gilt frame, calligraphic name plate
## and the chosen match-up. Cross-fades when the selection changes.
const Kit = preload("res://scripts/ui/kit.gd")
var frame := Rect2(40, 108, 776, 470)
var stage: Resource
var previous: Texture2D
var avatars: Array[Texture2D] = []
var accents: Array[Color] = [Kit.P1, Kit.P2]
var display_font: Font
var title_font: Font
var body_font: Font
var numeric_font: Font
var time: float = 0.0
var change_time: float = 1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(1280, 720)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func set_stage(next: Resource) -> void:
	if next == stage:
		return
	previous = stage.thumbnail if stage != null else null
	stage = next
	change_time = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	time += delta
	change_time += delta
	queue_redraw()

func _draw() -> void:
	var shape := Kit.chamfer(frame, 22, 5)
	draw_colored_polygon(Kit.chamfer(frame.grow(6), 26, 5), Color(Kit.INK_900, 0.9))
	var zoom := 1.04 + 0.03 * sin(time * 0.18)
	var focus := Vector2(0.5 + 0.03 * sin(time * 0.11), 0.48)
	var blend := Kit.ease_out(change_time / 0.35)
	if previous != null and blend < 1.0:
		Kit.clipped_texture(self, previous, shape, frame, Kit.cover_region(previous, frame.size, focus, zoom))
	if stage != null and stage.thumbnail != null:
		Kit.clipped_texture(self, stage.thumbnail, shape, frame, Kit.cover_region(stage.thumbnail, frame.size, focus, zoom), false, Color(1, 1, 1, blend))
	var shade := PackedVector2Array([Vector2(frame.position.x, frame.end.y - 170), Vector2(frame.end.x, frame.end.y - 170), frame.end, Vector2(frame.position.x, frame.end.y)])
	Kit.gradient_fill(self, shade, Color(Kit.INK_900, 0), Color(Kit.INK_900, 0.92))
	Kit.frame(self, shape, Kit.GOLD, 1.0, 4.0, 1.6)
	Kit.brackets(self, frame.grow(10), 18, Color(Kit.GOLD_HI, 0.8), 2.0)
	if stage == null:
		return
	var enter := Kit.ease_out(change_time / 0.3)
	var x := frame.position.x + 32 - (1.0 - enter) * 20
	Kit.tracked(self, numeric_font, "STAGE", Vector2(x + 2, frame.end.y - 112), 12, Color(Kit.GOLD, enter), 4.0)
	Kit.text(self, display_font, stage.display_name, Vector2(x, frame.end.y - 58), 54, Color(Kit.PAPER, enter), 6)
	Kit.text(self, body_font, stage.subtitle, Vector2(x + 2, frame.end.y - 24), 17, Color(Kit.GOLD_HI, enter), 3)
	if avatars.size() == 2:
		var right := frame.end.x - 58
		for slot in [1, 0]:
			var center := Vector2(right - (0 if slot == 1 else 128), frame.end.y - 62)
			var diamond := Kit.diamond_points(center, 40)
			draw_colored_polygon(Kit.diamond_points(center, 44), Color(Kit.INK_900, 0.9))
			if avatars[slot] != null:
				Kit.clipped_texture(self, avatars[slot], diamond, Rect2(center - Vector2(40, 40), Vector2(80, 80)), Kit.cover_region(avatars[slot], Vector2(80, 80), Vector2(0.5, 0.42)), slot == 1)
			draw_polyline(Kit.closed(diamond), Kit.player_color(slot), 2.0, true)
		Kit.text_aligned(self, numeric_font, "VS", Vector2(right - 64, frame.end.y - 52), 30, Kit.GOLD_HI, 1, 5)
