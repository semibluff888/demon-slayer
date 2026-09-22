extends Control
## Screen-space HUD; presentation never changes combat resources.
const InputRouter = preload("res://scripts/input_router.gd")
const Style = preload("res://scripts/presentation/battle_style.gd")
const PAPER := Style.PAPER
const GOLD := Style.GOLD
const MUTED := Style.MUTED
const INK := Style.INK
var combat: RefCounted
var catalog: RefCounted
var super_view: Node2D
var cpu: bool = true
var training: RefCounted
var input_device: String = "keyboard:0"
var frozen: bool = false
var practice_details: bool = false
var input_hints: Array[String] = ["WASD / FG · VB", "↑↓←→ / JK · NM"]
var meter_flash: Array[float] = [0.0, 0.0]
var meter_error: Array[float] = [0.0, 0.0]
var meter_spent: Array[int] = [0, 0]
var spent_time: Array[float] = [0.0, 0.0]
var trailing: Array[float] = [1000.0, 1000.0]
var callouts: Array[String] = ["", ""]
var callout_time: Array[float] = [0.0, 0.0]
var combo_pop: Array[float] = [0.0, 0.0]
var last_combo: Array[int] = [0, 0]
var last_stock: Array[int] = [0, 0]
var time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func reset_effects() -> void:
	trailing.assign([1000.0, 1000.0])
	callouts.assign(["", ""])
	callout_time.assign([0.0, 0.0])
	meter_flash.assign([0.0, 0.0])
	meter_error.assign([0.0, 0.0])
	meter_spent.assign([0, 0])
	spent_time.assign([0.0, 0.0])
	combo_pop.assign([0.0, 0.0])
	last_combo.assign([0, 0])
	last_stock.assign([0, 0])
	time = 0

func consume(events: Array) -> void:
	for event: Dictionary in events:
		if event.type == "swing" and combat.moves[event.move].kind == "skill":
			callouts[event.attacker] = combat.moves[event.move].display_name
			callout_time[event.attacker] = 1.2
		elif event.type == "meter_empty":
			meter_error[event.attacker] = 0.6
			callouts[event.attacker] = "呼吸槽不足 · 需要 %d 格" % int(event.cost / 100)
			callout_time[event.attacker] = 1.2
		elif event.type == "meter":
			meter_flash[event.attacker] = 0.35
			if int(event.amount) < 0:
				meter_spent[event.attacker] = -int(event.amount)
				spent_time[event.attacker] = 0.9
				callout_time[event.attacker] = 0
		elif event.type == "hit":
			combo_pop[event.attacker] = 0.20
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
			meter_error[i] = maxf(0, meter_error[i] - delta)
			spent_time[i] = maxf(0, spent_time[i] - delta)
			combo_pop[i] = maxf(0, combo_pop[i] - delta)
			trailing[i] = move_toward(trailing[i], combat.fighters[i].hp, delta * 270)
			callout_time[i] = maxf(0, callout_time[i] - delta)
			var stock := int(combat.fighters[i].meter / 100)
			if stock > last_stock[i]:
				meter_flash[i] = 0.55
			last_stock[i] = stock
			last_combo[i] = combat.fighters[i].combo
	queue_redraw()

func _text(value: String, at: Vector2, font_size: int, color: Color = PAPER, title: bool = false) -> void:
	Style.text(self, catalog.title_font if title else catalog.body_font, value, at, font_size, color, 2)

func _right_text(value: String, right: float, y: float, font_size: int, color: Color = PAPER, title: bool = false) -> void:
	var font: Font = catalog.title_font if title else catalog.body_font
	_text(value, Vector2(right - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, y), font_size, color, title)

func _fitted_text(value: String, at: Vector2, font_size: int, width: float, color: Color) -> void:
	var measured: float = catalog.body_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at, mini(font_size, int(font_size * width / maxf(1, measured))), color)

func _diamond(at: Vector2, radius: float, color: Color, filled: bool = true) -> void:
	Style.diamond(self, at, radius, color, filled)

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

func _portrait(slot: int, visual: Resource) -> void:
	var x := 24.0 if slot == 0 else 1168.0
	draw_set_transform(Vector2(x if slot == 0 else x + 88, 14), 0, Vector2(1 if slot == 0 else -1, 1))
	var frame := PackedVector2Array([Vector2(0, 19), Vector2(11, 8), Vector2(88, 8), Vector2(88, 75), Vector2(77, 86), Vector2(0, 86), Vector2(0, 19)])
	draw_polyline(frame, Color(INK, 0.9), 3, true)
	draw_polyline(frame, Color(GOLD, 0.72), 1.2, true)
	var texture: Texture2D = visual.battle_portrait if visual.battle_portrait != null else visual.avatar
	if texture != null:
		draw_texture_rect(texture, Rect2(0, 0, 88, 88), false)
	draw_polyline(PackedVector2Array([Vector2(0, 35), Vector2(0, 19), Vector2(11, 8), Vector2(28, 8)]), GOLD, 1.5, true)
	draw_line(Vector2(48, 87), Vector2(76, 87), visual.accent, 2, true)
	draw_line(Vector2(78, 85), Vector2(89, 74), visual.accent, 1.5, true)
	draw_set_transform(Vector2.ZERO)

