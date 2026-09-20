extends Control
## Native controls over the illustrated stage. Artwork contains no interface text.
const DuelButton = preload("res://scripts/ui/duel_button.gd")
const PAPER := Color("f5ead7")
const GOLD := Color("d1b17b")
const MUTED := Color("b5b2c5")
const RED := Color("9f3549")
var app: Node2D
var catalog: RefCounted
var actions: Dictionary = {}
var transition: Tween
var decorative: Array[Dictionary] = []
var motion_time: float = 0.0
var shades: Dictionary = {}
var result_spark_time: float = 0.0
var result_sparks: Node2D

func _ready() -> void:
	name = "Interface"
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font = catalog.body_font
	ui_theme.default_font_size = 18
	theme = ui_theme
	for side in ["left", "right", "bottom"]:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(0.022, 0.035, 0.075, 0.98), Color(0.028, 0.045, 0.09, 0.83), Color(0.025, 0.04, 0.07, 0)])
		gradient.offsets = PackedFloat32Array([0, 0.47, 1])
		var shade := GradientTexture2D.new()
		shade.gradient = gradient
		shade.width = 256
		shade.height = 128
		shade.fill_from = Vector2(1, 0) if side == "right" else (Vector2(0, 1) if side == "bottom" else Vector2.ZERO)
		shade.fill_to = Vector2.ZERO if side in ["right", "bottom"] else Vector2(1, 0)
		shades[side] = shade

func _process(delta: float) -> void:
	if app.paused:
		return
	motion_time += delta
	if is_instance_valid(result_sparks) and result_spark_time < 1.1:
		result_spark_time += delta
		result_sparks.queue_redraw()
	for entry: Dictionary in decorative:
		if is_instance_valid(entry.node):
			entry.node.position = entry.origin + Vector2(sin(motion_time * 0.38 + entry.phase) * 2, cos(motion_time * 0.32 + entry.phase) * 1.8)

func clear() -> void:
	if transition != null:
		transition.kill()
	modulate = Color.WHITE
	decorative.clear()
	result_sparks = null
	result_spark_time = 0
	for child in get_children():
		remove_child(child)
		child.queue_free()
	actions.clear()
	app.setup_options.clear()
	app.device_notice = null
	app.start_button = null

func reveal() -> void:
	modulate.a = 0.25
	transition = create_tween()
	transition.tween_property(self, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var focusable: Array[Control] = []
	for child in get_children():
		if child is BaseButton and child.focus_mode != Control.FOCUS_NONE and not child.disabled:
			focusable.append(child)
	for i in range(focusable.size()):
		var previous := focusable[(i - 1 + focusable.size()) % focusable.size()]
		var next := focusable[(i + 1) % focusable.size()]
		focusable[i].focus_neighbor_top = focusable[i].get_path_to(previous)
		focusable[i].focus_neighbor_bottom = focusable[i].get_path_to(next)
		focusable[i].focus_previous = focusable[i].get_path_to(previous)
		focusable[i].focus_next = focusable[i].get_path_to(next)

func title() -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.025, 0.035, 0.075, 0.08))
	portrait("zenitsu", Rect2(872, 118, 365, 553), false, true)
	portrait("tanjiro", Rect2(522, 58, 491, 655), true, true)
	texture(shades.left, Rect2(0, 0, 800, 720))
	texture(shades.bottom, Rect2(0, 604, 1280, 116))
	rect(Rect2(56, 50, 35, 35), RED)
	label("滅", Rect2(56, 50, 35, 35), 24, PAPER, true, HORIZONTAL_ALIGNMENT_CENTER)
	label("鬼灭之刃  /  同人格斗", Rect2(109, 55, 415, 25), 17, GOLD)
	label("月下对决", Rect2(49, 170, 569, 113), 99, PAPER, true)
	label("M O O N L I T   D U E L", Rect2(61, 288, 493, 27), 18, GOLD)
	rule(Vector2(61, 342), 58, RED)
	label("挥刀，斩破长夜。", Rect2(60, 359, 434, 35), 25, MUTED, true)
	var cpu := button("mode_cpu", "对 战 电 脑", Rect2(61, 434, 372, 59), func(): app.choose_mode("cpu"), true, true)
	cpu.kicker = "01"
	cpu.grab_focus()
	var local := button("mode_local", "本 地 双 人", Rect2(61, 506, 372, 59), func(): app.choose_mode("local"), false, true)
	local.kicker = "02"
	button("help", "操作指南", Rect2(61, 595, 179, 39), app.show_help, false, false, 17)
	button("sound", "声音  /  " + ("关" if app.sound.muted else "开"), Rect2(258, 595, 175, 39), func(): app.sound.toggle(); app.show_title(), false, false, 17)
	label("一对一对决    ·    六十秒一局    ·    三局两胜", Rect2(61, 675, 533, 22), 13, MUTED)
	label("藤袭之庭", Rect2(1012, 657, 210, 31), 24, PAPER, true, HORIZONTAL_ALIGNMENT_RIGHT)
	label("月夜  /  紫藤庭院", Rect2(1012, 692, 210, 18), 12, GOLD, false, HORIZONTAL_ALIGNMENT_RIGHT)
	reveal()

