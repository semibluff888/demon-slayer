extends Button
## Select-grid cell: a character avatar, the random cell or a 「敬请期待」 placeholder,
## with per-player cursor frames and lock seals.
const Kit = preload("res://scripts/ui/kit.gd")
const CELL := Vector2(100, 100)
const CUT := 12.0
## "character", "random" or "empty".
var kind: String = "character"
var portrait: Texture2D
var cursors: Array[int] = []
var locked: Array[bool] = [false, false]
var accent := Color("ed526b")
var tag_font: Font
var glyph_font: Font
var label_font: Font
var time: float = 0.0

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = CELL
	set_meta("select_cell", true)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_color_override("font_color", Color.TRANSPARENT)

func _process(delta: float) -> void:
	time += delta
	if kind == "random" or not cursors.is_empty():
		queue_redraw()

## Top-left and bottom-right corners cut, like the kit's seals and plates.
func _shape(grow: float = 0.0) -> PackedVector2Array:
	return Kit.chamfer(Rect2(-grow, -grow, size.x + grow * 2, size.y + grow * 2), CUT + grow * 0.4, 5)

func _draw() -> void:
	var shape := _shape()
	var bounds := Rect2(Vector2.ZERO, size)
	var center := size * 0.5
	var hot := is_hovered() or has_focus()
	var under := not cursors.is_empty()
	var label: Font = label_font if label_font != null else get_theme_font("font")
	match kind:
		"character":
			Kit.gradient_fill(self, shape, accent.darkened(0.45), Kit.INK_900)
			if portrait != null:
				Kit.clipped_texture(self, portrait, shape, bounds, Kit.cover_region(portrait, size, Vector2(0.5, 0.4)), false,
					Color.WHITE if hot or under else Color(0.74, 0.76, 0.82))
			Kit.gradient_fill(self, Kit.chamfer(Rect2(0, size.y * 0.64, size.x, size.y * 0.36), CUT, 4),
				Color(Kit.INK_900, 0), Color(Kit.INK_900, 0.5))
		"random":
			Kit.gradient_fill(self, shape, Kit.CRIMSON_DEEP, Kit.INK_900)
			Kit.pattern(self, bounds, "seigaiha", Color(Kit.GOLD, 0.07), 12, shape)
			var spin := time * 0.9
			for i in range(3):
				var from := spin + i * TAU / 3.0
				draw_arc(center - Vector2(0, 8), 31, from, from + 1.4, 18, Color(Kit.GOLD, 0.55), 2.0, true)
			var glyph: Font = glyph_font if glyph_font != null else label
			Kit.text_aligned(self, glyph, "？", center + Vector2(0, 11), 48, Kit.GOLD_HI, 1, 4, Color(Kit.CRIMSON_DEEP, 0.9))
			Kit.text_aligned(self, label, "随机", Vector2(center.x, size.y - 9), 13, Kit.GOLD_HI, 1, 3)
		_:
			Kit.gradient_fill(self, shape, Color(Kit.INK_700, 0.92), Color(Kit.INK_900, 0.95))
			Kit.diamond(self, center - Vector2(0, 6 if under else 0), 6, Color(Kit.GOLD, 0.22 if under else 0.14), false)
			if under:
				Kit.text_aligned(self, label, "敬请期待", Vector2(center.x, center.y + 22), 12, Color(Kit.PAPER_DIM, 0.85), 1)
	var edge := 0.85 if hot else (0.5 if kind != "empty" else 0.22)
	draw_polyline(Kit.closed(shape), Color(Kit.GOLD, edge), 2.0 if hot else 1.0, true)
	if hot:
		draw_polyline(Kit.closed(_shape(-3)), Color(Kit.GOLD_HI, 0.55), 1.0, true)
	var font: Font = tag_font if tag_font != null else get_theme_font("font")
	var pulse := 0.8 + 0.2 * sin(time * 6.0)
	for slot: int in cursors:
		var tint := Kit.player_color(slot)
		var inset := 1.5 + slot * 4.0
		draw_polyline(Kit.closed(_shape(-inset)), Color(tint, pulse if not locked[slot] else 1.0), 3.0, true)
		var chip := Rect2(14, 3, 30, 17) if slot == 0 else Rect2(size.x - 44, size.y - 20, 30, 17)
		draw_colored_polygon(Kit.slant(chip, 4), tint)
		Kit.text_aligned(self, font, "%dP" % [slot + 1], Vector2(chip.get_center().x, chip.end.y - 4), 12, Kit.INK_900, 1)
		if locked[slot]:
			var seal := Rect2(size.x - 28, 4, 22, 22) if slot == 0 else Rect2(6, size.y - 28, 22, 22)
			Kit.diamond(self, seal.get_center(), 11, Kit.INK_900)
			Kit.diamond(self, seal.get_center(), 9.5, tint)
			draw_polyline(PackedVector2Array([seal.get_center() + Vector2(-4.5, 0), seal.get_center() + Vector2(-1, 3.5), seal.get_center() + Vector2(5, -3.5)]), Kit.INK_900, 2.2, true)
