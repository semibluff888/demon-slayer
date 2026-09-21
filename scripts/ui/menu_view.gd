extends Control
## Native controls over the illustrated stage. Artwork contains no interface text.
const DuelButton = preload("res://scripts/ui/duel_button.gd")
const PAPER := Color("fff0c8")
const GOLD := Color("e6c77f")
const MUTED := Color("b7bfd0")
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
	for child in actions.values():
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
	portrait(catalog.characters.keys()[-1], Rect2(872, 118, 365, 553), false, true)
	portrait(catalog.characters.keys()[0], Rect2(522, 58, 491, 655), true, true)
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
	button("mode_practice", "自由练习", Rect2(61, 576, 372, 45), func(): app.choose_mode("practice"), false, true, 21)
	button("help", "操作指南", Rect2(61, 635, 179, 39), app.show_help, false, false, 17)
	button("sound", "声音  /  " + ("关" if app.sound.muted else "开"), Rect2(258, 635, 175, 39), func(): app.sound.toggle(); app.show_title(), false, false, 17)
	label("一对一对决    ·    六十秒一局    ·    三局两胜", Rect2(61, 675, 533, 22), 13, MUTED)
	label("藤袭之庭", Rect2(1012, 657, 210, 31), 24, PAPER, true, HORIZONTAL_ALIGNMENT_RIGHT)
	label("月夜  /  紫藤庭院", Rect2(1012, 692, 210, 18), 12, GOLD, false, HORIZONTAL_ALIGNMENT_RIGHT)
	reveal()

func setup() -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.025, 0.038, 0.075, 0.61))
	texture(shades.bottom, Rect2(0, 409, 1280, 311))
	label("选择剑士", Rect2(47, 23, 440, 62), 43, PAPER, true)
	label("S E L E C T   Y O U R   F I G H T E R", Rect2(51, 90, 513, 22), 12, GOLD)
	label("自由练习" if app.mode == "practice" else ("玩家对电脑" if app.mode == "cpu" else "本地双人对战"), Rect2(866, 42, 364, 28), 17, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	rule(Vector2(51, 123), 1178, Color(GOLD, 0.34))
	for i in range(2):
		var visual = catalog.characters[app.characters[i]]
		var left := i == 0
		var x := 49.0 if left else 730.0
		portrait(app.characters[i], Rect2(217 if left else 741, 125, 321, 389), left)
		var tx := 54.0 if left else 1068.0
		var align := HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
		label("PLAYER 01" if left else ("DUMMY" if app.mode == "practice" else ("COMPUTER" if app.mode == "cpu" else "PLAYER 02")), Rect2(tx, 145, 165, 22), 12, visual.accent, false, align)
		label(visual.display_name, Rect2(tx - (17 if not left else 0), 184, 182, 45), 32, PAPER, true, align)
		label(visual.element_name, Rect2(tx, 245, 165, 29), 20, visual.accent, false, align)
		label(app.combat.catalog.characters[app.characters[i]].role, Rect2(tx, 280, 165, 25), 16, MUTED, false, align)
		rule(Vector2(tx, 326), 161, Color(visual.accent, 0.48))
		label("236 牵制 / 突进\n623 对空 / 214 回旋", Rect2(tx, 348, 165, 65), 13, MUTED, false, align)
		label("1格超必杀\n3格 MAX 超必杀", Rect2(tx, 421, 165, 66), 20, PAPER, true, align)
		var roster: Array = catalog.characters.keys()
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(x, 516)
		scroll.size = Vector2(502, 70)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 12)
		scroll.add_child(cards)
		for j in range(roster.size()):
			var id: String = roster[j]
			var card_visual = catalog.characters[id]
			var card := button("p%d_%s" % [i + 1, id], card_visual.display_name, Rect2(x + j * 258, 520, 242, 54), func(): app.select_character(i, id), false, false, 18)
			card.reparent(cards)
			card.custom_minimum_size = Vector2(242, 54)
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
		if i == 1 and app.mode != "local":
			option.add_item("练习木桩" if app.mode == "practice" else "电脑对手  ·  普通")
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
	if app.mode == "practice":
		button("practice_options", "练习设置 F3", Rect2(526, 700, 137, 20), app.show_practice_options, false, false, 13).focus_mode = Control.FOCUS_NONE
	button("pause", "暂停  Esc", Rect2(679, 700, 112, 20), func(): app.set_paused(true), false, false, 13).focus_mode = Control.FOCUS_NONE

