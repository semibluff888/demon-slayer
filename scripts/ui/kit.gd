extends RefCounted
## 「大正墨金」design language: tokens, easing and stateless canvas primitives.
## Menus, the battle HUD and overlays draw through these helpers so every
## surface shares one palette, one stroke vocabulary and one motion feel.

# Sumi ink surfaces, darkest first.
const INK_900 := Color("06080d")
const INK_800 := Color("0c1019")
const INK_700 := Color("141a27")
const INK_600 := Color("1e2536")
const LINE := Color("2c3448")
# Washi paper text.
const PAPER := Color("f3ead3")
const PAPER_DIM := Color("c9bfa8")
const MUTED := Color("9aa3b2")
# Gold leaf.
const GOLD_HI := Color("ffe9b0")
const GOLD := Color("e0b460")
const GOLD_LO := Color("9a7332")
const GOLD_DEEP := Color("5a4220")
# Lacquer.
const CRIMSON := Color("d02b3f")
const CRIMSON_DEEP := Color("7c1222")
const VERMILION := Color("e8553a")
const GUARD := Color("8fd0ff")
# Player identity, shared by menus, HUD and the in-world foot markers.
const P1 := Color("4fd2f0")
const P2 := Color("ff5d7a")

const NUMERALS := ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾"]
const PATTERNS := {"tanjiro": "ichimatsu", "zenitsu": "uroko", "nezuko": "asanoha", "akaza": "rashin"}
const PAD_COLORS := {"A": Color("5fc46a"), "B": Color("e2504a"), "X": Color("4c8fe8"), "Y": Color("e8bf3c")}
const ARROWS := {1: Vector2(-1, 1), 2: Vector2(0, 1), 3: Vector2(1, 1), 4: Vector2(-1, 0), 6: Vector2(1, 0),
	7: Vector2(-1, -1), 8: Vector2(0, -1), 9: Vector2(1, -1)}

static func player_color(slot: int) -> Color:
	return P1 if slot == 0 else P2

static func numeral(value: int) -> String:
	return NUMERALS[value] if value >= 0 and value < NUMERALS.size() else str(value)

static func crest_glyph(element_name: String) -> String:
	return element_name.substr(0, 1) if not element_name.is_empty() else "◆"

static func pattern_for(character_id: String) -> String:
	return PATTERNS.get(character_id, "seigaiha")

# --- Motion -------------------------------------------------------------------

static func ease_out(t: float) -> float:
	t = clampf(t, 0, 1)
	return 1.0 - pow(1.0 - t, 3)

static func ease_in(t: float) -> float:
	t = clampf(t, 0, 1)
	return t * t * t

static func ease_out_back(t: float, overshoot: float = 1.7) -> float:
	t = clampf(t, 0, 1) - 1.0
	return 1.0 + (overshoot + 1.0) * t * t * t + overshoot * t * t

static func ease_out_expo(t: float) -> float:
	t = clampf(t, 0, 1)
	return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)

## Normalized progress of a staggered element whose clock started at zero.
static func stagger(time: float, index: int, step: float = 0.04, duration: float = 0.22) -> float:
	return clampf((time - index * step) / duration, 0, 1)

static func wave(time: float, speed: float = 1.0) -> float:
	return 0.5 + 0.5 * sin(time * speed)

# --- Text -----------------------------------------------------------------------

static func width(font: Font, value: String, size: int) -> float:
	return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Largest size not above `size` that keeps `value` inside `limit` pixels.
static func fitted(font: Font, value: String, size: int, limit: float) -> int:
	var measured := width(font, value, size)
	return size if measured <= limit else maxi(8, int(size * limit / maxf(1, measured)))

static func text(canvas: CanvasItem, font: Font, value: String, at: Vector2, size: int, color: Color,
		outline: int = 0, outline_color: Color = Color(0.024, 0.031, 0.051, 0.9)) -> void:
	if value.is_empty():
		return
	if outline > 0:
		canvas.draw_string_outline(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline,
			Color(outline_color, outline_color.a * color.a))
	canvas.draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Draws `value` left (0), centered (1) or right (2) of `at.x`; returns the width.
