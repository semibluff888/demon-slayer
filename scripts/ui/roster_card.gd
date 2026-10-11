extends Button
## Slanted roster portrait with per-player cursor frames and lock seals.
const Kit = preload("res://scripts/ui/kit.gd")
var portrait: Texture2D
var cursors: Array[int] = []
var locked: Array[bool] = [false, false]
var accent := Color("ed526b")
var tag_font: Font
const LEAN := 12.0

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_theme_color_override("font_color", Color.TRANSPARENT)

func _shape(grow: float = 0.0) -> PackedVector2Array:
	return Kit.slant(Rect2(-grow, -grow, size.x + grow * 2, size.y + grow * 2), LEAN)

func _draw() -> void:
	var shape := _shape()
	var bounds := Rect2(Vector2.ZERO, size)
	var hot := is_hovered() or has_focus()
	Kit.gradient_fill(self, shape, Kit.INK_600, Kit.INK_900)
	Kit.pattern(self, bounds, "seigaiha", Color(accent, 0.08), 12, shape)
	if portrait != null:
		Kit.clipped_texture(self, portrait, shape, bounds, Kit.cover_region(portrait, size, Vector2(0.5, 0.4)), false,
			Color(1, 1, 1, 1) if hot or not cursors.is_empty() else Color(0.78, 0.8, 0.86, 1))
	Kit.gradient_fill(self, Kit.slant(Rect2(0, size.y * 0.62, size.x, size.y * 0.38), LEAN * 0.38), Color(Kit.INK_900, 0), Color(Kit.INK_900, 0.55))
	draw_polyline(Kit.closed(shape), Color(Kit.GOLD, 0.85 if hot else 0.4), 2.0 if hot else 1.0, true)
	if hot:
		draw_polyline(Kit.closed(_shape(-3)), Color(Kit.GOLD_HI, 0.6), 1.0, true)
	var font: Font = tag_font if tag_font != null else get_theme_font("font")
	for slot: int in cursors:
		var tint := Kit.player_color(slot)
		var inset := 1.5 + slot * 4.0
		draw_polyline(Kit.closed(_shape(-inset)), tint, 3.0, true)
		var chip := Rect2(4, 3, 30, 17) if slot == 0 else Rect2(size.x - 34, size.y - 20, 30, 17)
		draw_colored_polygon(Kit.slant(chip, 4), tint)
		Kit.text_aligned(self, font, "%dP" % [slot + 1], Vector2(chip.get_center().x, chip.end.y - 4), 12, Kit.INK_900, 1)
		if locked[slot]:
			var seal := Rect2(size.x - 28, 4, 22, 22) if slot == 0 else Rect2(8, size.y - 28, 22, 22)
			Kit.diamond(self, seal.get_center(), 11, Kit.INK_900)
			Kit.diamond(self, seal.get_center(), 9.5, tint)
			draw_polyline(PackedVector2Array([seal.get_center() + Vector2(-4.5, 0), seal.get_center() + Vector2(-1, 3.5), seal.get_center() + Vector2(5, -3.5)]), Kit.INK_900, 2.2, true)
