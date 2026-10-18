extends Control
## Native controls over illustrated scenery in the 「大正墨金」style. The title
## poster carries its own lettering; every other screen is built from the kit.
## Entry motion only offsets drawing, so controls are clickable immediately.
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const RosterCard = preload("res://scripts/ui/roster_card.gd")
const Selection = preload("res://scripts/ui/selection_controller.gd")
const StageCard = preload("res://scripts/ui/stage_card.gd")
const DuelButton = preload("res://scripts/ui/duel_button.gd")
const BattleStyle = preload("res://scripts/presentation/battle_style.gd")
const Kit = preload("res://scripts/ui/kit.gd")
const Backdrop = preload("res://scripts/ui/screen_backdrop.gd")
const Header = preload("res://scripts/ui/screen_header.gd")
const PromptBar = preload("res://scripts/ui/prompt_bar.gd")
const PromptLabel = preload("res://scripts/ui/prompt_label.gd")
const Wipe = preload("res://scripts/ui/screen_wipe.gd")
const Showcase = preload("res://scripts/ui/fighter_showcase.gd")
const StagePreview = preload("res://scripts/ui/stage_preview.gd")
const Glyphs = preload("res://scripts/ui/command_glyphs.gd")
const GradientText = preload("res://scripts/ui/gradient_text.gd")
const Brush = preload("res://scripts/ui/brush_stroke.gd")
const PAUSE_SHADER = preload("res://scripts/ui/shaders/pause_backdrop.gdshader")
const PAPER := Kit.PAPER
const GOLD := Kit.GOLD
const MUTED := Kit.MUTED
const RED := Kit.CRIMSON
const STEPS := ["角色", "场景", "开战"]
const MODE_NAMES := {"cpu": "单人对战 · VS CPU", "local": "双人对战", "practice": "自由练习"}
const TITLE_ITEMS := [
	["mode_cpu", "单人对战", "ARCADE · VS CPU", "与电脑对手一决胜负，先取两回合者获胜。"],
	["mode_local", "双人对战", "VERSUS · LOCAL", "两名玩家同屏对战，可用键盘或手柄。"],
	["mode_practice", "自由练习", "TRAINING", "木桩练习连段、必杀、超杀与觉醒。"],
	["help", "帮助", "GUIDE · MOVE LIST", "按键、攻防规则与全角色招式表。"],
	["settings", "游戏设置", "OPTIONS", "音量、按键、手柄与必杀动画演出。"]]
var settings_panel: RefCounted
var roster_scroll: ScrollContainer
## Character cells by id; `roster_cells` holds every grid cell in display order.
var roster_cards: Dictionary = {}
var roster_cells: Array[Button] = []
var random_card: Button
var stage_cards: Dictionary = {}
var fighter_portraits: Array = []
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
var backdrop: Control
var preview: Control
var footer: Control
var embers: Node2D
# The back label and extra hints the footer is rebuilt from when the device changes.
var _footer_prompt: Array[String] = ["", ""]
var _footer_device: String = ""
var _last_screen: String = ""
var _quiet: bool = true

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
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	theme = catalog.ui_assets().build_theme(catalog.body_font, catalog.title_font)
	for side in ["left", "right", "bottom"]:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(Kit.INK_900, 0.97), Color(Kit.INK_800, 0.8), Color(Kit.INK_800, 0)])
		gradient.offsets = PackedFloat32Array([0, 0.5, 1])
		var shade := GradientTexture2D.new()
		shade.gradient = gradient
		shade.width = 256
		shade.height = 128
		shade.fill_from = Vector2(1, 0) if side == "right" else (Vector2(0, 1) if side == "bottom" else Vector2.ZERO)
		shade.fill_to = Vector2.ZERO if side in ["right", "bottom"] else Vector2(1, 0)
		shades[side] = shade

func _process(delta: float) -> void:
	app.selection.tick(delta)
	_refresh_footer()
	if app.paused:
		return
	motion_time += delta
	if is_instance_valid(embers):
		embers.queue_redraw()
	if is_instance_valid(result_sparks) and result_spark_time < 2.4:
		result_spark_time += delta
		result_sparks.queue_redraw()
	for entry: Dictionary in decorative:
		if is_instance_valid(entry.node):
			entry.node.position = entry.origin + Vector2(sin(motion_time * 0.38 + entry.phase) * 2, cos(motion_time * 0.32 + entry.phase) * 1.8)

func clear() -> void:
	settings_panel = null
	roster_cards.clear()
	roster_cells.clear()
	random_card = null
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
	backdrop = null
	preview = null
	footer = null
	embers = null
	_quiet = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	actions.clear()
	app.setup_options.clear()
	app.device_notice = null
	app.start_button = null

func reveal() -> void:
	var fresh: bool = app.screen != _last_screen
	_last_screen = app.screen
	modulate = Color.WHITE
	if fresh and app.screen != "battle":
		add_child(Wipe.new())
	var focusable: Array[Control] = []
	var order := 0
	for child in actions.values():
		if child is DuelButton and not child.battle_style and not child.keycap and not child.tab:
			# Short, capped stagger: everything settles within ~0.35 s.
			child.intro_delay = (0.04 if fresh else 0.0) + mini(order, 5) * 0.025
			child.intro_time = 0.0
			order += 1
		if child is BaseButton and child.focus_mode != Control.FOCUS_NONE and not child.disabled:
			focusable.append(child)
	for i in range(focusable.size()):
		var previous := focusable[(i - 1 + focusable.size()) % focusable.size()]
		var next := focusable[(i + 1) % focusable.size()]
		focusable[i].focus_neighbor_top = focusable[i].get_path_to(previous)
		focusable[i].focus_neighbor_bottom = focusable[i].get_path_to(next)
		focusable[i].focus_previous = focusable[i].get_path_to(previous)
		focusable[i].focus_next = focusable[i].get_path_to(next)
	_unquiet.call_deferred()

func _unquiet() -> void:
	_quiet = false

func _focus_cue() -> void:
	if not _quiet and app.sound != null:
		app.sound.play("ui_move", 0.35)

# --- Shared prompts ---------------------------------------------------------------