static func text_aligned(canvas: CanvasItem, font: Font, value: String, at: Vector2, size: int, color: Color,
		align: int = 0, outline: int = 0, outline_color: Color = Color(0.024, 0.031, 0.051, 0.9)) -> float:
	var measured := width(font, value, size)
	var x := at.x - (measured * 0.5 if align == 1 else (measured if align == 2 else 0.0))
	text(canvas, font, value, Vector2(x, at.y), size, color, outline, outline_color)
	return measured

static func tracked_width(font: Font, value: String, size: int, tracking: float) -> float:
	var total := 0.0
	for character in value:
		total += width(font, character, size) + tracking
	return maxf(0, total - tracking)

## Letter-spaced caption (English kickers such as "R O U N D"); returns the width.
static func tracked(canvas: CanvasItem, font: Font, value: String, at: Vector2, size: int, color: Color,
		tracking: float, align: int = 0, outline: int = 0) -> float:
	var total := tracked_width(font, value, size, tracking)
	var x := at.x - (total * 0.5 if align == 1 else (total if align == 2 else 0.0))
	for character in value:
		text(canvas, font, character, Vector2(x, at.y), size, color, outline)
		x += width(font, character, size) + tracking
	return total

# --- Geometry -------------------------------------------------------------------

## Parallelogram leaning forward: the top edge is shifted right by `amount`.
static func slant(rect: Rect2, amount: float) -> PackedVector2Array:
	return PackedVector2Array([rect.position + Vector2(amount, 0), Vector2(rect.end.x, rect.position.y),
		rect.end - Vector2(amount, 0), Vector2(rect.position.x, rect.end.y)])

## Rectangle with cut corners; `corners` bits are TL=1, TR=2, BR=4, BL=8.
static func chamfer(rect: Rect2, cut: float, corners: int = 15) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var points := PackedVector2Array()
	if corners & 1: points.append_array([Vector2(p.x, p.y + cut), Vector2(p.x + cut, p.y)])
	else: points.append(p)
	if corners & 2: points.append_array([Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut)])
	else: points.append(Vector2(e.x, p.y))
	if corners & 4: points.append_array([Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y)])
	else: points.append(e)
	if corners & 8: points.append_array([Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut)])
	else: points.append(Vector2(p.x, e.y))
	return points

## Tapered bar pointing right (or left when reversed), as used by gauges.
static func blade(rect: Rect2, reverse: bool = false) -> PackedVector2Array:
	var cut := minf(rect.size.y * 0.5, rect.size.x * 0.5)
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x - cut, rect.position.y),
		Vector2(rect.end.x, rect.get_center().y), Vector2(rect.end.x - cut, rect.end.y), Vector2(rect.position.x, rect.end.y)])
	if reverse:
		for i in range(points.size()):
			points[i].x = rect.position.x + rect.end.x - points[i].x
	return points

static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result

static func mirror_x(points: PackedVector2Array, axis: float = 640.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points.size() - 1, -1, -1):
		result.append(Vector2(axis * 2.0 - points[i].x, points[i].y))
	return result

static func bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points:
		result = result.expand(point)
	return result

## UVs that map `rect` onto `region` (normalized texture space) for polygon clipping.
static func uv_for(points: PackedVector2Array, rect: Rect2, region: Rect2 = Rect2(0, 0, 1, 1), flip_h: bool = false) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for point in points:
		var local := (point - rect.position) / rect.size
		if flip_h:
			local.x = 1.0 - local.x
		uvs.append(region.position + local * region.size)
	return uvs

## Texture drawn inside an arbitrary convex polygon, cropped to `region` (normalized).
static func clipped_texture(canvas: CanvasItem, texture: Texture2D, points: PackedVector2Array, rect: Rect2,
		region: Rect2 = Rect2(0, 0, 1, 1), flip_h: bool = false, modulate: Color = Color.WHITE) -> void:
	if texture == null or points.size() < 3:
		return
	canvas.draw_polygon(points, PackedColorArray([modulate]), uv_for(points, rect, region, flip_h), texture)

## Normalized source region that crops `texture` to the aspect of `target` around a focus point.
static func cover_region(texture: Texture2D, target: Vector2, focus: Vector2 = Vector2(0.5, 0.5), zoom: float = 1.0) -> Rect2:
	var size := texture.get_size()
	var wanted := target.x / maxf(1, target.y)
	var crop := Vector2(size.x, size.x / wanted) if size.x / size.y < wanted else Vector2(size.y * wanted, size.y)
	crop /= maxf(zoom, 0.01)
	var origin := (size * focus - crop * 0.5).clamp(Vector2.ZERO, (size - crop).max(Vector2.ZERO))
	return Rect2(origin / size, crop / size)

