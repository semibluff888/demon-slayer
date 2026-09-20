extends Node2D
const Combat = preload("res://scripts/combat.gd")
const InputRouter = preload("res://scripts/input_router.gd")
const AI = preload("res://scripts/ai_controller.gd")
const Practice = preload("res://scripts/practice_controller.gd")
const World = preload("res://scripts/world_view.gd")
const Sound = preload("res://scripts/audio.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Menu = preload("res://scripts/ui/menu_view.gd")
var combat := Combat.new()
var router := InputRouter.new()
var ai := AI.new()
var practice_controller := Practice.new()
var catalog := Catalog.new()
var view: Node2D
var sound: Node
var gui: Control
var screen: String = "title"
var mode: String = "cpu"
var characters: Array[String] = []
var devices: Array[String] = ["keyboard:0", "keyboard:1"]
var paused: bool = false
var device_notice: Label
var start_button: Button
var setup_options: Array[OptionButton] = []
var pause_reason: String = ""
var help_return: String = "title"

func _ready() -> void:
	var ids: Array = catalog.characters.keys()
	characters.assign([ids[0], ids[mini(1, ids.size() - 1)]])
	view = World.new()
	view.combat = combat
	view.catalog = catalog
	add_child(view)
	sound = Sound.new()
	add_child(sound)
	gui = Menu.new()
	gui.z_index = 60
	gui.app = self
	gui.catalog = catalog
	add_child(gui)
	Input.joy_connection_changed.connect(_on_joy_connection)
	show_title()

func _physics_process(_delta: float) -> void:
	if screen != "battle" or paused:
		return
	var commands: Array = [router.read(0, devices[0]), Combat.neutral()]
	if mode == "cpu":
		commands[1] = ai.command(combat.fighters[1].observable(), combat.fighters[0].observable())
	elif mode == "practice":
		commands[1] = practice_controller.command(combat)
	else:
		commands[1] = router.read(1, devices[1])
	var previous_phase := combat.phase
	combat.step(commands)
	if mode == "practice":
		practice_controller.after_step(combat)
	view.consume(combat.events)
	for event in combat.events:
		sound.play(event.type)
		if event.type == "swing":
			sound.play(event.get("effect", ""))
	if previous_phase == "round_end" and combat.phase == "intro":
		ai.reset()
		router.reset(devices)
		view.reset_effects()
	if combat.phase == "match_end":
		show_result()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			view.debug_boxes = not view.debug_boxes
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			sound.toggle()
			if screen == "title":
				show_title()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3 and screen == "battle" and mode == "practice":
			show_practice_options()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BACKSPACE and screen == "battle" and mode == "practice" and not paused:
			reset_practice()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_back_or_pause()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		_back_or_pause()
		get_viewport().set_input_as_handled()

func _back_or_pause() -> void:
	if screen == "battle":
		if paused and not _devices_ready():
			return
		set_paused(not paused)
	elif screen == "help":
		close_help()
	elif screen in ["setup", "result"]:
		show_title()

func _change_screen(next_screen: String) -> void:
	screen = next_screen
	view.screen = next_screen
	view.characters = characters
	view.paused = paused
	gui.clear()

func show_title() -> void:
	paused = false
	_change_screen("title")
	gui.title()

func choose_mode(selected: String) -> void:
	mode = selected
	sound.play("select")
	show_setup()

func select_character(player: int, id: String) -> void:
	characters[player] = id
	sound.play("select")
	show_setup()
	gui.actions["p%d_%s" % [player + 1, id]].grab_focus()

func show_setup() -> void:
	paused = false
	_change_screen("setup")
	gui.setup()

func _validate_setup() -> void:
	if screen != "setup":
		return
	var duplicate := mode == "local" and devices[0] == devices[1]
	start_button.disabled = duplicate or not _devices_ready()
	device_notice.text = "两位玩家请选择不同的操作设备" if duplicate else (
		"自由练习 / F3 设置木桩与气槽 / Backspace 重置" if mode == "practice" else
		"60 秒 / 回合 · 先赢两局获胜\n手柄 X 轻斩 · A 轻体术 · Y 重斩 · B 重体术")

func start_match() -> void:
	if not _devices_ready() or (mode == "local" and devices[0] == devices[1]):
		return
	combat.practice = mode == "practice"
	combat.new_match(characters[0], characters[1])
	ai.reset()
	router.reset(devices)
	if mode == "practice":
		practice_controller.reset(combat)
	view.reset_effects()
	view.cpu = mode == "cpu"
	view.hud.training = practice_controller if mode == "practice" else null
	view.hud.input_device = devices[0]
	view.input_hints.assign([_device_hint(devices[0]), _device_hint(devices[1])])
	paused = false
	_change_screen("battle")
	gui.battle()
	sound.play("select")

func _device_hint(device: String) -> String:
	if device == "keyboard:0":
		return "WASD / FG · VB"
	if device == "keyboard:1":
		return "↑↓←→ / JK · NM"
	return "手柄 X A / Y B"

func _reset_inputs() -> void:
	var held: Array = [router.sample(devices[0]), router.sample(devices[1])]
	router.reset(devices)
	combat.clear_inputs(held)
	ai.queue.clear()

func set_paused(value: bool, reason: String = "") -> void:
	if screen != "battle":
		return
	if not value and not _devices_ready():
		return
	paused = value
	view.paused = value
	_reset_inputs()
	pause_reason = reason
	gui.clear()
	if not paused:
		gui.battle()
	else:
		gui.pause(reason)

func show_result() -> void:
	paused = false
	_change_screen("result")
	gui.result()

func show_help() -> void:
	help_return = "battle" if screen == "battle" else "title"
	if help_return == "battle":
		paused = true
		_reset_inputs()
	_change_screen("help")
	gui.help()

func close_help() -> void:
	if help_return == "battle":
		_change_screen("battle")
		set_paused(not _devices_ready(), "" if _devices_ready() else "请重新连接操作设备")
	else:
		show_title()

func show_practice_options() -> void:
	if mode != "practice" or screen != "battle":
		return
	set_paused(true)
	gui.clear()
	gui.training_options()

func reset_practice() -> void:
	practice_controller.reset(combat)
	_reset_inputs()
	view.reset_effects()

func _devices_ready() -> bool:
	return router.connected(devices[0]) and (mode != "local" or router.connected(devices[1]))

func _on_joy_connection(_device: int, _connected: bool) -> void:
	if screen == "setup":
		show_setup()
	elif screen == "battle":
		if not _devices_ready():
			set_paused(true, "手柄已断开，请重新连接；\n也可返回选人切换操作设备。")
		elif paused:
			set_paused(true, "设备已连接，可以继续对战。")