func _prompts(back_label: String = "返回", extra: String = "") -> String:
	var parts: Array[String] = []
	if str(app.menu_device).begins_with("pad:"):
		parts.append("十字键 选择")
		parts.append("A 确认")
		if not back_label.is_empty():
			parts.append("B " + back_label)
	else:
		var keys: Array = app.router.current_keys(0)
		parts.append("%s 确认" % app.router.key_name(keys[4]))
		if not back_label.is_empty():
			parts.append("%s %s" % [app.router.key_name(keys[5]), back_label])
	if not extra.is_empty():
		parts.append(extra)
	return " · ".join(parts)

func _footer(bounds: Rect2, back_label: String, extra: String = "", note: String = "", align: int = 2) -> Control:
	var bar := PromptBar.new()
	bar.position = bounds.position
	bar.size = bounds.size
	bar.font = catalog.body_font
	bar.note_font = catalog.body_font
	bar.align = align
	bar.note = note
	add_child(bar)
	footer = bar
	_footer_prompt.assign([back_label, extra])
	_footer_device = ""
	_refresh_footer()
	return bar

## Keeps footer keys on the device that last drove the menu (the title screen
## switches between keyboard and pad on each press).
func _refresh_footer() -> void:
	if is_instance_valid(footer) and _footer_device != app.menu_device:
		_footer_device = app.menu_device
		footer.text = _prompts(_footer_prompt[0], _footer_prompt[1])

func _header(title_text: String, kicker: String, chip: String = "", step: int = -1) -> Control:
	var header := Header.new()
	header.title = title_text
	header.kicker = kicker
	header.chip = chip
	header.step = step
	if step >= 0:
		header.steps = PackedStringArray(STEPS)
	header.display_font = catalog.display_font
	header.title_font = catalog.title_font
	header.numeric_font = catalog.numeric_font
	add_child(header)
	return header

func _backdrop(left: Color, right: Color, strength: float = 0.55) -> Control:
	backdrop = Backdrop.new()
	backdrop.set_tints(left, right, strength)
	add_child(backdrop)
	return backdrop

func _pause_veil() -> void:
	var veil := ColorRect.new()
	veil.name = "PauseVeil"
	veil.size = Vector2(1280, 720)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paint := ShaderMaterial.new()
	paint.shader = PAUSE_SHADER
	veil.material = paint
	add_child(veil)

# --- Title --------------------------------------------------------------------------

func title() -> void:
	var poster := texture(load("res://art/ui/title-poster.png"), Rect2(0,0,1280,720))
	poster.name="TitlePoster"
	poster.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Soft ink wash under the menu keeps it legible over the crowded poster.
	paint(Rect2(0, 0, 1280, 720), func(canvas: Control):
		Kit.shade(canvas, Rect2(0, 180, 760, 540), Kit.INK_900, func(u: float, v: float) -> float:
			return 0.9 * (1.0 - smoothstep(0.35, 1.0, u)) * smoothstep(0.0, 0.42, v))
		Kit.shade(canvas, Rect2(0, 560, 1280, 160), Kit.INK_900, func(_u: float, v: float) -> float:
			return 0.85 * smoothstep(0.0, 1.0, v)))
	embers = Node2D.new()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = additive
	embers.draw.connect(_draw_embers)
	add_child(embers)
	var captions := {}
	var callbacks := {"mode_cpu": func(): app.choose_mode("cpu"), "mode_local": func(): app.choose_mode("local"),
		"mode_practice": func(): app.choose_mode("practice"), "help": app.show_help, "settings": app.show_settings}
	for i in range(TITLE_ITEMS.size()):
		var item: Array = TITLE_ITEMS[i]
		var node := button(item[0], item[1], Rect2(56, 350 + i * 60, 336, 54), callbacks[item[0]], false, true, 24)
		node.kicker = Kit.numeral(i + 1)
		node.subtitle = item[2]
		captions[node] = item[3]
	var bar := _footer(Rect2(56, 666, 1168, 36), "", "F2 静音", TITLE_ITEMS[0][3])
	for node: Control in captions:
		node.focus_entered.connect(func(): bar.note = captions[node])
	actions.mode_cpu.grab_focus()
	reveal()

func _draw_embers() -> void:
	for i in range(26):
		var phase := i * 2.399
		var y := fposmod(700.0 - motion_time * (14.0 + (i % 5) * 6.0) - i * 61.0, 760.0) - 20.0
		var x := fposmod(80.0 + i * 197.3 + sin(motion_time * 0.5 + phase) * 26.0, 1280.0)
		var life := clampf(y / 720.0, 0, 1)
		var flicker := 0.55 + 0.45 * sin(motion_time * 3.0 + phase * 2.0)
		var color := Color(1.0, 0.62 + (i % 3) * 0.08, 0.32, 0.5 * flicker * life)
		embers.draw_circle(Vector2(x, y), 4.0 + (i % 3), Color(color, color.a * 0.25), true, -1, true)
		embers.draw_circle(Vector2(x, y), 1.4 + (i % 3) * 0.5, color, true, -1, true)

func settings() -> void:
	settings_panel=SettingsPanel.new()
	settings_panel.build(self)

# --- Character select ------------------------------------------------------------------