# --- Surfaces -------------------------------------------------------------------

static func gradient_fill(canvas: CanvasItem, points: PackedVector2Array, top: Color, bottom: Color) -> void:
	var area := bounds(points)
	var colors := PackedColorArray()
	for point in points:
		colors.append(top.lerp(bottom, (point.y - area.position.y) / maxf(1, area.size.y)))
	canvas.draw_polygon(points, colors)

## Soft two-dimensional wash: `alpha_at(u, v)` (0..1 across `rect`) shapes the
## opacity of `color` on a vertex grid, so the falloff has no hard edges.
static func shade(canvas: CanvasItem, rect: Rect2, color: Color, alpha_at: Callable, columns: int = 12, rows: int = 8) -> void:
	for row in range(rows):
		for column in range(columns):
			var u0 := float(column) / columns
			var u1 := float(column + 1) / columns
			var v0 := float(row) / rows
			var v1 := float(row + 1) / rows
			var points := PackedVector2Array([rect.position + rect.size * Vector2(u0, v0), rect.position + rect.size * Vector2(u1, v0),
				rect.position + rect.size * Vector2(u1, v1), rect.position + rect.size * Vector2(u0, v1)])
			var colors := PackedColorArray([Color(color, color.a * alpha_at.call(u0, v0)), Color(color, color.a * alpha_at.call(u1, v0)),
				Color(color, color.a * alpha_at.call(u1, v1)), Color(color, color.a * alpha_at.call(u0, v1))])
			canvas.draw_polygon(points, colors)

## Double keyline: dark ink outside, gold leaf inside.
static func frame(canvas: CanvasItem, points: PackedVector2Array, gold: Color = GOLD, alpha: float = 1.0,
		ink_width: float = 3.0, gold_width: float = 1.2) -> void:
	var loop := closed(points)
	canvas.draw_polyline(loop, Color(INK_900, 0.85 * alpha), ink_width, true)
	canvas.draw_polyline(loop, Color(gold, gold.a * alpha), gold_width, true)

## Lacquered card: deep ink gradient, faint top sheen and a gold keyline.
static func plate(canvas: CanvasItem, points: PackedVector2Array, alpha: float = 0.92, gold: Color = GOLD) -> void:
	gradient_fill(canvas, points, Color(INK_600, alpha), Color(INK_800, alpha))
	frame(canvas, points, Color(gold, 0.75), 1.0, 2.0, 1.0)

## Hairline fading out at both ends.
static func rule(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, line_width: float = 1.0) -> void:
	canvas.draw_polyline_colors(PackedVector2Array([from, from.lerp(to, 0.5), to]),
		PackedColorArray([Color(color, 0), color, Color(color, 0)]), line_width, true)

## Hairline fading out toward `to` only.
static func rule_out(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, line_width: float = 1.0) -> void:
	canvas.draw_polyline_colors(PackedVector2Array([from, to]), PackedColorArray([color, Color(color, 0)]), line_width, true)

static func brackets(canvas: CanvasItem, rect: Rect2, length: float, color: Color, line_width: float = 1.5) -> void:
	var p := rect.position
	var e := rect.end
	for corner in [[p, Vector2(1, 1)], [Vector2(e.x, p.y), Vector2(-1, 1)], [e, Vector2(-1, -1)], [Vector2(p.x, e.y), Vector2(1, -1)]]:
		var at: Vector2 = corner[0]
		var sign_v: Vector2 = corner[1]
		canvas.draw_polyline(PackedVector2Array([at + Vector2(0, length * sign_v.y), at, at + Vector2(length * sign_v.x, 0)]),
			color, line_width, true)

static func diamond_points(at: Vector2, radius: float, squash: float = 1.0) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0, -radius * squash), at + Vector2(radius, 0), at + Vector2(0, radius * squash), at + Vector2(-radius, 0)])

static func diamond(canvas: CanvasItem, at: Vector2, radius: float, color: Color, filled: bool = true, line_width: float = 1.2) -> void:
	var points := diamond_points(at, radius)
	if filled:
		canvas.draw_colored_polygon(points, color)
	else:
		canvas.draw_polyline(closed(points), color, line_width, true)

