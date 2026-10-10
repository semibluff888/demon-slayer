extends Control
## Native controls over illustrated scenery; the title poster includes its own lettering.
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
var settings_panel: RefCounted
const RosterCard = preload("res://scripts/ui/roster_card.gd")
const StageCard = preload("res://scripts/ui/stage_card.gd")
const DuelButton = preload("res://scripts/ui/duel_button.gd")
const BattleStyle = preload("res://scripts/presentation/battle_style.gd")
const PAPER := Color("fff0c8")
const GOLD := Color("e6c77f")
const MUTED := Color("b7bfd0")
const RED := Color("9f3549")
var roster_scroll: ScrollContainer
var roster_cards: Dictionary = {}
var stage_cards: Dictionary = {}
var fighter_portraits: Array[TextureRect] = []
var fighter_names: Array[Label] = []
var fighter_states: Array[Label] = []
var slot_buttons: Array[Button] = []
var app: Node2D
var catalog: RefCounted
var actions: Dictionary = {}
var transition: Tween
var decorative: Array[Dictionary] = []
var motion_time: float = 0.0
var shades: Dictionary = {}
var result_spark_time: float = 0.0
var result_sparks: Node2D
var battle_style: bool = false

func _ready() -> void:
	# Godot's defaults may only bind keyboard accept/cancel; native menus also
	# need explicit all-device gamepad bindings. Fighter input remains sampled
	# by InputRouter and battle footer buttons never take keyboard/pad focus.
	var menu_buttons := {"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B}
	for action: String in menu_buttons:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = menu_buttons[action]
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
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
	app.selection.tick(delta)
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
	settings_panel=null
	roster_cards.clear()
	stage_cards.clear()
	fighter_portraits.clear()
	fighter_names.clear()
	fighter_states.clear()
	slot_buttons.clear()
	battle_style = false
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
	var poster := texture(load("res://art/ui/title-poster.png"), Rect2(0,0,1280,720))
	poster.name="TitlePoster"
	poster.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	button("mode_cpu","单人对战",Rect2(55,357,300,51),func():app.choose_mode("cpu"),true,true,26).grab_focus()
	button("mode_local","双人对战",Rect2(55,420,300,51),func():app.choose_mode("local"),false,true,25)
	button("mode_practice","自由练习",Rect2(55,483,300,51),func():app.choose_mode("practice"),false,true,25)
	button("help","帮助",Rect2(55,546,300,51),app.show_help,false,true,25)
	button("settings","游戏设置",Rect2(55,609,300,51),app.show_settings,false,true,25)
	reveal()

func settings() -> void:
	settings_panel=SettingsPanel.new()
	settings_panel.build(self)

func slash(bounds: Rect2, color: Color, cut: float = 40) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([bounds.position + Vector2(cut, 0), Vector2(bounds.end.x, bounds.position.y), bounds.end - Vector2(cut, 0), Vector2(bounds.position.x, bounds.end.y)])
	polygon.color = color
	add_child(polygon)

func hero_portrait(id: String, bounds: Rect2, faces_right: bool) -> TextureRect:
	var visual = catalog.characters[id]
	var node := TextureRect.new()
	node.position = bounds.position
	node.size = bounds.size
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	_set_hero(node, visual, faces_right)
	return node

func _set_hero(node: TextureRect, visual: Resource, faces_right: bool) -> void:
	if visual.portrait == null: return
	var crop := AtlasTexture.new()
	crop.atlas = visual.portrait
	var height: float = visual.portrait.get_height() * 0.72
	var width: float = minf(visual.portrait.get_width(), height * node.size.x / node.size.y)
	var center: float = visual.menu_focus_x * visual.portrait.get_width()
	crop.region = Rect2(clampf(center - width * 0.5, 0, visual.portrait.get_width() - width), 0, width, height)
	node.texture = crop
	node.flip_h = faces_right != visual.portrait_faces_right

func setup() -> void:
	rect(Rect2(0, 0, 1280, 720), Color("09111f"))
	slash(Rect2(0, 76, 529, 351), Color("153642"), 72)
	slash(Rect2(751, 76, 529, 351), Color("422639"), 72)
	label("选择角色", Rect2(47, 22, 495, 56), 36, PAPER, true)
	label("练习" if app.mode == "practice" else ("单人" if app.mode == "cpu" else "双人"), Rect2(1053, 30, 179, 30), 17, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	rule(Vector2(49, 83), 1182, Color(GOLD, 0.28))
	for slot in range(2):
		var left := slot == 0
		var x := 56.0 if left else 872.0
		var portrait_node := hero_portrait(app.characters[slot], Rect2(48 if left else 796, 92, 436, 304), left)
		fighter_portraits.append(portrait_node)
		slot_buttons.append(button("slot_%d" % [slot+1], "P%d" % [slot+1], Rect2(56 if left else 1110, 394, 114, 35), func(): app.selection.activate(slot), false, false, 17))
		fighter_states.append(label("", Rect2(x, 432, 352, 25), 16, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT if not left else HORIZONTAL_ALIGNMENT_LEFT))
		fighter_names.append(label("", Rect2(191 if left else 758, 389, 333, 47), 31, PAPER, true, HORIZONTAL_ALIGNMENT_RIGHT if not left else HORIZONTAL_ALIGNMENT_LEFT))
	label("VS", Rect2(529, 209, 222, 103), 77, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	roster_scroll = ScrollContainer.new()
	roster_scroll.name = "RosterScroll"
	roster_scroll.position = Vector2(319, 450)
	roster_scroll.size = Vector2(642, 192)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(roster_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(center)
	var grid := GridContainer.new()
	grid.columns = mini(6, catalog.characters.size())
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	center.add_child(grid)
	for id: String in catalog.characters:
		var card := RosterCard.new()
		card.name = "character_" + id
		card.custom_minimum_size = Vector2(96, 88)
		card.portrait = catalog.characters[id].avatar
		card.tooltip_text = catalog.characters[id].display_name
		card.pressed.connect(func(): app.select_character(app.selection.active_slot, id))
		card.mouse_entered.connect(card.queue_redraw)
		card.mouse_exited.connect(card.queue_redraw)
		card.focus_entered.connect(card.queue_redraw)
		card.focus_exited.connect(card.queue_redraw)
		grid.add_child(card)
		roster_cards[id] = card
		actions["character_" + id] = card
	button("back", "返回", Rect2(48, 663, 130, 39), app.show_title, false, false, 17)
	app.device_notice = label("", Rect2(213, 669, 760, 29), 15, MUTED)
	app.start_button = button("start", "确认", Rect2(1006, 654, 225, 48), func(): app.selection.confirm(app.selection.active_slot), true, true, 21)
	refresh_setup()
	reveal()

func refresh_setup() -> void:
	if app.screen != "setup" or fighter_portraits.size() != 2: return
	for slot in range(2):
		var visual = catalog.characters[app.characters[slot]]
		_set_hero(fighter_portraits[slot], visual, slot == 0)
		fighter_names[slot].text = visual.display_name
		fighter_states[slot].text = "已就绪" if app.selection.ready[slot] else ("选择中" if app.mode == "local" or app.selection.active_slot == slot else "")
		fighter_states[slot].modulate = Color("69dbea") if slot == 0 else Color("f191ae")
		slot_buttons[slot].text = "P1" if slot == 0 else ("木桩" if app.mode == "practice" else "CPU" if app.mode == "cpu" else "P2")
		slot_buttons[slot].selected = app.selection.active_slot == slot
	for id: String in roster_cards:
		var card: Button = roster_cards[id]
		card.cursors.clear()
		card.locked.assign(app.selection.ready)
		for slot in range(2):
			if app.characters[slot] == id: card.cursors.append(slot)
		card.queue_redraw()
	var current: Button = roster_cards[app.characters[app.selection.active_slot]]
	current.grab_focus()
	roster_scroll.ensure_control_visible.call_deferred(current)
	app.start_button.text = "确认 P%d" % [app.selection.active_slot + 1] if app.mode == "local" else "确认"
	app._validate_setup()

func stages() -> void:
	rect(Rect2(0, 0, 1280, 720), Color("09111f"))
	slash(Rect2(623, 0, 657, 720), Color("202b40"), 140)
	label("选择场景", Rect2(49, 35, 600, 63), 41, PAPER, true)
	rule(Vector2(51, 113), 1178, Color(GOLD, 0.32))
	var index := 0
	var columns := mini(4, catalog.stages.size())
	var rows := ceili(float(catalog.stages.size()) / columns)
	var card_width := (1178.0 - (columns - 1) * 20.0) / columns
	var card_height := minf(337.0, (432.0 - (rows - 1) * 18.0) / rows)
	var top := 158.0 + (432.0 - rows * card_height - (rows - 1) * 18.0) * 0.5
	for id: String in catalog.stages:
		var visual = catalog.stages[id]
		var card := StageCard.new()
		card.name = "stage_" + id
		card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.caption = visual.display_name
		card.preview = visual.thumbnail
		card.position = Vector2(51 + (index % columns) * (card_width + 20), top + (index / columns) * (card_height + 18))
		card.size = Vector2(card_width, card_height)
		card.pressed.connect(func(): app.stage_id = id; refresh_stages())
		add_child(card)
		actions["stage_" + id] = card
		stage_cards[id] = card
		index += 1
	button("back", "返回选人", Rect2(51, 660, 180, 42), app.show_setup, false, false, 18)
	app.device_notice = label("", Rect2(274, 666, 677, 30), 15, MUTED)
	app.start_button = button("start", "开战", Rect2(974, 647, 257, 56), func(): app.selection.confirm(0), true, true, 25)
	refresh_stages()
	reveal()

func refresh_stages() -> void:
	for id: String in stage_cards:
		stage_cards[id].selected = id == app.stage_id
		stage_cards[id].queue_redraw()
	if stage_cards.has(app.stage_id): stage_cards[app.stage_id].grab_focus()
	app._validate_setup()

func portrait(id: String, bounds: Rect2, flip: bool = false, moving: bool = false) -> void:
	var visual = catalog.characters[id]
	if visual.portrait == null:
		return
	var node := texture(visual.portrait, bounds)
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.flip_h = flip != visual.portrait_faces_right
	if moving:
		decorative.append({"node": node, "origin": bounds.position, "phase": decorative.size() * 1.7})

func battle() -> void:
	battle_style = true
	if app.mode == "practice":
		button("practice_options", "练习设置 F3", Rect2(507, 694, 150, 26), app.show_practice_options, false, false, 13).focus_mode = Control.FOCUS_NONE
	button("pause", "暂停  Esc", Rect2(680, 694, 112, 26), func(): app.set_paused(true), false, false, 13).focus_mode = Control.FOCUS_NONE

func pause(reason: String) -> void:
	battle_style=false
	rect(Rect2(0,0,1280,720),Color(0.018,0.03,0.065,0.72))
	panel(Rect2(399,43,482,634))
	label("P A U S E",Rect2(434,77,412,23),14,GOLD,false,HORIZONTAL_ALIGNMENT_CENTER)
	label("暂停对战",Rect2(424,111,432,67),45,PAPER,true,HORIZONTAL_ALIGNMENT_CENTER)
	label(reason,Rect2(426,187,428,54),16,MUTED,false,HORIZONTAL_ALIGNMENT_CENTER)
	var resume:=button("resume","继续练习" if app.mode=="practice" else "继续对战",Rect2(449,260,382,49),func():app.set_paused(false),true,true)
	resume.disabled=not app._devices_ready()
	button("restart","重置练习" if app.mode=="practice" else "重新开始比赛",Rect2(449,323,382,43),app.start_match,false,false,19)
	button("move_list","帮助与招式表",Rect2(449,379,382,43),app.show_help,false,false,19)
	button("settings","游戏设置",Rect2(449,435,382,43),app.show_settings,false,false,19)
	if app.mode=="practice":
		button("practice_options","木桩与气槽设置",Rect2(449,491,382,43),app.show_practice_options,false,false,19)
	button("setup","返回选人",Rect2(449,574,382,43),app.show_setup,false,false,19)
	if resume.disabled:actions.settings.grab_focus()
	else:resume.grab_focus()
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
	label("月色如初，再决胜负。", Rect2(685, 662, 495, 26), 17, MUTED, true)
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
	label("操作指南", Rect2(48, 25, 560, 64), 43, PAPER, true)
	label("A / B 轻攻击 · C / D 重攻击  /  方向随朝向解释", Rect2(52, 104, 1176, 30), 19, MUTED)
	if page == "basics":
		panel(Rect2(50, 164, 553, 461))
		panel(Rect2(627, 164, 604, 461))
		label("壹 / 按键与移动", Rect2(75, 181, 508, 42), 25, Color("82d4de"), true)
		var keys1: Array=app.router.current_keys(0)
		var keys2: Array=app.router.current_keys(1)
		var rows := [["移动 / 跳跃",app.router.movement_hint(0),app.router.movement_hint(1)]]
		for index in range(4):
			rows.append([["A 轻攻击","B 轻体术","C 重攻击","D 重体术"][index],app.router.key_name(keys1[index+4]),app.router.key_name(keys2[index+4])])
		label("键盘 P1", Rect2(280, 233, 123, 24), 15, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
		label("键盘 P2", Rect2(439, 233, 123, 24), 15, GOLD, false, HORIZONTAL_ALIGNMENT_CENTER)
		for i in range(rows.size()):
			var y := 273 + i * 43
			label(rows[i][0], Rect2(77, y, 181, 31), 18)
			keycap(rows[i][1], Rect2(280, y, 123, 32))
			keycap(rows[i][2], Rect2(439, y, 123, 32))
		label("觉醒 B+C：P1 %s+%s / P2 %s+%s" % [app.router.key_name(keys1[5]), app.router.key_name(keys1[6]), app.router.key_name(keys2[5]), app.router.key_name(keys2[6])], Rect2(75, 489, 508, 27), 16, GOLD)
		label("手柄 X/A/Y/B 对应 A/B/C/D；觉醒 A+Y", Rect2(75, 517, 508, 27), 15, MUTED)
		label("236 = ↓↘→；214 = ↓↙←，朝左时镜像。\n双击前后可短冲刺；按键可在游戏设置中修改。",Rect2(75,547,508,56),16,GOLD)
		label("贰 / 攻防与资源", Rect2(652, 181, 553, 42), 25, GOLD, true)
		var lessons := [
			"后方向站防，后下方向蹲防；跳攻站防、下段蹲防。",
			"近身 6+D 前投 / 4+D 背投，抓取后 7 帧内 D 拆投。",
			"A+B 前滚 / 4+A+B 后滚；可躲打击，但全程可被投。",
			"236 / 214 可省斜方向，0.5秒完成；攻击可晚0.2秒。",
			"轻技 → 重技 → 必杀 → 超杀；空挥不能取消。",
			"236236+A/C 超杀耗 1 格；236236+A+C MAX 耗 3 格。",
			"B+C 耗2格：普通觉醒10秒，普通技命中快速觉醒6秒。",
			"觉醒不回气：超杀1格保留觉醒；MAX1格耗尽觉醒。"]
		for i in range(lessons.size()):
			label(lessons[i], Rect2(654, 244 + i * 43, 549, 39), 17, PAPER)
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
				var y := 170 + i * 58
				label(row.input, Rect2(75, y, 246, 43), 22, definition.accent)
				label(row.name, Rect2(330, y, 860, 29), 22, PAPER, true)
				var description: String = row.description
				if i == 3:
					description += "；觉醒中伤害110%，耗1格，保留觉醒"
				elif i == 4:
					description += "；觉醒中耗1格，并耗尽觉醒"
				label(description, Rect2(333, y + 28, 855, 24), 15, MUTED)
				rule(Vector2(75, y + 57), 1115, Color(GOLD, 0.18))
			label("B+C · " + definition.awakening.display_name + " · 2格 / 普通10秒、快速6秒", Rect2(75, 464, 1115, 24), 16, definition.accent)
			label(definition.awakening.effect_summary(), Rect2(75, 491, 1115, 24), 15, MUTED)
			label("示例连段 / j. 为空中，5 为站立，2 为蹲下", Rect2(75, 520, 1115, 26), 17, GOLD)
			for i in range(definition.combos.size()):
				label(definition.combos[i], Rect2(76 + (i % 2) * 571, 553 + int(i / 2) * 36, 554, 30), 18)
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
	battle_style = false
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
	for item in [["0 格", 0], ["1 格", 1], ["2 格", 4], ["3 格", 2], ["无限气", 3]]:
		meter.add_item(item[0], item[1])
	meter.select(meter.get_item_index(app.practice_controller.meter_mode))
	meter.item_selected.connect(func(index: int): app.practice_controller.meter_mode = meter.get_item_id(index); app.practice_controller.apply_meter(app.combat))
	var details := CheckButton.new()
	details.text = "展开输入指导与搓招提示"
	details.position = Vector2(355, 380)
	details.size = Vector2(567, 42)
	details.button_pressed = app.view.hud.practice_details
	details.toggled.connect(func(value: bool): app.view.hud.practice_details = value)
	details.add_theme_color_override("font_color", PAPER)
	add_child(details)
	actions["practice_details"] = details
	var awakening := CheckButton.new()
	awakening.text = "觉醒时间无限（仍需 B+C 发动）"
	awakening.position = Vector2(355, 423)
	awakening.size = Vector2(567, 42)
	awakening.button_pressed = app.practice_controller.awakening_infinite
	awakening.toggled.connect(func(value: bool): app.practice_controller.awakening_infinite = value; app.combat.awakening_infinite = value)
	awakening.add_theme_color_override("font_color", PAPER)
	add_child(awakening)
	actions["practice_awakening"] = awakening
	label("连段结束后自动补血；Backspace 重置并解除觉醒。", Rect2(355, 474, 567, 30), 16, MUTED)
	button("resume", "继续练习", Rect2(355, 515, 267, 49), func(): app.set_paused(false), true, true, 21).grab_focus()
	button("practice_reset", "重置位置", Rect2(649, 515, 273, 49), func(): app.reset_practice(); app.set_paused(false), false, false, 21)
	reveal()


func keycap(value: String, bounds: Rect2) -> void:
	rect(bounds, Color("242d43"))
	rule(bounds.position + Vector2(0, bounds.size.y - 1), bounds.size.x, Color("6d738a"))
	label(value, bounds, 17, PAPER, false, HORIZONTAL_ALIGNMENT_CENTER)

func label(value: String, bounds: Rect2, font_size: int = 18, color: Color = PAPER, serif: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	if battle_style:
		if color == PAPER: color = BattleStyle.PAPER
		elif color == GOLD: color = BattleStyle.GOLD
		elif color == MUTED: color = BattleStyle.MUTED
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
	node.battle_style = battle_style
	node.text_only = battle_style and bounds.size.y < 30
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