func setup() -> void:
	_backdrop(Color("1d4f5c"), Color("5c1d2a"))
	_header("选择角色", "CHARACTER SELECT", MODE_NAMES.get(app.mode, ""), 0)
	var avatars: Array[Texture2D] = []
	for id: String in catalog.characters:
		if catalog.characters[id].avatar != null:
			avatars.append(catalog.characters[id].avatar)
	for slot in range(2):
		var showcase := Showcase.new()
		showcase.slot = slot
		showcase.display_font = catalog.display_font
		showcase.title_font = catalog.title_font
		showcase.body_font = catalog.body_font
		showcase.avatars = avatars
		add_child(showcase)
		fighter_portraits.append(showcase)
	for slot in range(2):
		var left := slot == 0
		var align := HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
		slot_buttons.append(button("slot_%d" % [slot+1], "P%d" % [slot+1], Rect2(24 if left else 1152, 104, 104, 32), func(): app.selection.activate(slot), false, false, 17))
		fighter_states.append(label("", Rect2(24 if left else 1056, 140, 200, 22), 15, MUTED, false, align))
		fighter_names.append(label("", Rect2(24 if left else 876, 486, 380, 66), 56, PAPER, false, align, "display"))
		fighter_portraits[slot].name_label = fighter_names[slot]
	paint(Rect2(412, 112, 456, 488), _draw_roster_plate)
	roster_scroll = ScrollContainer.new()
	roster_scroll.name = "RosterScroll"
	roster_scroll.position = Vector2(425, 150)
	roster_scroll.size = Vector2(430, 430)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(roster_scroll)
	var grid := GridContainer.new()
	grid.columns = Selection.COLS
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	roster_scroll.add_child(grid)
	var cells: Array[String] = app.selection.cells()
	for index in range(cells.size()):
		var id := cells[index]
		var card := RosterCard.new()
		card.tag_font = catalog.numeric_font
		card.glyph_font = catalog.display_font
		card.label_font = catalog.body_font
		var key := "character_" + id
		if catalog.characters.has(id):
			card.portrait = catalog.characters[id].avatar
			card.accent = catalog.characters[id].accent
			card.tooltip_text = catalog.characters[id].display_name
			card.pressed.connect(func(): app.select_character(app.selection.active_slot, id))
			roster_cards[id] = card
		elif id == Selection.RANDOM:
			key = "random"
			card.kind = "random"
			card.tooltip_text = "随机角色"
			card.pressed.connect(func(): app.selection.point(app.selection.active_slot, index))
			random_card = card
		else:
			key = "empty_%d" % index
			card.kind = "empty"
			card.tooltip_text = "敬请期待"
			card.pressed.connect(func(): app.selection.point(app.selection.active_slot, index))
		card.name = key
		# Unowned arrow keys move GUI focus; keep the active cursor on the focused cell.
		card.focus_entered.connect(func():
			if app.screen == "setup" and app.selection.cursor_cell(app.selection.active_slot) != index:
				app.selection.point(app.selection.active_slot, index))
		for signal_name: String in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
			card.connect(signal_name, card.queue_redraw)
		grid.add_child(card)
		roster_cells.append(card)
		actions[key] = card
	button("back", "返回", Rect2(426, 612, 150, 44), app.show_title, false, false, 18)
	app.device_notice = prompt_label(Rect2(160, 678, 960, 30))
	app.start_button = button("start", "确认", Rect2(634, 608, 220, 50), func(): app.selection.confirm(app.selection.active_slot), true, true, 22)
	refresh_setup()
	reveal()
	_link_grid()

## Arrow-key focus inside the grid wraps on both axes like the selection cursors;
## reveal() keeps Tab cycling through the grid, back and start.
func _link_grid() -> void:
	var columns := Selection.COLS
	var rows := int(roster_cells.size() / float(columns))
	for i in range(roster_cells.size()):
		var card := roster_cells[i]
		var row := int(i / float(columns))
		var column := i % columns
		card.focus_neighbor_left = card.get_path_to(roster_cells[row * columns + posmod(column - 1, columns)])
		card.focus_neighbor_right = card.get_path_to(roster_cells[row * columns + posmod(column + 1, columns)])
		card.focus_neighbor_top = card.get_path_to(roster_cells[posmod(row - 1, rows) * columns + column])
		card.focus_neighbor_bottom = card.get_path_to(roster_cells[posmod(row + 1, rows) * columns + column])

func _draw_roster_plate(canvas: Control) -> void:
	var rect := Rect2(Vector2.ZERO, canvas.size)
	var shape := Kit.chamfer(rect, 16, 5)
	Kit.gradient_fill(canvas, shape, Color(Kit.INK_700, 0.88), Color(Kit.INK_900, 0.94))
	Kit.frame(canvas, shape, Kit.GOLD, 0.8, 2.0, 1.0)
	Kit.brackets(canvas, rect.grow(-6), 12, Color(Kit.GOLD_HI, 0.45), 1.2)
	Kit.tracked(canvas, catalog.numeric_font, "ROSTER", Vector2(20, 26), 11, Color(Kit.GOLD, 0.75), 3.0)
	var slots: int = app.selection.cells().size() - 1
	Kit.tracked(canvas, catalog.numeric_font, "%d / %d" % [catalog.characters.size(), slots], Vector2(rect.size.x - 20, 26), 11,
		Color(Kit.GOLD, 0.6), 2.0, 2)
	Kit.rule(canvas, Vector2(20, 32), Vector2(rect.size.x - 20, 32), Color(Kit.GOLD, 0.4))

func _cell_kind(slot: int) -> String:
	var id: String = app.selection.cell_id(slot)
	return "random" if id == Selection.RANDOM else ("empty" if id.is_empty() else "character")

func refresh_setup() -> void:
	if app.screen != "setup" or fighter_portraits.size() != 2: return
	var selection: RefCounted = app.selection
	var tints: Array[Color] = []
	for slot in range(2):
		var kind := _cell_kind(slot)
		var visual = catalog.characters[app.characters[slot]]
		var definition: Resource = app.combat.catalog.characters.get(app.characters[slot])
		var active: bool = app.mode == "local" or selection.active_slot == slot
		fighter_portraits[slot].configure(kind, visual, definition, selection.ready[slot], active, selection.rolled[slot])
		fighter_names[slot].text = visual.display_name if kind == "character" else ("随机角色" if kind == "random" else "敬请期待")
		fighter_states[slot].text = "已就绪" if selection.ready[slot] else ("选择中…" if app.mode == "local" or selection.active_slot == slot else "")
		fighter_states[slot].modulate = Kit.player_color(slot)
		slot_buttons[slot].text = "P1" if slot == 0 else ("木桩" if app.mode == "practice" else "CPU" if app.mode == "cpu" else "P2")
		slot_buttons[slot].selected = selection.active_slot == slot
		tints.append(visual.accent.darkened(0.45) if kind == "character" else Kit.INK_600)
	if backdrop != null:
		backdrop.set_tints(tints[0], tints[1], 0.6)
	for i in range(roster_cells.size()):
		var card := roster_cells[i]
		card.cursors.clear()
		card.locked.assign(selection.ready)
		for slot in range(2):
			if selection.cursor_cell(slot) == i: card.cursors.append(slot)
		card.queue_redraw()
	var current := roster_cells[selection.cursor_cell(selection.active_slot)]
	current.grab_focus()
	roster_scroll.ensure_control_visible.call_deferred(current)
	app.start_button.text = "确认 P%d" % [selection.active_slot + 1] if app.mode == "local" else "确认"
	app._validate_setup()