## Soft radial bloom approximated by stacked translucent discs.
static func glow(canvas: CanvasItem, at: Vector2, radius: float, color: Color, steps: int = 6) -> void:
	for n in range(steps, 0, -1):
		var amount := float(n) / steps
		canvas.draw_circle(at, radius * amount, Color(color, color.a * (1.0 - amount) * 2.0 / steps), true, -1, true)

## Kanji crest set in a gold-keyed diamond, as on the HUD gauges.
static func crest(canvas: CanvasItem, font: Font, glyph: String, at: Vector2, radius: float, accent: Color, alpha: float = 1.0) -> void:
	var outer := diamond_points(at, radius)
	gradient_fill(canvas, outer, Color(INK_600, 0.96 * alpha), Color(INK_900, 0.96 * alpha))
	canvas.draw_polyline(closed(outer), Color(INK_900, alpha), 4.0, true)
	canvas.draw_polyline(closed(outer), Color(GOLD, alpha), 1.6, true)
	canvas.draw_polyline(closed(diamond_points(at, radius - 5)), Color(accent, 0.55 * alpha), 1.0, true)
	var size := int(radius * 0.95)
	text_aligned(canvas, font, glyph, at + Vector2(0, size * 0.36), size, Color(PAPER, alpha), 1, 4,
		Color(accent.darkened(0.6), 0.9))

## Red hanko seal with a centered glyph.
static func seal(canvas: CanvasItem, rect: Rect2, font: Font, value: String, color: Color = CRIMSON,
		text_color: Color = PAPER, alpha: float = 1.0) -> void:
	var points := chamfer(rect, rect.size.x * 0.12)
	canvas.draw_colored_polygon(points, Color(color, color.a * alpha))
	canvas.draw_polyline(closed(chamfer(rect.grow(-2.5), rect.size.x * 0.1)), Color(text_color, 0.55 * alpha), 1.0, true)
	var size := fitted(font, value, int(rect.size.y * 0.66), rect.size.x - 6)
	text_aligned(canvas, font, value, Vector2(rect.get_center().x, rect.get_center().y + size * 0.36), size,
		Color(text_color, alpha), 1)

static func keycap_width(font: Font, value: String, height: float = 22.0) -> float:
	return maxf(height, width(font, value.substr(0, 12), int(height * 0.56)) + height * 0.6)

## Keyboard key glyph whose left edge sits at `at.x` and is vertically centered on `at.y`.
static func keycap(canvas: CanvasItem, font: Font, value: String, at: Vector2, height: float = 22.0,
		active: bool = false, alpha: float = 1.0) -> float:
	var size := int(height * 0.56)
	var label := value.substr(0, 12)
	var w := keycap_width(font, value, height)
	var rect := Rect2(at.x, at.y - height * 0.5, w, height)
	var face := chamfer(rect, 3.0)
	gradient_fill(canvas, face, Color(INK_600.lightened(0.12) if not active else GOLD, alpha),
		Color(INK_800 if not active else GOLD_LO, alpha))
	canvas.draw_polyline(closed(face), Color(GOLD if active else PAPER_DIM, (0.9 if active else 0.42) * alpha), 1.0, true)
	canvas.draw_line(Vector2(rect.position.x + 3, rect.end.y - 1), Vector2(rect.end.x - 3, rect.end.y - 1), Color(INK_900, alpha), 2.0, true)
	text_aligned(canvas, font, label, Vector2(rect.get_center().x, rect.get_center().y + size * 0.36), size,
		Color(INK_900 if active else PAPER, alpha), 1)
	return w

## Gamepad face button (A/B/X/Y) or a neutral round glyph for other labels.
static func pad_glyph(canvas: CanvasItem, font: Font, value: String, center: Vector2, radius: float = 10.0, alpha: float = 1.0) -> void:
	var tint: Color = PAD_COLORS.get(value, MUTED)
	canvas.draw_circle(center, radius, Color(INK_900, 0.9 * alpha), true, -1, true)
	canvas.draw_circle(center, radius - 1.5, Color(tint.darkened(0.25), alpha), true, -1, true)
	canvas.draw_arc(center, radius - 1.0, 0, TAU, 24, Color(tint.lightened(0.35), 0.8 * alpha), 1.0, true)
	var size := int(radius * 1.15)
	text_aligned(canvas, font, value, center + Vector2(0, size * 0.36), size, Color(PAPER, alpha), 1)

