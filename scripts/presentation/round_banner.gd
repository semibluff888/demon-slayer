extends Control
## Shared, deterministic arcade callout, also used by the isolated demo and the
## cinematic KO freeze. The combat model supplies {text, subtitle, age, duration}
## in ticks; this view maps it to brush calligraphy with an English kicker and
## animates purely from `age`, so it freezes with the model.
const Kit = preload("res://scripts/ui/kit.gd")
const Brush = preload("res://scripts/ui/brush_stroke.gd")
const GradientText = preload("res://scripts/ui/gradient_text.gd")
const LINES = preload("res://scripts/ui/shaders/speed_lines.gdshader")
const RAMPS := {
	"gold": [Color("fff4cf"), Color("e9b95b"), Color("8d6124")],
	"silver": [Color("ffffff"), Color("dbe6f4"), Color("7d93ad")],
	"ko": [Color("ffffff"), Color("ffd27a"), Color("c23a2c")],
	"crimson": [Color("ffe2dc"), Color("ff6a5c"), Color("8a1426")],
}
var title_font: Font
var body_font: Font
## Optional richer faces; the demo only assigns title/body fonts.
var display_font: Font
var numeric_font: Font
var center := Vector2(640, 280)
var cue: Dictionary = {}:
	set(value):
		cue = value
		_sync()
var lines: ColorRect
var band: Node2D
var main: Node2D
var top: Node2D
var _layout: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines = ColorRect.new()
	lines.name = "FocusLines"
	lines.size = Vector2(1280, 720)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint := ShaderMaterial.new()
	paint.shader = LINES
	lines.material = paint
	add_child(lines)
	band = Brush.new(4.4)
	band.name = "Band"
	band.set_param("taper", 0.55)
	band.set_param("roughness", 0.38)
	add_child(band)
	main = GradientText.new()
	main.name = "Main"
	add_child(main)
	top = Node2D.new()
	top.name = "Kicker"
	top.draw.connect(_draw_top)
	add_child(top)
	_sync()

## Maps a combat cue to {main, kicker, sub, style}. Unknown text is shown as-is.
static func compose(text: String, subtitle: String = "") -> Dictionary:
	if text.begins_with("ROUND "):
		return {"main": "第%s回合" % Kit.numeral(int(text.substr(6))), "kicker": text, "style": "round"}
	match text:
		"READY":
			return {"main": "全集中", "kicker": "READY", "style": "ready"}
		"GO!":
			return {"main": "开战", "kicker": "FIGHT", "style": "go"}
		"K.O.":
			return {"main": "K.O.", "kicker": "胜负已分", "style": "ko"}
		"DOUBLE K.O.":
			return {"main": "DOUBLE K.O.", "kicker": "两败俱伤", "style": "ko"}
		"TIME UP":
			return {"main": "时间到", "kicker": "TIME UP", "style": "time"}
		"DRAW":
			return {"main": "平局", "kicker": "DRAW", "style": "draw"}
	if text.ends_with(" WINS"):
		return {"main": "胜", "kicker": text, "sub": subtitle, "style": "win"}
	return {"main": text, "kicker": subtitle, "style": "plain"}

func _font(kind: String) -> Font:
	if kind == "numeric":
		return numeric_font if numeric_font != null else title_font
	return display_font if display_font != null else title_font

