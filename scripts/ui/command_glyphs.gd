extends RefCounted
## Renders numpad notation such as "236236 + A+C" as arrow and button glyphs.
const Kit = preload("res://scripts/ui/kit.gd")
const BUTTON_TINTS := {"A": Color("5fc0ff"), "B": Color("6fd69a"), "C": Color("ffb44c"), "D": Color("ff6f6f")}

static func tokens(notation: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for character in notation:
		if character in ["1", "2", "3", "4", "6", "7", "8", "9"]:
			result.append({"kind": "dir", "value": int(character)})
		elif character == "5":
			result.append({"kind": "dir", "value": 5})
		elif character in ["A", "B", "C", "D"]:
			result.append({"kind": "button", "value": character})
		elif character == "+":
			result.append({"kind": "plus", "value": "+"})
		elif character == "/":
			result.append({"kind": "or", "value": "/"})
		elif character != " ":
			result.append({"kind": "text", "value": character})
	return result

static func _advance(token: Dictionary, height: float, font: Font) -> float:
	match token.kind:
		"dir", "button": return height + 2
		"plus", "or": return height * 0.6
	return Kit.width(font, token.value, int(height * 0.7)) + 2

static func measure(notation: String, height: float, font: Font) -> float:
	var total := 0.0
	for token in tokens(notation):
		total += _advance(token, height, font)
	return total

## Draws glyphs starting at `at` (left edge, vertical center). Returns the width.
static func paint(canvas: CanvasItem, font: Font, notation: String, at: Vector2, height: float = 24.0, alpha: float = 1.0) -> float:
	var x := at.x
	var radius := height * 0.5
	for token in tokens(notation):
		match token.kind:
			"dir":
				Kit.arrow(canvas, Vector2(x + radius, at.y), radius, int(token.value), Color(Kit.PAPER, alpha))
			"button":
				var tint: Color = BUTTON_TINTS.get(token.value, Kit.MUTED)
				var center := Vector2(x + radius, at.y)
				canvas.draw_circle(center, radius, Color(Kit.INK_900, alpha), true, -1, true)
				canvas.draw_circle(center, radius - 1.5, Color(tint.darkened(0.2), alpha), true, -1, true)
				canvas.draw_arc(center, radius - 1.0, 0, TAU, 24, Color(tint.lightened(0.35), 0.8 * alpha), 1.0, true)
				Kit.text_aligned(canvas, font, token.value, center + Vector2(0, height * 0.22), int(height * 0.6), Color(Kit.PAPER, alpha), 1)
			"plus", "or":
				Kit.text_aligned(canvas, font, token.value, Vector2(x + height * 0.3, at.y + height * 0.22), int(height * 0.62), Color(Kit.GOLD, alpha), 1)
			_:
				Kit.text(canvas, font, token.value, Vector2(x, at.y + height * 0.24), int(height * 0.7), Color(Kit.PAPER_DIM, alpha))
		x += _advance(token, height, font)
	return x - at.x