# --- Stage select -------------------------------------------------------------------

func stages() -> void:
	_backdrop(Color("27304f"), Color("4a2034"))
	_header("选择场景", "STAGE SELECT", MODE_NAMES.get(app.mode, ""), 1)
	preview = StagePreview.new()
	preview.display_font = catalog.display_font
	preview.title_font = catalog.title_font
	preview.body_font = catalog.body_font
	preview.numeric_font = catalog.numeric_font
	for slot in range(2):
		preview.avatars.append(catalog.characters[app.characters[slot]].avatar)
	add_child(preview)
	var count: int = catalog.stages.size()
	var gap := 14.0
	var card_height := minf(106.0, (470.0 - (count - 1) * gap) / count)
	var top := 140.0 + (470.0 - count * card_height - (count - 1) * gap) * 0.5
	var index := 0
	for id: String in catalog.stages:
		var visual = catalog.stages[id]
		var card := StageCard.new()
		card.name = "stage_" + id
		card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.caption = visual.display_name
		card.subtitle = visual.subtitle
		card.preview = visual.thumbnail
		card.title_font = catalog.title_font
		card.body_font = catalog.body_font
		card.position = Vector2(840, top + index * (card_height + gap))
		card.size = Vector2(400, card_height)
		card.pressed.connect(func(): app.stage_id = id; refresh_stages())
		add_child(card)
		actions["stage_" + id] = card
		stage_cards[id] = card
		index += 1
	button("back", "返回选人", Rect2(40, 664, 190, 44), app.show_setup, false, false, 18)
	app.device_notice = prompt_label(Rect2(250, 668, 740, 36))
	app.start_button = button("start", "开战", Rect2(1010, 656, 230, 54), func(): app.selection.confirm(0), true, true, 25)
	refresh_stages()
	reveal()

func refresh_stages() -> void:
	for id: String in stage_cards:
		stage_cards[id].selected = id == app.stage_id
		stage_cards[id].queue_redraw()
	if preview != null and catalog.stages.has(app.stage_id):
		preview.set_stage(catalog.stages[app.stage_id])
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

# --- Battle footer and pause ------------------------------------------------------------

func battle() -> void:
	battle_style = true
	if app.mode == "practice":
		var options := button("practice_options", "练习设置", Rect2(486, 694, 150, 26), app.show_practice_options, false, false, 13)
		options.focus_mode = Control.FOCUS_NONE
		options.hotkey = "F3"
	var pause_button := button("pause", "暂停", Rect2(652, 694, 128, 26), func(): app.set_paused(true), false, false, 13)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.hotkey = "Esc"

func pause(reason: String) -> void:
	battle_style=false
	_pause_veil()
	paint(Rect2(0, 0, 1280, 720), _draw_pause_panel)
	var resume:=button("resume","继续练习" if app.mode=="practice" else "继续对战",Rect2(48,252,410,58),func():app.set_paused(false),true,true,24)
	resume.subtitle = "RESUME"
	resume.disabled=not app._devices_ready()
	var items := [["restart","重置练习" if app.mode=="practice" else "重新开始比赛","RESTART",app.start_match],
		["move_list","帮助与招式表","MOVE LIST",app.show_help],["settings","游戏设置","OPTIONS",app.show_settings]]
	if app.mode=="practice":
		items.append(["practice_options","木桩与气槽设置","TRAINING",app.show_practice_options])
	items.append(["setup","返回选人","CHARACTER SELECT",app.show_setup])
	for i in range(items.size()):
		var node := button(items[i][0],items[i][1],Rect2(48,322+i*56,410,50),items[i][3],false,true,19)
		node.subtitle = items[i][2]
	label(reason,Rect2(56,206,410,40),14,Kit.GOLD_HI,false,HORIZONTAL_ALIGNMENT_LEFT)
	_footer(Rect2(48, 666, 1184, 36), "继续")
	if resume.disabled:actions.settings.grab_focus()
	else:resume.grab_focus()
	reveal()

func _draw_pause_panel(canvas: Control) -> void:
	var panel := PackedVector2Array([Vector2(0, 0), Vector2(520, 0), Vector2(470, 720), Vector2(0, 720)])
	var colors := PackedColorArray([Color(Kit.INK_800, 0.97), Color(Kit.INK_800, 0.9), Color(Kit.INK_900, 0.9), Color(Kit.INK_900, 0.97)])
	canvas.draw_polygon(panel, colors)
	canvas.draw_line(Vector2(520, 0), Vector2(470, 720), Kit.GOLD, 2.0, true)
	canvas.draw_line(Vector2(530, 0), Vector2(480, 720), Color(Kit.CRIMSON, 0.7), 1.0, true)
	Kit.diamond(canvas, Vector2(62, 62), 3.5, Kit.CRIMSON)
	Kit.tracked(canvas, catalog.numeric_font, "PAUSED", Vector2(74, 67), 13, Kit.GOLD, 4.0)
	Kit.text(canvas, catalog.display_font, "暂停", Vector2(54, 150), 76, Kit.PAPER, 6)
	var model = app.combat
	var info := "修炼模式" if model.practice else "第%s回合  ·  比分 %d : %d" % [Kit.numeral(model.round_number), model.wins[0], model.wins[1]]
	Kit.text(canvas, catalog.title_font, info, Vector2(58, 186), 16, Kit.GOLD_HI, 3)
	Kit.rule_out(canvas, Vector2(56, 200), Vector2(440, 200), Kit.GOLD, 1.5)
	# Quick reference for P1's specials on the right.
	var definition = model.catalog.characters.get(app.characters[0])
	if definition == null:
		return
	var card := Rect2(574, 118, 650, 460)
	var shape := Kit.chamfer(card, 18, 5)
	Kit.gradient_fill(canvas, shape, Color(Kit.INK_700, 0.9), Color(Kit.INK_900, 0.92))
	Kit.frame(canvas, shape, Kit.GOLD, 0.9, 2.0, 1.0)
	Kit.tracked(canvas, catalog.numeric_font, "COMMAND LIST", Vector2(card.position.x + 28, card.position.y + 34), 12, Kit.GOLD, 3.0)
	Kit.text(canvas, catalog.display_font, catalog.characters[app.characters[0]].display_name + " · 招式速查", Vector2(card.position.x + 26, card.position.y + 72), 30, Kit.PAPER, 4)
	Kit.rule_out(canvas, card.position + Vector2(24, 88), card.position + Vector2(card.size.x - 24, 88), Color(Kit.GOLD, 0.7))
	# Five rows fill the card; a longer list (air specials) tightens the pitch.
	var count: int = definition.move_list.size()
	var pitch := 64.0 if count <= 5 else 300.0 / (count - 1)
	for i in range(count):
		var row: Dictionary = definition.move_list[i]
		var y := card.position.y + 126 + i * pitch
		Glyphs.paint(canvas, catalog.numeric_font, row.input, Vector2(card.position.x + 28, y), 22 if count <= 5 else 20)
		var size := Kit.fitted(catalog.title_font, row.name, 18 if count <= 5 else 17, 330)
		Kit.text(canvas, catalog.title_font, row.name, Vector2(card.position.x + 290, y + 2), size, Kit.PAPER, 3)
		Kit.text(canvas, catalog.body_font, row.description, Vector2(card.position.x + 290, y + (24 if count <= 5 else 21)), 13, Kit.MUTED, 2)
		if i < count - 1:
			var rule_y := y + (38.0 if count <= 5 else pitch * 0.68)
			Kit.rule(canvas, Vector2(card.position.x + 24, rule_y), Vector2(card.end.x - 24, rule_y), Color(Kit.GOLD, 0.2))