func _sync() -> void:
	if main == null:
		return
	var showing := not cue.is_empty() and title_font != null
	for node in [lines, band, main, top]:
		node.visible = showing
	if not showing:
		return
	_layout = compose(str(cue.get("text", "")), str(cue.get("subtitle", "")))
	var style: String = _layout.style
	var age := float(cue.get("age", 0))
	var duration := float(cue.get("duration", 60))
	var alpha := clampf((duration - age) / 8.0, 0, 1)
	var pop := 1.0 + 0.22 * pow(1.0 - clampf(age / float(cue.get("pop_ticks", 7.0)), 0, 1), 3)
	var latin: bool = style == "ko"
	var size: int = {"round": 92, "ready": 100, "go": 132, "ko": 150, "time": 100, "draw": 116, "win": 176}.get(style, 76)
	if _layout.main == "DOUBLE K.O.":
		size = 104
	main.setup(_font("numeric" if latin else "display"), _layout.main, size, 1)
	main.set_ramp(RAMPS.get({"ready": "silver", "ko": "ko", "time": "crimson"}.get(style, "gold"), RAMPS.gold))
	main.outline = 10 if size > 120 else 8
	main.glow_size = 24 if style in ["go", "ko", "win"] else 0
	main.glow_color = Color(Kit.CRIMSON if style == "ko" else Kit.GOLD, 0.22 * alpha)
	main.skew = -0.16 if latin else 0.0
	main.position = center + Vector2(0, size * 0.34)
	main.scale = Vector2.ONE * pop
	main.modulate.a = alpha
	main.set_glint(fmod(age / 40.0, 1.6) - 0.3 if style in ["win", "go", "round"] else -1.0)
	# Ink band sweeps in behind the calligraphy, wider for the headline cues.
	var reach := 560.0 if style in ["go", "ko", "win"] else 470.0
	var height := size * 0.95
	var tint: Color = {"go": Kit.CRIMSON, "ko": Kit.CRIMSON_DEEP, "win": Kit.CRIMSON_DEEP, "time": Kit.CRIMSON_DEEP}.get(style, Kit.INK_900)
	band.configure(Rect2(center.x - reach, center.y - height * 0.5, reach * 2, height), Color(tint, 0.86 * alpha), 22.0, Kit.ease_out(age / 9.0))
	var focus := 0.0
	if style in ["go", "ko"]:
		focus = clampf(1.0 - age / 30.0, 0, 1) * alpha
	var paint := lines.material as ShaderMaterial
	paint.set_shader_parameter("intensity", focus)
	paint.set_shader_parameter("phase", age / 60.0)
	paint.set_shader_parameter("center", center / Vector2(1280, 720))
	paint.set_shader_parameter("tint", Color(1, 0.92, 0.78, 0.55) if style == "go" else Color(1, 0.75, 0.7, 0.6))
	lines.visible = focus > 0.001
	top.queue_redraw()
	queue_redraw()

func _draw_top() -> void:
	if cue.is_empty() or _layout.is_empty():
		return
	var age := float(cue.get("age", 0))
	var duration := float(cue.get("duration", 60))
	var alpha := clampf((duration - age) / 8.0, 0, 1) * Kit.ease_out((age - 4.0) / 10.0)
	var style: String = _layout.style
	var kicker: String = _layout.get("kicker", "")
	var size: int = main.font_size
	var y := center.y + size * 0.34 + 40
	if kicker.is_empty():
		return
	var latin := kicker.unicode_at(0) < 0x2E80
	var kicker_font := _font("numeric" if latin else "display")
	var kicker_size := 24 if latin else 32
	var width := Kit.tracked(top, kicker_font, kicker, Vector2(center.x, y), kicker_size, Color(Kit.PAPER, alpha), 7.0 if latin else 10.0, 1, 4)
	var side := width * 0.5 + 18
	Kit.rule_out(top, Vector2(center.x - side, y - kicker_size * 0.32), Vector2(center.x - side - 120, y - kicker_size * 0.32), Color(Kit.GOLD, alpha), 1.5)
	Kit.rule_out(top, Vector2(center.x + side, y - kicker_size * 0.32), Vector2(center.x + side + 120, y - kicker_size * 0.32), Color(Kit.GOLD, alpha), 1.5)
	Kit.diamond(top, Vector2(center.x - side + 8, y - kicker_size * 0.32), 3, Color(Kit.GOLD, alpha))
	Kit.diamond(top, Vector2(center.x + side - 8, y - kicker_size * 0.32), 3, Color(Kit.GOLD, alpha))
	var sub: String = _layout.get("sub", "")
	if not sub.is_empty():
		Kit.text_aligned(top, _font("display"), sub, Vector2(center.x, y + 44), 34, Color(Kit.GOLD_HI, alpha), 1, 5)
	if style == "ko" and age < 14:
		# A white-hot slash crosses the letters on impact.
		var cut := Kit.ease_out(age / 6.0)
		var fade := 1.0 - clampf((age - 6.0) / 8.0, 0, 1)
		var from := center + Vector2(-300, -70)
		var to := from.lerp(center + Vector2(300, 60), cut)
		top.draw_line(from, to, Color(1, 0.97, 0.9, 0.9 * fade), 7.0 * fade + 1.0, true)
		top.draw_line(from, to, Color(1, 0.55, 0.4, 0.5 * fade), 16.0 * fade + 1.0, true)
