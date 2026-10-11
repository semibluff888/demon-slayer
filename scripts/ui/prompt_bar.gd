extends Control
## Footer key prompts drawn as keycaps and pad glyphs. `text` follows the
## router hint grammar: groups split by four spaces (optionally prefixed with
## "P1 "/"P2 "), items split by " · ", and an item is "KEY 说明". Items without
## a key are drawn as plain text. `note` is a left-aligned description.
const Kit = preload("res://scripts/ui/kit.gd")
var text: String = "":
	set(value):
		text = value
		queue_redraw()
var note: String = "":
	set(value):
		note = value
		queue_redraw()
var align: int = 2
var font: Font
var note_font: Font

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

static func _is_key(value: String) -> bool:
	if value.is_empty() or value.length() > 8:
		return false
	for character in value:
		var code := character.unicode_at(0)
		if code > 0x7F and not character in ["←", "→", "↑", "↓"]:
			return false
	return true

static func pieces(value: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group_text in value.split("    ", false):
		var group := group_text.strip_edges()
		if group.is_empty():
			continue
		if not result.is_empty():
			result.append({"kind": "space", "value": ""})
		var pad := group.contains("十字键")
		if group.begins_with("P1 ") or group.begins_with("P2 "):
			result.append({"kind": "chip", "value": group.substr(0, 2)})
			group = group.substr(3)
		var items := group.split(" · ", false)
		for i in range(items.size()):
			var item := items[i].strip_edges()
			var gap := item.find(" ")
			if gap > 0 and _is_key(item.substr(0, gap)):
				var key := item.substr(0, gap)
				result.append({"kind": "pad" if pad and key in ["A", "B", "X", "Y"] else "key", "value": key})
				result.append({"kind": "text", "value": item.substr(gap + 1)})
			else:
				result.append({"kind": "text", "value": item})
			if i < items.size() - 1:
				result.append({"kind": "gap", "value": ""})
	return result

static func measure(parts: Array[Dictionary], face: Font, height: float) -> float:
	var total := 0.0
	var text_size := int(height * 0.64)
	for part in parts:
		match part.kind:
			"key": total += maxf(height, Kit.width(face, part.value, int(height * 0.56)) + height * 0.6) + 6
			"pad": total += height + 6
			"chip": total += Kit.width(face, part.value, text_size) + 16
			"text": total += Kit.width(face, part.value, text_size)
			"gap": total += 18
			"space": total += 36
	return total

## Draws prompts inside `rect`; align 0/1/2 = left/center/right. Returns width.
static func paint(canvas: CanvasItem, rect: Rect2, value: String, face: Font, color: Color, alignment: int = 2) -> float:
	var parts := pieces(value)
	var height := minf(24.0, rect.size.y - 4)
	var total := measure(parts, face, height)
	var x := rect.position.x + (rect.size.x - total) * (0.5 if alignment == 1 else (1.0 if alignment == 2 else 0.0))
	var mid := rect.get_center().y
	var text_size := int(height * 0.64)
	for part in parts:
		match part.kind:
			"key":
				x += Kit.keycap(canvas, face, part.value, Vector2(x, mid), height, false, color.a) + 6
			"pad":
				Kit.pad_glyph(canvas, face, part.value, Vector2(x + height * 0.5, mid), height * 0.5, color.a)
				x += height + 6
			"chip":
				var w := Kit.width(face, part.value, text_size) + 12
				var chip := Rect2(x, mid - height * 0.42, w, height * 0.84)
				canvas.draw_colored_polygon(Kit.slant(chip, 4), Color(Kit.player_color(0 if part.value == "P1" else 1), color.a))
				Kit.text_aligned(canvas, face, part.value, Vector2(chip.get_center().x, mid + text_size * 0.36), text_size, Color(Kit.INK_900, color.a), 1)
				x += w + 4
			"text":
				Kit.text(canvas, face, part.value, Vector2(x, mid + text_size * 0.36), text_size, color, 3)
				x += Kit.width(face, part.value, text_size)
			"gap":
				Kit.diamond(canvas, Vector2(x + 9, mid), 2, Color(Kit.GOLD, 0.6 * color.a))
				x += 18
			"space":
				x += 36
	return total

func _draw() -> void:
	var face: Font = font if font != null else get_theme_font("font")
	var used := 0.0
	if not text.is_empty():
		used = paint(self, Rect2(Vector2.ZERO, size), text, face, Kit.PAPER_DIM, align)
	if not note.is_empty():
		var small: Font = note_font if note_font != null else face
		var limit := size.x - used - 40
		var note_size := Kit.fitted(small, note, 16, maxf(40, limit))
		Kit.diamond(self, Vector2(6, size.y * 0.5), 4, Kit.CRIMSON)
		Kit.text(self, small, note, Vector2(18, size.y * 0.5 + note_size * 0.36), note_size, Kit.PAPER, 3)