func _health_bar(slot: int, f: RefCounted, visual: Resource) -> void:
	var x := 128.0 if slot == 0 else 704.0
	var width := 448.0
	if slot == 0:
		_text(visual.display_name, Vector2(x, 35), 22, PAPER, true)
		_right_text("P1", x + width, 33, 12, visual.accent)
	else:
		_right_text(visual.display_name, x + width, 35, 22, PAPER, true)
		_text("木桩" if combat.practice else ("CPU" if cpu else "P2"), Vector2(x, 33), 12, visual.accent)
	var rail := Style.blade_points(Rect2(x, 47, width, 14), slot == 1)
	rail.append(rail[0])
	draw_polyline(rail, Color(INK, 0.85), 3, true)
	draw_polyline(rail, Color(PAPER, 0.52), 1, true)
	var hp := clampf(f.hp / 1000.0, 0, 1)
	var trail := clampf(trailing[slot] / 1000.0, hp, 1)
	var origin := x if slot == 0 else x + width * (1 - trail)
	Style.blade(self, Rect2(origin, 47, width * trail, 14), Color("ba6864"), slot == 1)
	origin = x if slot == 0 else x + width * (1 - hp)
	var tint := Color("91c9aa") if hp >= 0.25 else Color("df9c7b").lerp(Color("f5c597"), 0.18 + sin(time * 6) * 0.12)
	Style.blade(self, Rect2(origin, 47, width * hp, 14), tint, slot == 1)
	for n in range(1, 4):
		var tick_x := x + width * n / 4.0
		draw_line(Vector2(tick_x, 58), Vector2(tick_x, 61), Color(INK, 0.28), 1, true)
	for n in range(2):
		var dx := x + 7 + n * 20 if slot == 0 else x + width - 7 - n * 20
		_diamond(Vector2(dx, 78), 5, GOLD if combat.wins[slot] > n else Color(PAPER, 0.55), combat.wins[slot] > n)
	var start := Vector2(x + 44 if slot == 0 else x + width - 44, 78)
	draw_line(start, start + Vector2(34 if slot == 0 else -34, 0), Color(visual.accent, 0.6), 1, true)

func meter_cell(slot: int, index: int) -> Rect2:
	return Rect2((84.0 if slot == 0 else 948.0) + index * 84, 657, 80, 8)

func meter_fill_rect(slot: int, value: int, index: int) -> Rect2:
	var cell := meter_cell(slot, index)
	var fill := clampf((value - (index if slot == 0 else 2 - index) * 100) / 100.0, 0, 1)
	return Rect2(cell.position + Vector2(0 if slot == 0 else cell.size.x * (1 - fill), 0), Vector2(cell.size.x * fill, cell.size.y))

func _meter(slot: int, f: RefCounted, visual: Resource) -> void:
	var left := slot == 0
	var stock := clampi(int(f.meter / 100), 0, 3)
	var flash := meter_flash[slot]
	var tint: Color = Color("f48a8f") if meter_error[slot] > 0 else visual.accent
	var bx := 84.0 if left else 948.0
	if left:
		_text(str(stock), Vector2(30, 673), 40, PAPER)
		_text(visual.element_name, Vector2(bx, 645), 15, PAPER, true)
	else:
		_right_text(str(stock), 1250, 673, 40, PAPER)
		_right_text(visual.element_name, bx + 248, 645, 15, PAPER, true)
	for n in range(3):
		var cell := meter_cell(slot, n)
		draw_line(cell.position, Vector2(cell.end.x, cell.position.y), Color(tint, 0.32), 1, true)
		draw_line(Vector2(cell.position.x, cell.end.y), cell.end, Color(tint, 0.5), 1, true)
		var fill_rect := meter_fill_rect(slot, f.meter, n)
		Style.blade(self, fill_rect, tint.lightened(flash * 0.65), not left)
	var caption := "MAX" if stock == 3 else ""
	if meter_error[slot] > 0:
		caption = "气量不足"
	elif spent_time[slot] > 0:
		caption = "−%d 格" % int(meter_spent[slot] / 100)
	if left:
		_text(caption, Vector2(bx, 686), 13, tint if meter_error[slot] > 0 else GOLD)
	else:
		_right_text(caption, bx + 248, 686, 13, tint if meter_error[slot] > 0 else GOLD)