# --- Result -------------------------------------------------------------------------------

func result() -> void:
	var winner: int = app.combat.match_winner
	var visual = catalog.characters[app.characters[winner]]
	_backdrop(visual.accent.darkened(0.35), Color("5c1222"), 0.7)
	var slash := Brush.new(3.3)
	slash.configure(Rect2(-60, 250, 820, 230), Color(Kit.CRIMSON, 0.55), 60.0)
	add_child(slash)
	portrait(visual.character_id, Rect2(70, 12, 560, 700), true, true)
	texture(shades.right, Rect2(560, 0, 720, 720))
	texture(shades.bottom, Rect2(0, 600, 1280, 120))
	var big := GradientText.new()
	big.setup(catalog.display_font, "胜", 240)
	big.position = Vector2(1146, 296)
	big.outline = 12
	big.glow_size = 30
	big.glow_color = Color(Kit.GOLD, 0.18)
	big.set_glint(0.35)
	add_child(big)
	var name_size := Kit.fitted(catalog.display_font, visual.display_name, 64, 330)
	paint(Rect2(0, 0, 1280, 720), func(canvas: Control):
		Kit.diamond(canvas, Vector2(690, 124), 4, Kit.CRIMSON)
		Kit.tracked(canvas, catalog.numeric_font, "VICTORY", Vector2(704, 130), 18, Kit.GOLD, 8.0)
		Kit.rule_out(canvas, Vector2(686, 150), Vector2(1000, 150), Kit.GOLD, 1.5)
		var chip := Rect2(686, 372, 112, 30)
		canvas.draw_colored_polygon(Kit.slant(chip, 8), Kit.player_color(winner))
		Kit.text_aligned(canvas, catalog.numeric_font, "P%d WINS" % [winner + 1], Vector2(chip.get_center().x, chip.end.y - 8), 17, Kit.INK_900, 1)
		var score := "%d  :  %d" % [app.combat.wins[0], app.combat.wins[1]]
		var score_width := Kit.width(catalog.numeric_font, score, 54)
		Kit.text_aligned(canvas, catalog.numeric_font, score, Vector2(1204, 410), 54, Kit.GOLD_HI, 2, 6)
		Kit.text_aligned(canvas, catalog.numeric_font, "P1", Vector2(1196 - score_width, 392), 14, Kit.P1, 2, 3)
		Kit.text_aligned(canvas, catalog.numeric_font, "P2", Vector2(1212, 392), 14, Kit.P2, 0, 3)
		Kit.rule_out(canvas, Vector2(686, 432), Vector2(1204, 432), Color(Kit.GOLD, 0.5)))
	label(visual.display_name, Rect2(684, 160, 350, 90), name_size, PAPER, false, HORIZONTAL_ALIGNMENT_LEFT, "display")
	label(visual.epithet, Rect2(688, 252, 340, 34), 21, Kit.GOLD_HI, true)
	label(visual.element_name, Rect2(688, 296, 340, 30), 16, visual.accent.lightened(0.3), true)
	var replay := button("replay", "再来一场", Rect2(684, 470, 520, 62), app.start_match, true, true, 26)
	replay.subtitle = "REMATCH"
	replay.grab_focus()
	button("setup", "返回选人", Rect2(684, 548, 254, 46), app.show_setup, false, false, 18)
	button("home", "返回主菜单", Rect2(950, 548, 254, 46), app.show_title, false, false, 18)
	label("月色如初，再决胜负。", Rect2(688, 612, 520, 40), 26, Color(PAPER, 0.85), false, HORIZONTAL_ALIGNMENT_LEFT, "display")
	_footer(Rect2(684, 668, 556, 36), "")
	result_sparks = Node2D.new()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	result_sparks.material = additive
	result_sparks.draw.connect(_draw_result_sparks)
	add_child(result_sparks)
	reveal()

func _draw_result_sparks() -> void:
	# Gold leaf bursts out of the victory mark, then drifts down.
	for i in range(46):
		var angle := i * 2.399
		var speed := 120.0 + (i % 7) * 34.0
		var t := clampf(result_spark_time - (i % 5) * 0.05, 0, 2.4)
		var at := Vector2(1146, 210) + Vector2(cos(angle), sin(angle) * 0.7) * speed * Kit.ease_out(t / 1.1)
		at.y += t * t * 22.0
		var alpha := clampf(1.0 - t / 2.4, 0, 1) * 0.85
		var spin := t * 5.0 + i
		var size := 3.0 + (i % 4)
		var leaf := PackedVector2Array([at + Vector2(cos(spin), sin(spin)) * size, at + Vector2(cos(spin + 1.9), sin(spin + 1.9)) * size * 0.45,
			at + Vector2(cos(spin + PI), sin(spin + PI)) * size, at + Vector2(cos(spin + 4.4), sin(spin + 4.4)) * size * 0.45])
		result_sparks.draw_colored_polygon(leaf, Color(Kit.GOLD_HI if i % 3 else Kit.GOLD, alpha))