func setup() -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.025, 0.038, 0.075, 0.61))
	texture(shades.bottom, Rect2(0, 409, 1280, 311))
	label("选择剑士", Rect2(47, 23, 440, 62), 43, PAPER, true)
	label("S E L E C T   Y O U R   F I G H T E R", Rect2(51, 90, 513, 22), 12, GOLD)
	label("玩家对电脑" if app.mode == "cpu" else "本地双人对战", Rect2(866, 42, 364, 28), 17, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	rule(Vector2(51, 123), 1178, Color(GOLD, 0.34))
	for i in range(2):
		var visual = catalog.characters[app.characters[i]]
		var left := i == 0
		var x := 49.0 if left else 730.0
		portrait(app.characters[i], Rect2(217 if left else 741, 125, 321, 389), left)
		var tx := 54.0 if left else 1068.0
		var align := HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
		label("PLAYER 01" if left else ("COMPUTER" if app.mode == "cpu" else "PLAYER 02"), Rect2(tx, 145, 165, 22), 12, visual.accent, false, align)
		label(visual.display_name, Rect2(tx - (17 if not left else 0), 184, 182, 45), 32, PAPER, true, align)
		label(visual.element_name, Rect2(tx, 245, 165, 29), 20, visual.accent, false, align)
		label("均衡 · 中距离" if app.characters[i] == "tanjiro" else "迅速 · 突进", Rect2(tx, 280, 165, 25), 16, MUTED, false, align)
		rule(Vector2(tx, 326), 161, Color(visual.accent, 0.48))
		label("技能\n前＋技能", Rect2(tx, 348, 165, 65), 13, MUTED, false, align)
		label("水面斩\n水车" if app.characters[i] == "tanjiro" else "居合斩\n霹雳一闪", Rect2(tx, 421, 165, 66), 20, PAPER, true, align)
		for j in range(2):
			var id := "tanjiro" if j == 0 else "zenitsu"
			var card_visual = catalog.characters[id]
			var card := button("p%d_%s" % [i + 1, id], card_visual.display_name, Rect2(x + j * 258, 520, 242, 54), func(): app.select_character(i, id), false, false, 18)
			card.accent = card_visual.accent.darkened(0.65)
			card.selected = app.characters[i] == id
			card.portrait_texture = card_visual.avatar
			if left and card.selected:
				card.grab_focus()
	label("VS", Rect2(563, 264, 154, 82), 64, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	label("呼 吸 之 间", Rect2(555, 354, 170, 28), 15, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	panel(Rect2(49, 590, 1182, 55))
	label("操作设备", Rect2(68, 603, 140, 28), 17, GOLD)
	var available: Array = app.router.available_devices()
	for i in range(2):
		label("P%d" % (i + 1), Rect2(218 + i * 488, 606, 51, 24), 15, MUTED)
		var option := device_option("device_p%d" % (i + 1), Rect2(269 + i * 488, 598, 386, 40))
		app.setup_options.append(option)
		if i == 1 and app.mode == "cpu":
			option.add_item("电脑对手  ·  普通")
			option.disabled = true
		else:
			var selected_index := -1
			for index in range(available.size()):
				option.add_item(available[index].label)
				if available[index].id == app.devices[i]:
					selected_index = index
			if selected_index < 0:
				selected_index = mini(i, available.size() - 1)
				app.devices[i] = available[selected_index].id
			option.select(selected_index)
			option.item_selected.connect(func(index: int): app.devices[i] = available[index].id; app._validate_setup())
	button("back", "返回", Rect2(49, 662, 153, 39), app.show_title, false, false, 17)
	app.device_notice = label("", Rect2(227, 656, 591, 52), 14, MUTED)
	app.start_button = button("start", "拔刀 · 进入对战", Rect2(915, 657, 316, 48), app.start_match, true, true, 21)
	app._validate_setup()
	reveal()

func portrait(id: String, bounds: Rect2, flip: bool = false, moving: bool = false) -> void:
	var visual = catalog.characters[id]
	if visual.portrait == null:
		return
	var node := texture(visual.portrait, bounds)
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.flip_h = flip
	if moving:
		decorative.append({"node": node, "origin": bounds.position, "phase": decorative.size() * 1.7})

func battle() -> void:
	button("pause", "暂停  Esc", Rect2(1122, 682, 126, 29), func(): app.set_paused(true), false, false, 13).focus_mode = Control.FOCUS_NONE

func pause(reason: String) -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.018, 0.03, 0.065, 0.72))
	panel(Rect2(399, 116, 482, 488))
	label("P A U S E", Rect2(434, 155, 412, 23), 14, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	label("暂收刀锋", Rect2(424, 199, 432, 67), 45, PAPER, true, HORIZONTAL_ALIGNMENT_CENTER)
	rule(Vector2(603, 290), 74, RED)
	label(reason if not reason.is_empty() else "呼吸片刻，再次拔刀。", Rect2(426, 311, 428, 57), 17, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	var resume := button("resume", "继续对战", Rect2(449, 394, 382, 52), func(): app.set_paused(false), true, true)
	resume.disabled = not app._devices_ready()
	button("restart", "重新开始比赛", Rect2(449, 463, 382, 45), app.start_match, false, false, 19)
	button("setup", "返回选人 / 调整设备", Rect2(449, 524, 382, 43), app.show_setup, false, false, 18)
	if resume.disabled:
		actions.setup.grab_focus()
	else:
		resume.grab_focus()
	reveal()

func result() -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.025, 0.035, 0.075, 0.40))
	var winner: int = app.combat.match_winner
	var visual = catalog.characters[app.characters[winner]]
	portrait(visual.character_id, Rect2(86, 23, 531, 694), true, true)
	texture(shades.right, Rect2(502, 0, 778, 720))
	texture(shades.bottom, Rect2(0, 615, 1280, 105))
	label("胜", Rect2(1060, 96, 157, 207), 154, Color(RED, 0.62), true)
	label("V I C T O R Y", Rect2(683, 131, 423, 27), 18, GOLD)
	rule(Vector2(684, 184), 62, RED)
	label(visual.display_name, Rect2(678, 211, 544, 79), 54, PAPER, true)
	label(visual.epithet, Rect2(685, 306, 498, 34), 23, MUTED, true)
	label("P%d  获胜" % [winner + 1], Rect2(687, 377, 241, 33), 19, visual.accent)
	label("%d  :  %d" % [app.combat.wins[0], app.combat.wins[1]], Rect2(969, 363, 211, 60), 42, GOLD, true, HORIZONTAL_ALIGNMENT_RIGHT)
	button("replay", "再来一场", Rect2(685, 472, 495, 61), app.start_match, true, true).grab_focus()
	button("setup", "返回选人", Rect2(685, 558, 237, 44), app.show_setup, false, false, 18)
	button("home", "返回主菜单", Rect2(943, 558, 237, 44), app.show_title, false, false, 18)
	label("刀锋归鞘，月色如初。", Rect2(685, 662, 495, 26), 17, MUTED, true)
	result_sparks = Node2D.new()
	result_sparks.draw.connect(_draw_result_sparks)
	add_child(result_sparks)
	reveal()

func _draw_result_sparks() -> void:
	var amount := clampf(result_spark_time / 1.1, 0, 1)
	for i in range(23):
		var angle := i * 2.399
		var at := Vector2(389, 370) + Vector2(cos(angle) * (90 + amount * 220), sin(angle) * (160 + amount * 120))
		at.y -= amount * 37
		result_sparks.draw_line(at, at - Vector2(cos(angle), sin(angle)) * (3 + i % 4), Color(GOLD, (1 - amount) * 0.75), 1, true)

func help() -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.035, 0.07, 0.85))
	label("剑士心得", Rect2(48, 28, 536, 73), 48, PAPER, true)
	label("掌握距离，让每一次出刀都有意义。", Rect2(52, 113, 1125, 31), 20, MUTED)
	panel(Rect2(50, 181, 553, 414))
	panel(Rect2(627, 181, 604, 414))
	label("壹  /  移动与按键", Rect2(74, 199, 506, 43), 26, Color("82d4de"), true)
	var rows := [["移动 / 跳跃", "WASD / W", "方向键 / ↑"], ["轻攻击", "F", "J"], ["重攻击", "G", "K"], ["呼吸法", "H", "L"], ["近身投技", "R", "U"]]
	label("键盘  P1", Rect2(274, 257, 132, 25), 14, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	label("键盘  P2", Rect2(435, 257, 132, 25), 14, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(rows.size()):
		var y := 297 + i * 47
		label(rows[i][0], Rect2(77, y, 174, 31), 18, PAPER)
		keycap(rows[i][1], Rect2(274, y, 132, 32))
		keycap(rows[i][2], Rect2(435, y, 132, 32))
	label("手柄  十字键 / 摇杆  ·  X 轻攻  Y 重攻  A 技能  B 投技", Rect2(75, 536, 508, 25), 14, MUTED)
	label("双击前 / 后短冲刺，可接攻击或跳跃；冲刺不能防御。", Rect2(75, 566, 508, 24), 14, GOLD)
	label("贰  /  攻防与呼吸法", Rect2(654, 199, 549, 43), 26, GOLD, true)
	var lessons := [["守", "后退防御，蹲下＋后退防御下段。\n跳跃攻击需站立防御，近身投技破解防御。"], ["连", "轻攻 → 重攻 → 技能\n命中或被防时衔接，空挥不能取消。"], ["技", "技能释放一招，朝前＋技能释放另一招。\n空中可轻攻 / 重攻，背摔需站立近身并交换站位。"]]
	for i in range(lessons.size()):
		var y := 282 + i * 95
		rect(Rect2(655, y + 6, 38, 40), Color(RED, 0.37))
		label(lessons[i][0], Rect2(655, y + 6, 38, 40), 23, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
		label(lessons[i][1], Rect2(714, y, 492, 72), 18, PAPER)
	label("方向按角色朝向解释。选人页可分配键盘或手柄。", Rect2(52, 610, 1176, 27), 16, MUTED)
	button("home", "返回主菜单", Rect2(51, 661, 248, 42), app.show_title, true, true, 18).grab_focus()
	label("Esc / Start  暂停     F1  判定框     M  静音", Rect2(577, 663, 653, 32), 15, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	reveal()

func keycap(value: String, bounds: Rect2) -> void:
	rect(bounds, Color("242d43"))
	rule(bounds.position + Vector2(0, bounds.size.y - 1), bounds.size.x, Color("6d738a"))
	label(value, bounds, 17, PAPER, false, HORIZONTAL_ALIGNMENT_CENTER)

func label(value: String, bounds: Rect2, font_size: int = 18, color: Color = PAPER, serif: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = value
	node.position = bounds.position
	node.add_theme_font_override("font", catalog.title_font if serif else catalog.body_font)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.04, 0.55))
	node.add_theme_constant_override("shadow_offset_y", 2)
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	node.size = bounds.size
	return node

func button(id: String, value: String, bounds: Rect2, callback: Callable, primary: bool = false, arrow: bool = false, font_size: int = 23) -> Button:
	var node := DuelButton.new()
	node.name = id
	node.text = value
	node.position = bounds.position
	node.primary = primary
	node.arrow = arrow
	node.add_theme_font_size_override("font_size", font_size)
	node.pressed.connect(callback)
	add_child(node)
	node.size = bounds.size
	actions[id] = node
	return node

func texture(value: Texture2D, bounds: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = value
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.position = bounds.position
	node.size = bounds.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node

func rect(bounds: Rect2, color: Color) -> void:
	var node := ColorRect.new()
	node.position = bounds.position
	node.size = bounds.size
	node.color = color
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)

func rule(at: Vector2, length: float, color: Color) -> void:
	rect(Rect2(at, Vector2(length, 1)), color)

func panel(bounds: Rect2) -> void:
	rect(bounds, Color(0.03, 0.045, 0.084, 0.91))
	rule(bounds.position, bounds.size.x, Color(GOLD, 0.62))
	rule(bounds.position + Vector2(0, bounds.size.y - 1), bounds.size.x, Color(GOLD, 0.27))
	rule(bounds.position + Vector2(0, 4), 21, GOLD)
	rule(bounds.end - Vector2(21, 5), 21, GOLD)

func device_option(id: String, bounds: Rect2) -> OptionButton:
	var node := OptionButton.new()
	node.name = id
	node.position = bounds.position
	node.clip_text = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182338")
	style.border_color = Color("6e6581")
	style.border_width_bottom = 1
	style.content_margin_left = 14
	style.content_margin_right = 27
	for state in ["normal", "hover", "pressed", "disabled"]:
		node.add_theme_stylebox_override(state, style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus", focus)
	node.get_popup().add_theme_stylebox_override("panel", style)
	node.get_popup().add_theme_font_override("font", catalog.body_font)
	node.get_popup().add_theme_font_size_override("font_size", 18)
	add_child(node)
	node.size = bounds.size
	actions[id] = node
	return node
