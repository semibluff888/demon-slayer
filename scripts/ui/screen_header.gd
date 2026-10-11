extends Control
## Screen title block: English kicker, brush-calligraphy title, gold rule, and
## on the right an optional mode chip and step trail (角色 → 场景 → 开战).
const Kit = preload("res://scripts/ui/kit.gd")
var title: String = ""
var kicker: String = ""
var chip: String = ""
var steps: PackedStringArray = PackedStringArray()
var step: int = -1
var display_font: Font
var title_font: Font
var numeric_font: Font
var time: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	size = Vector2(1280, 96)

func _process(delta: float) -> void:
	if time < 0.6:
		time += delta
		queue_redraw()

func _draw() -> void:
	var enter := Kit.ease_out(time / 0.32)
	var shift := -22.0 * (1.0 - enter)
	if not kicker.is_empty():
		Kit.diamond(self, Vector2(62 + shift, 30), 3.5, Color(Kit.CRIMSON, enter))
		Kit.tracked(self, numeric_font, kicker, Vector2(74 + shift, 35), 13, Color(Kit.GOLD, enter), 4.0)
	var title_width := Kit.width(display_font, title, 50)
	Kit.text(self, display_font, title, Vector2(56 + shift, 82), 50, Color(Kit.PAPER, enter), 6)
	Kit.rule_out(self, Vector2(56, 93), Vector2(56 + (title_width + 260) * enter, 93), Color(Kit.GOLD, 0.85), 1.5)
	var right := 1224.0
	if not steps.is_empty():
		var x := right
		for i in range(steps.size() - 1, -1, -1):
			var label: String = steps[i]
			var w := Kit.width(title_font, label, 15)
			var done := i < step
			var current := i == step
			var color: Color = Kit.GOLD_HI if current else (Kit.PAPER_DIM if done else Color(Kit.MUTED, 0.6))
			Kit.text(self, title_font, label, Vector2(x - w, 50), 15, Color(color, enter), 3)
			var badge := Vector2(x - w - 16, 45)
			Kit.diamond(self, badge, 9, Color(Kit.CRIMSON if current else Kit.INK_600, enter))
			Kit.diamond(self, badge, 9, Color(Kit.GOLD if current or done else Color(Kit.GOLD, 0.35), enter), false, 1.2)
			Kit.text_aligned(self, numeric_font, str(i + 1), badge + Vector2(0, 4.5), 12, Color(Kit.PAPER, enter), 1)
			x = badge.x - 22
			if i > 0:
				Kit.rule(self, Vector2(x - 26, 45), Vector2(x + 4, 45), Color(Kit.GOLD, 0.6 * enter))
				x -= 34
	if not chip.is_empty():
		var w := Kit.width(title_font, chip, 14) + 28
		var plate := Rect2(right - w, 64, w, 24)
		draw_colored_polygon(Kit.slant(plate, 8), Color(Kit.CRIMSON_DEEP, 0.9 * enter))
		draw_polyline(Kit.closed(Kit.slant(plate, 8)), Color(Kit.GOLD, 0.7 * enter), 1.0, true)
		Kit.text_aligned(self, title_font, chip, Vector2(plate.get_center().x, plate.end.y - 7), 14, Color(Kit.GOLD_HI, enter), 1)