## Numpad-notation direction glyph (5 = neutral dot).
static func arrow(canvas: CanvasItem, center: Vector2, radius: float, direction: int, color: Color, ring: bool = true) -> void:
	if ring:
		canvas.draw_circle(center, radius, Color(INK_800, 0.85 * color.a), true, -1, true)
		canvas.draw_arc(center, radius, 0, TAU, 24, Color(color, 0.45 * color.a), 1.0, true)
	if not ARROWS.has(direction):
		canvas.draw_circle(center, radius * 0.22, color, true, -1, true)
		return
	var dir: Vector2 = ARROWS[direction].normalized()
	var normal := dir.orthogonal()
	var tip := center + dir * radius * 0.68
	var tail := center - dir * radius * 0.55
	canvas.draw_line(tail, tip - dir * radius * 0.2, color, maxf(1.5, radius * 0.2), true)
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip - dir * radius * 0.5 + normal * radius * 0.4,
		tip - dir * radius * 0.5 - normal * radius * 0.4]), color)

## Sword-guard (tsuba) medallion used by the round timer.
static func tsuba(canvas: CanvasItem, center: Vector2, radius: float, rim: Color, alpha: float = 1.0, notches: int = 8) -> void:
	var outline := PackedVector2Array()
	for n in range(notches * 6):
		var angle := TAU * n / (notches * 6) - PI * 0.5
		var phase := fmod(n, 6.0)
		var r := radius * (0.93 if phase == 0.0 else 1.0)
		outline.append(center + Vector2(cos(angle), sin(angle)) * r)
	gradient_fill(canvas, outline, Color(INK_600, 0.96 * alpha), Color(INK_900, 0.98 * alpha))
	canvas.draw_polyline(closed(outline), Color(INK_900, alpha), 4.5, true)
	canvas.draw_polyline(closed(outline), Color(rim, alpha), 1.8, true)
	canvas.draw_arc(center, radius * 0.8, 0, TAU, 48, Color(rim, 0.38 * alpha), 1.0, true)
	for n in range(notches):
		var angle := TAU * n / notches - PI * 0.5 + PI / notches
		var direction := Vector2(cos(angle), sin(angle))
		canvas.draw_line(center + direction * radius * 0.8, center + direction * radius * 0.92, Color(rim, 0.55 * alpha), 1.2, true)

## Haori pattern laid inside `clip` (or `rect`) at very low opacity.
static func pattern(canvas: CanvasItem, rect: Rect2, kind: String, color: Color, cell: float = 12.0,
		clip: PackedVector2Array = PackedVector2Array()) -> void:
	var columns := int(ceil(rect.size.x / cell)) + 1
	var rows := int(ceil(rect.size.y / cell)) + 1
	for row in range(rows):
		for column in range(columns):
			var at := rect.position + Vector2(column * cell + (cell * 0.5 if kind in ["uroko", "seigaiha", "asanoha"] and row % 2 == 1 else 0.0), row * cell)
			var center := at + Vector2.ONE * cell * 0.5
			if not rect.has_point(center) or (clip.size() >= 3 and not Geometry2D.is_point_in_polygon(center, clip)):
				continue
			match kind:
				"ichimatsu":
					if (row + column) % 2 == 0:
						canvas.draw_rect(Rect2(at, Vector2.ONE * cell), color)
				"uroko":
					canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(cell * 0.5, 0), at + Vector2(cell, cell), at + Vector2(0, cell)]), color)
				"asanoha":
					for n in range(6):
						var direction := Vector2.from_angle(n * TAU / 6 + PI / 6)
						canvas.draw_line(center, center + direction * cell * 0.55, color, 1.0, true)
				"rashin":
					for n in range(4):
						var direction := Vector2.from_angle(n * PI / 4)
						canvas.draw_line(center - direction * cell * 0.32, center + direction * cell * 0.32, color, 1.0, true)
				_:
					canvas.draw_arc(center + Vector2(0, cell * 0.5), cell * 0.5, PI, TAU, 10, color, 1.0, true)
					canvas.draw_arc(center + Vector2(0, cell * 0.5), cell * 0.28, PI, TAU, 8, color, 1.0, true)
