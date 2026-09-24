extends Control
## Shared, deterministic arcade callout, also used by the isolated demo.
var title_font: Font
var body_font: Font
var cue: Dictionary = {}
var center := Vector2(640, 280)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if cue.is_empty() or title_font == null:
		return
	var age := float(cue.get("age", 0))
	var duration := float(cue.get("duration", 60))
	var alpha := clampf((duration - age) / 8.0, 0, 1)
	var pop := 1.0 + 0.22 * pow(1.0 - clampf(age / 7.0, 0, 1), 3)
	var message: String = cue.text
	var font_size := 76 if message.length() < 10 else 60
	if message == "GO!":
		font_size = 104
	var ink := Color(0.035, 0.047, 0.065, alpha * 0.9)
	var paper := Color("f5edda")
	var gold := Color("e1c185")
	paper.a = alpha
	gold.a = alpha
	draw_set_transform(center, 0, Vector2.ONE * pop)
	var width := title_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(-width / 2, font_size * 0.34)
	draw_string_outline(title_font, at + Vector2(0, 3), message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 7, ink)
	draw_string(title_font, at, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, gold if message == "GO!" or message.ends_with("WINS") else paper)
	draw_line(Vector2(-42, 54), Vector2(42, 54), gold * Color(1, 1, 1, 0.7), 1.5, true)
	var subtitle: String = cue.get("subtitle", "")
	if not subtitle.is_empty() and body_font != null:
		var sw := body_font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string_outline(body_font, Vector2(-sw / 2, 89), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 4, ink)
		draw_string(body_font, Vector2(-sw / 2, 89), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, paper)
	draw_set_transform(Vector2.ZERO)