func _combo(slot: int, f: RefCounted) -> void:
	if frozen or f.combo_display <= 0 or f.combo < 2:
		return
	var pop := 1.0 + sin(clampf(combo_pop[slot] / 0.2, 0, 1) * PI) * 0.08
	var digits := str(f.combo)
	var digit_width: float = catalog.title_font.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	var width := digit_width + 62
	var origin := Vector2(32 if slot == 0 else 1248 - width * pop, 218)
	draw_set_transform(origin, 0, Vector2.ONE * pop)
	_text(digits, Vector2(0, 61), 64, GOLD, true)
	_text("HIT", Vector2(digit_width + 12, 37), 21, PAPER)
	_text("连击", Vector2(digit_width + 12, 58), 14, PAPER)
	if slot == 0:
		_text("%d 伤害" % f.combo_damage, Vector2(2, 87), 14, PAPER)
	else:
		_right_text("%d 伤害" % f.combo_damage, width, 87, 14, PAPER)
	draw_set_transform(Vector2.ZERO)

func has_super_title() -> bool:
	return is_instance_valid(super_view) and not super_view.active.is_empty()

func practice_details_visible() -> bool:
	return practice_details and not has_super_title() and not frozen

func _practice() -> void:
	var names := ["站立不防", "站立防御", "蹲下防御", "首击后防"]
	_text("%s  ·  最近 %d HIT / %d 伤害" % [names[training.guard_mode], training.last_combo, training.last_damage], Vector2(419, 637), 14, GOLD)
	var input_text := ""
	var entries: Array = combat.fighters[0].input.history
	for entry in entries.slice(maxi(0, entries.size() - 8)):
		input_text += str(entry.direction)
		for n in range(4):
			if int(entry.buttons) & (1 << n):
				input_text += "ABCD"[n]
		input_text += "  "
	_fitted_text(input_text, Vector2(419, 659), 15, 440, PAPER)
	_fitted_text(combat.fighters[0].input.last_action, Vector2(419, 683), 14, 440, MUTED)
	if has_super_title() or frozen:
		return
	if practice_details_visible():
		var hints := practice_hints()
		for n in range(hints.size()):
			_text(hints[n], Vector2(292, 140 + n * 23), 16 if n < 2 else 14, PAPER if n < 2 else MUTED)
		_text(practice_feedback(), Vector2(292, 214), 14, GOLD)
	elif not combat.fighters[0].input.feedback.is_empty():
		_text(practice_feedback(), Vector2(310, 597), 15, GOLD)

func _draw() -> void:
	if combat == null or catalog == null or combat.fighters.size() < 2:
		return
	for i in range(2):
		var f = combat.fighters[i]
		var visual = catalog.characters[f.character]
		_portrait(i, visual)
		_health_bar(i, f, visual)
		_meter(i, f, visual)
		_combo(i, f)
		if callout_time[i] > 0 and not has_super_title() and not frozen:
			var alpha := minf(1, callout_time[i] * 3)
			var value: String = callouts[i]
			var measured: float = catalog.body_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			var font_size := mini(20, int(20 * 436 / maxf(1, measured)))
			if i == 0:
				_text(value, Vector2(32, 148), font_size, Color(visual.accent, alpha))
			else:
				_right_text(value, 1248, 148, font_size, Color(visual.accent, alpha))
	var seconds := "∞" if combat.practice else str(ceili(combat.remaining / 60.0))
	var timer_width: float = catalog.title_font.get_string_size(seconds, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
	_text(seconds, Vector2(640 - timer_width / 2, 59), 48, PAPER, true)
	var round_label := "修  炼" if combat.practice else "第 %d 回合" % (combat.wins[0] + combat.wins[1] + 1)
	var label_width: float = catalog.body_font.get_string_size(round_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(round_label, Vector2(640 - label_width / 2, 81), 12, GOLD)
	draw_line(Vector2(606, 74), Vector2(611, 74), Color(GOLD, 0.6), 1, true)
	draw_line(Vector2(669, 74), Vector2(674, 74), Color(GOLD, 0.6), 1, true)
	if combat.practice and training != null:
		_practice()
	else:
		_text("P1  " + input_hints[0], Vector2(27, 710), 11, MUTED)
		_right_text("CPU" if cpu else "P2  " + input_hints[1], 1253, 710, 11, MUTED)
	if combat.phase in ["intro", "round_end"]:
		var message := ("凝神" if combat.phase_frames > 45 else "拔刀") if combat.phase == "intro" else ("平局 · 再决" if combat.round_winner < 0 else "胜负已分")
		var tw: float = catalog.title_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x
		_text(message, Vector2(640 - tw / 2, 338), 60, PAPER, true)
		draw_line(Vector2(600, 360), Vector2(680, 360), Color(GOLD, 0.75), 1, true)