func pause(reason: String) -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.018, 0.03, 0.065, 0.72))
	panel(Rect2(399, 77, 482, 566))
	label("P A U S E", Rect2(434, 111, 412, 23), 14, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
	label("暂收刀锋", Rect2(424, 149, 432, 67), 45, PAPER, true, HORIZONTAL_ALIGNMENT_CENTER)
	label(reason if not reason.is_empty() else "呼吸片刻，再次拔刀。", Rect2(426, 232, 428, 57), 17, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER)
	var resume := button("resume", "继续练习" if app.mode == "practice" else "继续对战", Rect2(449, 310, 382, 49), func(): app.set_paused(false), true, true)
	resume.disabled = not app._devices_ready()
	button("restart", "重置练习" if app.mode == "practice" else "重新开始比赛", Rect2(449, 376, 382, 43), app.start_match, false, false, 19)
	button("move_list", "招式表 / 操作指南", Rect2(449, 434, 382, 43), app.show_help, false, false, 19)
	if app.mode == "practice":
		button("practice_options", "木桩与气槽设置", Rect2(449, 492, 382, 43), app.show_practice_options, false, false, 19)
	button("setup", "返回选人 / 调整设备", Rect2(449, 559, 382, 43), app.show_setup, false, false, 18)
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

func help(page: String = "basics", character_id: String = "") -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.035, 0.07, 0.9))
	label("剑士心得", Rect2(48, 25, 560, 64), 43, PAPER, true)
	label("A 轻斩 · B 轻体术 · C 重斩 · D 重体术  /  方向随朝向解释", Rect2(52, 104, 1176, 30), 19, MUTED)
	if page == "basics":
		panel(Rect2(50, 164, 553, 461))
		panel(Rect2(627, 164, 604, 461))
		label("壹 / 按键与移动", Rect2(75, 181, 508, 42), 25, Color("82d4de"), true)
		var rows := [["移动 / 跳跃", "WASD", "方向键"], ["A 轻斩", "F", "J"], ["B 轻体术", "G", "K"], ["C 重斩", "V", "N"], ["D 重体术", "B", "M"]]
		label("键盘 P1", Rect2(280, 233, 123, 24), 15, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
		label("键盘 P2", Rect2(439, 233, 123, 24), 15, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
		for i in range(rows.size()):
			var y := 273 + i * 43
			label(rows[i][0], Rect2(77, y, 181, 31), 18)
			keycap(rows[i][1], Rect2(280, y, 123, 32))
			keycap(rows[i][2], Rect2(439, y, 123, 32))
		label("手柄：X / A / Y / B 对应逻辑 A / B / C / D", Rect2(75, 501, 508, 27), 16, MUTED)
		label("朝右：236 = S → D＋F/V；214 = S → A＋G/B。\n先松S；朝左交换A/D。双击前后可短冲刺。", Rect2(75, 547, 508, 56), 16, GOLD)
		label("贰 / 攻防与资源", Rect2(652, 181, 553, 42), 25, GOLD, true)
		var lessons := [
			"后方向站防，后下方向蹲防；跳攻站防、下段蹲防。",
			"近身 6+D 前投 / 4+D 背投，抓取后 7 帧内 D 拆投。",
			"A+B 前滚 / 4+A+B 后滚；可躲打击，但全程可被投。",
			"236 / 214 可省斜方向，0.5秒完成；攻击可晚0.2秒。",
			"轻技 → 重技 → 必杀 → 超杀；空挥不能取消。",
			"236236+A/C 超杀耗 1 格；236236+A+C MAX 耗 3 格。",
			"命中、受击和防御涨气；空挥不涨，连段伤害递减。"]
		for i in range(lessons.size()):
			label(lessons[i], Rect2(654, 244 + i * 48, 549, 39), 17, PAPER)
	else:
		if character_id.is_empty():
			character_id = app.characters[0]
		var definition = app.combat.catalog.characters[character_id]
		var selector := device_option("guide_character", Rect2(865, 41, 365, 43))
		var ids: Array = app.combat.catalog.characters.keys()
		for id in ids:
			selector.add_item(app.combat.catalog.characters[id].display_name)
		selector.select(ids.find(character_id))
		selector.item_selected.connect(func(index: int): _help_page(page, ids[index]))
		panel(Rect2(50, 160, 1180, 471))
		if page == "moves":
			for i in range(definition.move_list.size()):
				var row: Dictionary = definition.move_list[i]
				var y := 174 + i * 62
				label(row.input, Rect2(75, y, 246, 43), 22, definition.accent)
				label(row.name, Rect2(330, y, 860, 29), 22, PAPER, true)
				label(row.description, Rect2(333, y + 28, 855, 24), 15, MUTED)
				rule(Vector2(75, y + 57), 1115, Color(GOLD, 0.18))
			label("示例连段 / j. 为空中，5 为站立，2 为蹲下", Rect2(75, 497, 1115, 26), 17, GOLD)
			for i in range(definition.combos.size()):
				label(definition.combos[i], Rect2(76 + (i % 2) * 571, 538 + int(i / 2) * 39, 554, 30), 18)
		else:
			var keys: Array = definition.normals.keys()
			for i in range(keys.size()):
				var move: Resource = definition.normals[keys[i]]
				var x := 76 + int(i / 6) * 576
				var y := 179 + (i % 6) * 69
				label(keys[i], Rect2(x, y, 67, 32), 24, definition.accent)
				label(move.display_name, Rect2(x + 83, y, 426, 30), 20, PAPER, true)
				var guard := "站防" if move.level == "high" else ("蹲防" if move.level == "low" else "站蹲均可防")
				label("起手 %d 帧 / 伤害 %d / %s%s" % [move.startup, move.damage, guard, " / 扫倒终结" if move.knockdown else ""],
					Rect2(x + 84, y + 32, 427, 24), 15, MUTED)
	button("home", "返回对战" if app.help_return == "battle" else "返回主菜单", Rect2(51, 660, 224, 42), app.close_help, true, true, 18).grab_focus()
	button("guide_basics", "基础攻防", Rect2(296, 660, 180, 42), func(): _help_page("basics"), false, false, 18)
	button("guide_normals", "普通技", Rect2(491, 660, 165, 42), func(): _help_page("normals", character_id), false, false, 18)
	button("guide_moves", "必杀与奥义", Rect2(671, 660, 210, 42), func(): _help_page("moves", character_id), false, false, 18)
	label("F1 判定框 / F2 静音", Rect2(916, 667, 314, 27), 15, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	reveal()

func _help_page(page: String, id: String = "") -> void:
	clear()
	help(page, id)

func training_options() -> void:
	rect(Rect2(0, 0, 1280, 720), Color(0.018, 0.03, 0.065, 0.78))
	panel(Rect2(318, 115, 644, 495))
	label("练习设置", Rect2(350, 145, 580, 62), 38, PAPER, true)
	label("木桩防御", Rect2(355, 247, 156, 42), 21, GOLD)
	var guard := device_option("practice_guard", Rect2(530, 247, 392, 43))
	for item in ["站立不防", "站立防御", "蹲下防御", "首击后防（检验真连）"]:
		guard.add_item(item)
	guard.select(app.practice_controller.guard_mode)
	guard.item_selected.connect(func(index: int): app.practice_controller.guard_mode = index; app.practice_controller.first_hit = false)
	label("呼吸槽", Rect2(355, 323, 156, 42), 21, GOLD)
	var meter := device_option("practice_meter", Rect2(530, 323, 392, 43))
	for item in ["0 格", "1 格", "3 格", "无限气"]:
		meter.add_item(item)
	meter.select(app.practice_controller.meter_mode)
	meter.item_selected.connect(func(index: int): app.practice_controller.meter_mode = index; app.practice_controller.apply_meter(app.combat))
	var details := CheckButton.new()
	details.text = "展开输入指导与搓招提示"
	details.position = Vector2(355, 380)
	details.size = Vector2(567, 42)
	details.button_pressed = app.view.hud.practice_details
	details.toggled.connect(func(value: bool): app.view.hud.practice_details = value)
	details.add_theme_color_override("font_color", PAPER)
	add_child(details)
	actions["practice_details"] = details
	label("连段结束后自动补血；Backspace 重置。", Rect2(355, 431, 567, 30), 16, MUTED)
	button("resume", "继续练习", Rect2(355, 469, 267, 49), func(): app.set_paused(false), true, true, 21).grab_focus()
	button("practice_reset", "重置位置", Rect2(649, 469, 273, 49), func(): app.reset_practice(); app.set_paused(false), false, false, 21)
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
