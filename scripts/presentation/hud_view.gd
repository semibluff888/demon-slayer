extends Control
## Screen-space information only: health, time, rounds and confirmed combos.
const InputRouter = preload("res://scripts/input_router.gd")
const PAPER := Color("f5ead7")
const GOLD := Color("d3b783")
const MUTED := Color("b6b3c7")
var combat: RefCounted
var catalog: RefCounted
var cpu: bool = true
var training: RefCounted
var input_device: String = "keyboard:0"
var meter_flash: Array[float] = [0.0, 0.0]
var frozen: bool = false
var input_hints: Array[String] = ["WASD / FG · VB", "↑↓←→ / JK · NM"]
var trailing: Array[float] = [1000.0, 1000.0]
var callouts: Array[String] = ["", ""]
var callout_time: Array[float] = [0.0, 0.0]
var time: float = 0.0
var header: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.015, 0.025, 0.055, 0.97), Color(0.025, 0.035, 0.07, 0.85), Color(0.02, 0.03, 0.06, 0)])
	gradient.offsets = PackedFloat32Array([0, 0.6, 1])
	header = GradientTexture2D.new()
	header.gradient = gradient
	header.fill_from = Vector2.ZERO
	header.fill_to = Vector2(0, 1)
	header.width = 32
	header.height = 128

func reset_effects() -> void:
	trailing.assign([1000.0, 1000.0])
	callouts.assign(["", ""])
	callout_time.assign([0.0, 0.0])
	time = 0
	meter_flash.assign([0.0, 0.0])

func consume(events: Array) -> void:
	for event: Dictionary in events:
		if event.type == "swing" and combat.moves[event.move].kind in ["skill", "super", "max"]:
			var slot: int = event.attacker
			callouts[slot] = combat.moves[event.move].display_name
			callout_time[slot] = 1.4
		elif event.type == "meter_empty":
			callouts[event.attacker] = "呼吸槽不足 · 需要 %d 格" % int(event.cost / 100)
			callout_time[event.attacker] = 1.2
		elif event.type == "meter":
			meter_flash[event.attacker] = 0.35
		elif event.type == "throw_tech":
			callouts.assign(["拆投", "拆投"])
			callout_time.assign([0.8, 0.8])

func _process(delta: float) -> void:
	if combat == null or catalog == null or combat.fighters.is_empty():
		return
	if not frozen:
		time += delta
		for i in range(2):
			meter_flash[i] = maxf(0, meter_flash[i] - delta)
			trailing[i] = move_toward(trailing[i], combat.fighters[i].hp, delta * 270)
			callout_time[i] = maxf(0, callout_time[i] - delta)
	queue_redraw()

func _text(value: String, at: Vector2, font_size: int, color: Color = PAPER, title: bool = false) -> void:
	var font: Font = catalog.title_font if title else catalog.body_font
	draw_string(font, at + Vector2(0, 2), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.01, 0.02, 0.04, color.a * 0.8))
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func practice_hints() -> Array[String]:
	return InputRouter.motion_hints(input_device, combat.fighters[0].facing)

func practice_feedback() -> String:
	var down := "S" if input_device == "keyboard:0" else "↓"
	match combat.fighters[0].input.feedback:
		"release_down": return "搓招提示：仍在斜下，松开%s再按横方向＋攻击。" % down
		"motion_timeout": return "搓招提示：方向超时，请在0.5秒内连贯输入。"
		"attack_late": return "搓招提示：攻击偏晚，请在横方向后0.2秒内按攻击。"
		"wrong_button": return "搓招提示：236配轻重斩，214配轻重体术；按右侧键位。"
	return "方向和攻击不必同时按；斜方向可省略。"

func _fitted_text(value: String, at: Vector2, font_size: int, width: float, color: Color) -> void:
	var measured: float = catalog.body_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at, mini(font_size, int(font_size * width / maxf(1, measured))), color)

func _diamond(at: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	var points := PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, 1, true)