# --- Help -------------------------------------------------------------------------------------

func help(page: String = "basics", character_id: String = "") -> void:
	_backdrop(Color("1d3e52"), Color("3d1d2c"), 0.45)
	_header("操作指南", "HOW TO PLAY")
	var home := button("home", "返回对战" if app.help_return == "battle" else "返回主菜单", Rect2(40, 664, 230, 44), app.close_help, true, true, 18)
	# Weakest to strongest: basics, normals, command normals and target combos, then
	# specials (ground and air), supers and MAX.
	var tabs := [["guide_basics", "基础攻防", "basics", Rect2(56, 104, 170, 40)], ["guide_normals", "普通技", "normals", Rect2(236, 104, 150, 40)],
		["guide_specials", "特殊技·派生", "specials", Rect2(396, 104, 200, 40)], ["guide_moves", "必杀与奥义", "moves", Rect2(606, 104, 190, 40)]]
	if character_id.is_empty():
		character_id = app.characters[0]
	for entry in tabs:
		var target: String = entry[2]
		var node := button(entry[0], entry[1], entry[3], func(): _help_page(target, character_id if target != "basics" else ""), false, false, 18)
		node.tab = true
		node.selected = page == target
	if page == "basics":
		paint(Rect2(40, 160, 1200, 490), _draw_basics)
	else:
		var definition = app.combat.catalog.characters[character_id]
		var selector := device_option("guide_character", Rect2(880, 102, 352, 42))
		var ids: Array = app.combat.catalog.characters.keys()
		for id in ids:
			selector.add_item(app.combat.catalog.characters[id].display_name)
		selector.select(ids.find(character_id))
		selector.item_selected.connect(func(index: int): _help_page(page, ids[index]))
		if page == "moves":
			paint(Rect2(40, 160, 1200, 490), func(canvas: Control): _draw_moves(canvas, definition))
		elif page == "specials":
			paint(Rect2(40, 160, 1200, 490), func(canvas: Control): _draw_specials(canvas, definition))
		else:
			paint(Rect2(40, 160, 1200, 490), func(canvas: Control): _draw_normals(canvas, definition))
	_footer(Rect2(300, 668, 932, 36), "返回", "F1 判定框 · F2 静音")
	home.grab_focus()
	reveal()

func _help_page(page: String, id: String = "") -> void:
	clear()
	help(page, id)

func _section(canvas: Control, rect: Rect2, numeral: String, heading: String, accent: Color = Kit.GOLD_HI) -> void:
	var shape := Kit.chamfer(rect, 16, 5)
	Kit.gradient_fill(canvas, shape, Color(Kit.INK_700, 0.88), Color(Kit.INK_900, 0.92))
	Kit.frame(canvas, shape, Kit.GOLD, 0.85, 2.0, 1.0)
	Kit.seal(canvas, Rect2(rect.position + Vector2(20, 18), Vector2(34, 34)), catalog.display_font, numeral)
	Kit.text(canvas, catalog.title_font, heading, rect.position + Vector2(66, 44), 22, accent, 3)
	Kit.rule_out(canvas, rect.position + Vector2(20, 64), rect.position + Vector2(rect.size.x - 20, 64), Color(Kit.GOLD, 0.6))

func _draw_basics(canvas: Control) -> void:
	var router = app.router
	var keys1: Array = router.current_keys(0)
	var keys2: Array = router.current_keys(1)
	var font: Font = catalog.body_font
	_section(canvas, Rect2(0, 0, 580, 490), "壹", "按键与移动", Color("8fdde6"))
	Kit.text_aligned(canvas, catalog.title_font, "键盘 P1", Vector2(306, 96), 15, Kit.P1, 1, 3)
	Kit.text_aligned(canvas, catalog.title_font, "键盘 P2", Vector2(466, 96), 15, Kit.P2, 1, 3)
	var rows := [["移动 / 跳跃", router.movement_hint(0), router.movement_hint(1)]]
	for index in range(4):
		rows.append([["A 轻攻击", "B 轻体术", "C 重攻击", "D 重体术"][index], router.key_name(keys1[index + 4]), router.key_name(keys2[index + 4])])
	for i in range(rows.size()):
		var y := 128.0 + i * 46
		if i % 2 == 0:
			canvas.draw_rect(Rect2(16, y - 20, 548, 40), Color(Kit.INK_600, 0.35))
		Kit.text(canvas, catalog.title_font, rows[i][0], Vector2(30, y + 6), 17, Kit.PAPER, 3)
		for column in range(2):
			var value: String = rows[i][column + 1]
			var center := 306.0 + column * 160
			Kit.keycap(canvas, font, value, Vector2(center - Kit.keycap_width(font, value, 26) * 0.5, y), 26)
	var y2 := 370.0
	Kit.text(canvas, font, "觉醒 B+C：P1 %s+%s / P2 %s+%s" % [router.key_name(keys1[5]), router.key_name(keys1[6]), router.key_name(keys2[5]), router.key_name(keys2[6])], Vector2(30, y2), 16, Kit.GOLD_HI, 3)
	Kit.text(canvas, font, "手柄 X/A/Y/B 对应 A/B/C/D；觉醒 A+Y", Vector2(30, y2 + 30), 15, Kit.MUTED, 3)
	Kit.text(canvas, font, "236 = ↓↘→；214 = ↓↙←，朝左时镜像。", Vector2(30, y2 + 62), 15, Kit.PAPER_DIM, 3)
	Kit.text(canvas, font, "双击前后可短冲刺；按键可在游戏设置中修改。", Vector2(30, y2 + 90), 15, Kit.PAPER_DIM, 3)
	_section(canvas, Rect2(600, 0, 600, 490), "贰", "攻防与资源")
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
		var y := 106.0 + i * 47
		Kit.diamond(canvas, Vector2(626, y - 6), 4, Kit.CRIMSON if i % 2 == 0 else Kit.GOLD)
		var size := Kit.fitted(font, lessons[i], 17, 540)
		Kit.text(canvas, font, lessons[i], Vector2(642, y), size, Kit.PAPER, 3)
		if i < lessons.size() - 1:
			Kit.rule(canvas, Vector2(620, y + 18), Vector2(1180, y + 18), Color(Kit.GOLD, 0.16))

## Specials (ground and air), supers and MAX, then the awakening.
func _draw_moves(canvas: Control, definition: Resource) -> void:
	var accent: Color = definition.accent
	_section(canvas, Rect2(0, 0, 1200, 490), "伍", definition.display_name + " · 必杀与奥义", accent.lightened(0.3))
	var count: int = definition.move_list.size()
	var compact := count > 5
	var pitch := 276.0 / (count - 1) if compact else 54.0
	for i in range(count):
		var row: Dictionary = definition.move_list[i]
		var y := 100.0 + i * pitch
		Glyphs.paint(canvas, catalog.numeric_font, row.input, Vector2(26, y), 22 if compact else 24)
		var description: String = row.description
		var input: String = row.input
		if input.begins_with("236236"):
			description += "；觉醒中耗1格，并耗尽觉醒" if input.contains("A+C") else "；觉醒中伤害110%，耗1格，保留觉醒"
		Kit.text(canvas, catalog.title_font, row.name, Vector2(330, y), 18 if compact else 20, Kit.PAPER, 3)
		Kit.text(canvas, catalog.body_font, description, Vector2(332, y + (20 if compact else 22)), 13 if compact else 14, Kit.MUTED, 2)
		var rule_y := y + (pitch * 0.7 if compact else 34.0)
		Kit.rule(canvas, Vector2(20, rule_y), Vector2(1180, rule_y), Color(Kit.GOLD, 0.16))
	var awakening: Resource = definition.awakening
	var top := 100.0 + (count - 1) * pitch + 52.0
	Kit.seal(canvas, Rect2(24, top, 26, 26), catalog.display_font, "醒", Kit.CRIMSON)
	Kit.text(canvas, catalog.title_font, "B+C · " + awakening.display_name + " · 2格 / 普通10秒、快速6秒", Vector2(60, top + 20), 16, awakening.color.lightened(0.2), 3)
	Kit.text(canvas, catalog.body_font, awakening.effect_summary(), Vector2(60, top + 44), 14, Kit.MUTED, 2)

## Command normals and target combos, then sample combos.
func _draw_specials(canvas: Control, definition: Resource) -> void:
	var accent: Color = definition.accent
	_section(canvas, Rect2(0, 0, 1200, 490), "肆", definition.display_name + " · 特殊技与派生", accent.lightened(0.3))
	var rows := mini(5, definition.advanced_list.size())
	if rows == 0:
		Kit.text(canvas, catalog.body_font, "该角色的特殊技与派生连续技将在后续版本加入。", Vector2(26, 110), 17, Kit.MUTED, 2)
	for i in range(rows):
		var row: Dictionary = definition.advanced_list[i]
		var y := 100.0 + i * 54
		Glyphs.paint(canvas, catalog.numeric_font, row.input, Vector2(26, y), 22)
		Kit.text(canvas, catalog.title_font, row.name, Vector2(330, y), 20, Kit.PAPER, 3)
		Kit.text(canvas, catalog.body_font, row.description, Vector2(332, y + 22), 14, Kit.MUTED, 2)
		Kit.rule(canvas, Vector2(20, y + 34), Vector2(1180, y + 34), Color(Kit.GOLD, 0.16))
	var top := 100.0 + maxi(rows, 1) * 54 + 30.0
	Kit.text(canvas, catalog.title_font, "示例连段 / j. 为空中，5 为站立，2 为蹲下", Vector2(26, top), 15, Kit.GOLD_HI, 3)
	for i in range(definition.combos.size()):
		Kit.text(canvas, catalog.body_font, definition.combos[i], Vector2(26 + (i % 2) * 590, top + 28 + int(i / 2) * 26), 15, Kit.PAPER, 2)

func _draw_normals(canvas: Control, definition: Resource) -> void:
	var accent: Color = definition.accent
	_section(canvas, Rect2(0, 0, 1200, 490), "叁", definition.display_name + " · 普通技", accent.lightened(0.3))
	var keys: Array = definition.normals.keys()
	for i in range(keys.size()):
		var move: Resource = definition.normals[keys[i]]
		var x := 22.0 + int(i / 6) * 590
		var y := 82.0 + (i % 6) * 66
		var cell := Rect2(x, y, 566, 58)
		canvas.draw_colored_polygon(Kit.chamfer(cell, 8, 6), Color(Kit.INK_600, 0.4))
		Kit.seal(canvas, Rect2(x + 10, y + 9, 40, 40), catalog.numeric_font, keys[i], Kit.INK_900, accent.lightened(0.35))
		Kit.text(canvas, catalog.title_font, move.display_name, Vector2(x + 64, y + 26), 18, Kit.PAPER, 3)
		var guard := "站防" if move.level == "high" else ("蹲防" if move.level == "low" else "站蹲均可防")
		var chips := ["起手 %d 帧" % move.startup, "伤害 %d" % move.damage, guard]
		if move.knockdown:
			chips.append("扫倒终结")
		var cx := x + 64
		for chip_text: String in chips:
			var w := Kit.width(catalog.body_font, chip_text, 12) + 14
			var chip := Rect2(cx, y + 34, w, 18)
			canvas.draw_colored_polygon(Kit.slant(chip, 4), Color(Kit.INK_900, 0.8))
			canvas.draw_polyline(Kit.closed(Kit.slant(chip, 4)), Color(Kit.GOLD, 0.35), 1.0, true)
			Kit.text_aligned(canvas, catalog.body_font, chip_text, Vector2(chip.get_center().x, chip.end.y - 4), 12, Kit.PAPER_DIM, 1)
			cx += w + 6

# --- Practice options ---------------------------------------------------------------------