func _draw() -> void:
	if combat == null or catalog == null or combat.fighters.size() < 2 or header == null:
		return
	draw_texture_rect(header, Rect2(0, 0, 1280, 160), false)
	for i in range(2):
		var f = combat.fighters[i]
		var visual = catalog.characters[f.character]
		var x := 134.0 if i == 0 else 734.0
		var portrait_x := 36.0 if i == 0 else 1163.0
		var accent: Color = visual.accent
		var avatar_bounds := Rect2(portrait_x, 25, 81, 81)
		draw_rect(avatar_bounds.grow(3), Color("10182a"))
		if visual.avatar != null:
			draw_texture_rect(visual.avatar, avatar_bounds, false)
		draw_rect(avatar_bounds, GOLD.darkened(0.3), false, 1)
		for corner in [Vector2(portrait_x - 3, 22), Vector2(portrait_x + 84, 22), Vector2(portrait_x - 3, 109), Vector2(portrait_x + 84, 109)]:
			_diamond(corner, 3, GOLD)
		_text(visual.display_name, Vector2(x, 43), 22, PAPER, true)
		_text("P1" if i == 0 else ("木桩" if combat.practice else ("CPU" if cpu else "P2")), Vector2(x + 365, 43), 14, accent)
		# Sword-shaped outer rail; actual fill is a precise fraction of model HP.
		var rail := PackedVector2Array([Vector2(x - 6, 57), Vector2(x + 402, 57), Vector2(x + 414, 70), Vector2(x + 402, 83), Vector2(x - 6, 83), Vector2(x - 14, 70)])
		draw_colored_polygon(rail, Color("111829"))
		rail.append(rail[0])
		draw_polyline(rail, GOLD.darkened(0.22), 1.5, true)
		var hp: float = clampf(f.hp / 1000.0, 0, 1)
		var trail: float = clampf(trailing[i] / 1000.0, hp, 1)
		var origin := x if i == 0 else x + 400 * (1 - trail)
		draw_rect(Rect2(origin, 61, 400 * trail, 18), Color("aa4859"))
		origin = x if i == 0 else x + 400 * (1 - hp)
		var fill: Color = accent.darkened(0.27)
		if hp < 0.25:
			fill = fill.lerp(Color("d45368"), 0.3 + sin(time * 5) * 0.09)
		draw_rect(Rect2(origin, 61, 400 * hp, 18), fill)
		draw_rect(Rect2(origin, 61, 400 * hp, 3), accent.lightened(0.4))
		for n in range(2):
			_diamond(Vector2(x + 7 + n * 23, 100), 5, GOLD if combat.wins[i] > n else Color("444658"))
			_diamond(Vector2(x + 7 + n * 23, 100), 7, Color(GOLD, 0.45), false)
		_text(visual.element_name, Vector2(x + 293, 103), 13, MUTED)
		for stock in range(3):
			var meter_x := x + stock * 137
			draw_rect(Rect2(meter_x, 117, 126, 9), Color("172537"))
			var fill_amount := clampf((f.meter - stock * 100) / 100.0, 0, 1)
			draw_rect(Rect2(meter_x, 117, 126 * fill_amount, 9), accent.lightened(meter_flash[i] * 0.7))
			draw_rect(Rect2(meter_x, 117, 126, 9), Color(GOLD, 0.55), false, 1)
		_text("呼吸 %d / 3" % int(f.meter / 100), Vector2(x, 145), 13, GOLD)
		if f.meter >= 300:
			_text("MAX", Vector2(x + 358, 145), 14, accent)
		if f.combo_display > 0 and f.combo > 1:
			var combo_x := 47.0 if i == 0 else 1110.0
			_text("%02d" % f.combo, Vector2(combo_x, 244), 54, accent, true)
			_text("连  击", Vector2(combo_x + 3, 271), 17, PAPER)
			_text("%d 伤害" % f.combo_damage, Vector2(combo_x + 3, 297), 16, GOLD)
		if callout_time[i] > 0:
			var alpha := minf(1, callout_time[i] * 3)
			var at := Vector2(45 if i == 0 else 814, 186)
			draw_rect(Rect2(at - Vector2(13, 24), Vector2(419, 39)), Color(0.03, 0.05, 0.1, alpha * 0.73))
			draw_line(at + Vector2(0, 16), at + Vector2(392, 16), Color(accent, alpha * 0.7), 1)
			var callout_width: float = catalog.title_font.get_string_size(callouts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x
			var callout_size := mini(23, int(23 * 400 / maxf(1, callout_width)))
			_text(callouts[i], at + Vector2(0, 3), callout_size, Color(PAPER, alpha), true)
	# An eight-lobed tsuba motif frames the timer without taking battle space.
	var ornament := PackedVector2Array()
	for n in range(32):
		var a := n * TAU / 32 - PI / 2
		var radius := 51.0 if n % 4 in [0, 3] else 44.0
		ornament.append(Vector2(640, 62) + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(ornament, Color("11192a"))
	ornament.append(ornament[0])
	draw_polyline(ornament, GOLD.darkened(0.15), 1.4, true)
	draw_arc(Vector2(640, 62), 39, 0, TAU, 48, Color(GOLD, 0.55), 1, true)
	var seconds := "∞" if combat.practice else str(ceili(combat.remaining / 60.0))
	var width: float = catalog.title_font.get_string_size(seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 43).x
	_text(seconds, Vector2(640 - width / 2, 78), 43, PAPER, true)
	_text("PRACTICE" if combat.practice else "ROUND %02d" % (combat.wins[0] + combat.wins[1] + 1), Vector2(605, 126), 11, GOLD)
	draw_rect(Rect2(0, 677, 1280, 43), Color(0.02, 0.035, 0.07, 0.70))
	draw_line(Vector2(32, 677), Vector2(1248, 677), Color(GOLD, 0.22), 1)
	_text("P1  " + input_hints[0], Vector2(32, 703), 13, MUTED)
	_text("藤袭之庭  /  月夜", Vector2(558, 703), 14, GOLD, true)
	_text("" if combat.practice else ("CPU" if cpu else "P2  " + input_hints[1]), Vector2(867, 703), 13, MUTED)
	if combat.practice and training != null:
		draw_rect(Rect2(32, 603, 1216, 71), Color(0.02, 0.035, 0.07, 0.90))
		draw_line(Vector2(780, 611), Vector2(780, 666), Color(GOLD, 0.25), 1)
		var names := ["站立不防", "站立防御", "蹲下防御", "首击后防"]
		var stocks := ["0格", "1格", "3格", "无限气"]
		_text("练习 / %s / %s    最近连段 %d HIT · %d 伤害" % [names[training.guard_mode], stocks[training.meter_mode], training.last_combo, training.last_damage],
			Vector2(45, 624), 15, GOLD)
		var entries: Array = combat.fighters[0].input.history
		var input_text := ""
		for entry in entries.slice(maxi(0, entries.size() - 8)):
			input_text += str(entry.direction)
			for n in range(4):
				if int(entry.buttons) & (1 << n):
					input_text += "ABCD"[n]
			input_text += "  "
		_fitted_text(input_text, Vector2(45, 646), 15, 320, PAPER)
		var move_name: String = combat.fighters[0].input.last_action
		_fitted_text(move_name, Vector2(390, 646), 14, 372, MUTED)
		_fitted_text(practice_feedback(), Vector2(45, 667), 14, 720,
			GOLD if not combat.fighters[0].input.feedback.is_empty() else MUTED)
		var hints := practice_hints()
		for n in range(hints.size()):
			_fitted_text(hints[n], Vector2(799, 623 + n * 21), 16 if n < 2 else 13, 435, PAPER if n < 2 else MUTED)
	if combat.phase in ["intro", "round_end"]:
		var bounds := PackedVector2Array([Vector2(359, 260), Vector2(930, 264), Vector2(915, 358), Vector2(345, 354)])
		draw_colored_polygon(bounds, Color(0.025, 0.035, 0.07, 0.87))
		draw_line(Vector2(383, 267), Vector2(893, 267), Color(GOLD, 0.65), 1)
		draw_line(Vector2(370, 351), Vector2(886, 351), Color(GOLD, 0.65), 1)
		var message := ("凝神" if combat.phase_frames > 45 else "拔刀") if combat.phase == "intro" else ("平局 · 再决" if combat.round_winner < 0 else "胜负已分")
		var size_x: float = catalog.title_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
		_text(message, Vector2(640 - size_x / 2, 328), 48, PAPER, true)