func training_options() -> void:
	battle_style = false
	_pause_veil()
	paint(Rect2(316, 92, 648, 536), func(canvas: Control):
		var rect := Rect2(Vector2.ZERO, canvas.size)
		var shape := Kit.chamfer(rect, 22, 5)
		Kit.gradient_fill(canvas, shape, Color(Kit.INK_700, 0.95), Color(Kit.INK_900, 0.97))
		Kit.frame(canvas, shape, Kit.GOLD, 1.0, 3.0, 1.4)
		Kit.brackets(canvas, rect.grow(-8), 14, Color(Kit.GOLD_HI, 0.6), 1.5)
		Kit.diamond(canvas, Vector2(40, 40), 3.5, Kit.CRIMSON)
		Kit.tracked(canvas, catalog.numeric_font, "TRAINING OPTIONS", Vector2(52, 45), 12, Kit.GOLD, 3.5)
		Kit.text(canvas, catalog.display_font, "练习设置", Vector2(36, 104), 50, Kit.PAPER, 6)
		Kit.rule_out(canvas, Vector2(36, 120), Vector2(600, 120), Kit.GOLD, 1.5))
	label("木桩防御", Rect2(356, 236, 156, 42), 19, Kit.GOLD_HI, true)
	var guard := device_option("practice_guard", Rect2(530, 236, 392, 44))
	for item in ["站立不防", "站立防御", "蹲下防御", "首击后防（检验真连）"]:
		guard.add_item(item)
	guard.select(app.practice_controller.guard_mode)
	guard.item_selected.connect(func(index: int): app.practice_controller.guard_mode = index; app.practice_controller.first_hit = false)
	label("呼吸槽", Rect2(356, 296, 156, 42), 19, Kit.GOLD_HI, true)
	var meter := device_option("practice_meter", Rect2(530, 296, 392, 44))
	for item in [["0 格", 0], ["1 格", 1], ["2 格", 4], ["3 格", 2], ["无限气", 3]]:
		meter.add_item(item[0], item[1])
	meter.select(meter.get_item_index(app.practice_controller.meter_mode))
	meter.item_selected.connect(func(index: int): app.practice_controller.meter_mode = meter.get_item_id(index); app.practice_controller.apply_meter(app.combat))
	var details := CheckButton.new()
	details.text = "展开输入指导与搓招提示"
	details.position = Vector2(350, 356)
	details.size = Vector2(574, 44)
	details.button_pressed = app.view.hud.practice_details
	details.toggled.connect(func(value: bool): app.view.hud.practice_details = value)
	add_child(details)
	actions["practice_details"] = details
	var awakening := CheckButton.new()
	awakening.text = "觉醒时间无限（仍需 B+C 发动）"
	awakening.position = Vector2(350, 404)
	awakening.size = Vector2(574, 44)
	awakening.button_pressed = app.practice_controller.awakening_infinite
	awakening.toggled.connect(func(value: bool): app.practice_controller.awakening_infinite = value; app.combat.awakening_infinite = value)
	add_child(awakening)
	actions["practice_awakening"] = awakening
	label("连段结束后自动补血；Backspace 重置并解除觉醒。", Rect2(358, 462, 564, 30), 15, MUTED)
	var resume := button("resume", "继续练习", Rect2(356, 520, 278, 54), func(): app.set_paused(false), true, true, 21)
	resume.subtitle = "RESUME"
	resume.grab_focus()
	button("practice_reset", "重置位置", Rect2(646, 520, 278, 54), func(): app.reset_practice(); app.set_paused(false), false, false, 21).subtitle = "RESET"
	reveal()

# --- Builders -----------------------------------------------------------------------------

## Decorative custom-drawn control; `painter` receives the control to draw on.
func paint(bounds: Rect2, painter: Callable) -> Control:
	var node := Control.new()
	node.position = bounds.position
	node.size = bounds.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.focus_mode = Control.FOCUS_NONE
	node.draw.connect(func(): painter.call(node))
	add_child(node)
	return node

func prompt_label(bounds: Rect2) -> Label:
	var node := PromptLabel.new()
	node.position = bounds.position
	node.add_theme_font_override("font", catalog.body_font)
	add_child(node)
	node.size = bounds.size
	return node

func keycap(value: String, bounds: Rect2) -> void:
	paint(bounds, func(canvas: Control):
		Kit.keycap(canvas, catalog.body_font, value, Vector2(0, canvas.size.y * 0.5), canvas.size.y))

func label(value: String, bounds: Rect2, font_size: int = 18, color: Color = PAPER, serif: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT, kind: String = "") -> Label:
	var node := Label.new()
	node.text = value
	node.position = bounds.position
	var face: Font = catalog.display_font if kind == "display" else (catalog.title_font if serif else catalog.body_font)
	node.add_theme_font_override("font", face)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color(Kit.INK_900, 0.6))
	node.add_theme_constant_override("shadow_offset_y", 2)
	node.add_theme_color_override("font_outline_color", Color(Kit.INK_900, 0.85))
	node.add_theme_constant_override("outline_size", 6 if font_size >= 40 else (4 if font_size >= 20 else 3))
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
	node.caption_font = catalog.numeric_font
	node.seal_font = catalog.display_font
	node.add_theme_font_override("font", catalog.body_font if battle_style else catalog.title_font)
	node.add_theme_font_size_override("font_size", font_size)
	node.pressed.connect(callback)
	if not battle_style:
		node.focus_entered.connect(_focus_cue)
		if id in ["back", "home", "settings_back"]:
			node.pressed.connect(func(): app.sound.play("ui_back", 0.4))
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
	paint(Rect2(at - Vector2(0, 2), Vector2(length, 4)), func(canvas: Control):
		Kit.rule(canvas, Vector2(0, 2), Vector2(canvas.size.x, 2), color))

func slash(bounds: Rect2, color: Color, cut: float = 40) -> void:
	var stroke := Brush.new(bounds.position.x * 0.013)
	stroke.configure(bounds, color, cut * 0.5)
	add_child(stroke)

func panel(bounds: Rect2) -> void:
	paint(bounds, func(canvas: Control):
		var area := Rect2(Vector2.ZERO, canvas.size)
		var shape := Kit.chamfer(area, 16, 5)
		Kit.gradient_fill(canvas, shape, Color(Kit.INK_700, 0.9), Color(Kit.INK_900, 0.93))
		Kit.frame(canvas, shape, Kit.GOLD, 0.85, 2.0, 1.0)
		Kit.brackets(canvas, area.grow(-6), 12, Color(Kit.GOLD_HI, 0.45), 1.2))

func device_option(id: String, bounds: Rect2) -> OptionButton:
	var node := OptionButton.new()
	node.name = id
	node.position = bounds.position
	node.clip_text = true
	node.add_theme_font_size_override("font_size", 18)
	node.focus_entered.connect(_focus_cue)
	add_child(node)
	node.size = bounds.size
	actions[id] = node
	return node
