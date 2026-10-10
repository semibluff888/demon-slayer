extends Node2D
const Combat = preload("res://scripts/combat.gd")
const InputRouter = preload("res://scripts/input_router.gd")
const AI = preload("res://scripts/ai_controller.gd")
const Practice = preload("res://scripts/practice_controller.gd")
const World = preload("res://scripts/world_view.gd")
const Sound = preload("res://scripts/audio.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Selection = preload("res://scripts/ui/selection_controller.gd")
const Menu = preload("res://scripts/ui/menu_view.gd")
const Settings = preload("res://scripts/game_settings.gd")
var settings := Settings.new()
var settings_return: String = "title"
var combat := Combat.new()
var router := InputRouter.new()
var ai := AI.new()
var practice_controller := Practice.new()
var catalog := Catalog.new(false)
var selection := Selection.new()
var stage_id: String = "wisteria"
var view: Node2D
var sound: Node
var gui: Control
var screen: String = "title"
var mode: String = "cpu"
var menu_device: String = "keyboard:0"
var characters: Array[String] = []
var devices: Array[String] = ["keyboard:0", "keyboard:1"]
var paused: bool = false
var device_notice: Label
var start_button: Button
var setup_options: Array[OptionButton] = []
var pause_reason: String = ""
var help_return: String = "title"

func _ready() -> void:
	settings.load_config()
	router.apply_keymaps(settings.keymaps)
	selection.app = self
	var ids: Array = catalog.characters.keys()
	characters.assign([ids[0], ids[mini(1, ids.size() - 1)]])
	view = World.new()
	view.combat = combat
	view.catalog = catalog
	add_child(view)
	view.cinematic.app = self
	sound = Sound.new()
	add_child(sound)
	sound.set_levels(settings.muted,settings.volume)
	gui = Menu.new()
	gui.z_index = 60
	gui.app = self
	gui.catalog = catalog
	add_child(gui)
	Input.joy_connection_changed.connect(_on_joy_connection)
	show_title()
	if OS.get_cmdline_user_args().has("--verify-release"):
		preload("res://scripts/release_verifier.gd").run.call_deferred(self)

func _physics_process(_delta: float) -> void:
	if screen != "battle" or paused or view.cinematic.blocks_combat():
		return
	var commands: Array = [router.read(0, devices[0]), Combat.neutral()]
	if mode == "cpu":
		commands[1] = ai.command(combat.fighters[1].observable(), combat.fighters[0].observable())
	elif mode == "practice":
		commands[1] = practice_controller.command(combat)
	else:
		commands[1] = router.read(1, devices[1])
	var previous_phase := combat.phase
	combat.cinematic_moves = view.cinematic.available_moves() if settings.cinematic_enabled else {}
	combat.step(commands)
	if not combat.cinematic.is_empty() and not view.cinematic.active:
		if mode == "practice":
			practice_controller.after_step(combat)
		view.hud.consume(combat.events)
		view.cinematic.begin()
		_reset_inputs()
		return
	if mode == "practice":
		practice_controller.after_step(combat)
	view.consume(combat.events)
	sound.consume(combat.events,combat)
	if previous_phase == "round_end" and combat.phase == "intro":
		ai.reset()
		router.reset(devices)
		view.reset_effects()
		sound.reset_audio()
	if combat.phase == "match_end":
		show_result()

func _input(event: InputEvent) -> void:
	if screen == "settings" and gui.settings_panel != null and gui.settings_panel.handle(event):
		get_viewport().set_input_as_handled()
		return
	if screen == "title":
		if event is InputEventJoypadButton and event.pressed:
			menu_device = "pad:%d" % event.device
		elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
			menu_device = "keyboard:0"
	if _menu_keyboard(event):
		get_viewport().set_input_as_handled()
		return
	if selection.handle(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back_or_pause()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			view.debug_boxes = not view.debug_boxes
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			toggle_audio()
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
	if screen == "settings":
		close_settings()
		return
	if screen == "setup":
		selection.cancel(selection.active_slot)
		return
	if screen == "stage":
		show_setup()
		return
	if screen == "battle":
		if paused and not _devices_ready():
			return
		set_paused(not paused)
	elif screen == "help":
		close_help()
	elif screen in ["setup", "result"]:
		show_title()

func _change_screen(next_screen: String) -> void:
	if next_screen in ["title", "setup", "stage", "result"]:
		view.cinematic.cancel()
	gui.visible = true
	screen = next_screen
	view.screen = next_screen
	view.characters = characters
	view.paused = paused
	sound.set_paused(paused)
	if next_screen in ["title","setup","stage","result"]:
		sound.reset_audio()
	gui.clear()

func show_title() -> void:
	selection.reset()
	paused = false
	_change_screen("title")
	gui.title()

func choose_mode(selected: String) -> void:
	mode = selected
	if menu_device.begins_with("pad:") and router.connected(menu_device):
		devices[0] = menu_device
		if mode == "local":
			devices[1] = "keyboard:1"
			for candidate in router.available_devices():
				if candidate.id.begins_with("pad:") and candidate.id != menu_device:
					devices[1] = candidate.id
					break
	sound.play("select")
	show_setup()

func select_character(player: int, id: String) -> void:
	selection.choose(player, id)

func show_setup() -> void:
	paused = false
	selection.reset()
	_change_screen("setup")
	gui.setup()

func show_stages() -> void:
	_change_screen("stage")
	gui.stages()

func _validate_setup() -> void:
	if screen not in ["setup", "stage"] or not is_instance_valid(start_button):
		return
	var duplicate := mode == "local" and devices[0] == devices[1]
	start_button.disabled = duplicate or not _devices_ready()
	if is_instance_valid(device_notice):
		device_notice.text = "请选择不同设备" if duplicate else ("请连接操作设备" if not _devices_ready() else "")
		if device_notice.text.is_empty() and not selection.modal:
			var first: String = router.selection_hint(devices[0])
			device_notice.text = first if mode != "local" or screen == "stage" else "P1 " + first + "    P2 " + router.selection_hint(devices[1])
		device_notice.modulate = Color("ff8197") if start_button.disabled else Color.WHITE

func start_match() -> void:
	if not _devices_ready() or (mode == "local" and devices[0] == devices[1]):
		return
	selection.modal = false
	view.reset_effects()
	catalog.prepare_match(characters, stage_id)
	view.cinematic.prepare(characters)
	view.set_stage(stage_id)
	combat.practice = mode == "practice"
	combat.new_match(characters[0], characters[1])
	ai.reset()
	router.reset(devices)
	if mode == "practice":
		practice_controller.reset(combat)
	view.reset_effects()
	sound.reset_audio()
	view.cpu = mode == "cpu"
	view.hud.training = practice_controller if mode == "practice" else null
	view.hud.input_device = devices[0]
	view.input_hints.assign([_device_hint(devices[0]), _device_hint(devices[1])])
	_refresh_awakening_hints()
	paused = false
	_change_screen("battle")
	gui.battle()
	sound.play("select")

func _device_hint(device: String) -> String:
	return router.device_hint(device)

func refresh_input_hints() -> void:
	_refresh_awakening_hints()
	view.input_hints.assign([_device_hint(devices[0]),_device_hint(devices[1])])
	view.hud.input_device=devices[0]

func _menu_keyboard(event: InputEvent) -> bool:
	if event is not InputEventKey or not (screen in ["title","help","settings","result"] or (screen=="battle" and paused)):
		return false
	var key: int=event.physical_keycode if event.physical_keycode else event.keycode
	for player in range(2):
		var index:=router.current_keys(player).find(key)
		if index not in [0,1,2,3,4,5]:continue
		var action:=InputEventAction.new()
		action.action=["ui_left","ui_right","ui_down","ui_up","ui_accept","ui_cancel"][index]
		action.pressed=event.pressed
		get_viewport().push_input(action)
		return true
	return false

func toggle_audio() -> void:
	sound.toggle()
	settings.muted=sound.muted
	view.cinematic.sync_audio()
	settings.save_config()
	if screen=="settings":gui.actions.audio_mute.set_pressed_no_signal(settings.muted)

func show_settings() -> void:
	settings_return="battle" if screen=="battle" else "title"
	if settings_return=="battle":
		paused=true
		_reset_inputs()
	_change_screen("settings")
	gui.settings()

func close_settings() -> void:
	_reset_inputs()
	if settings_return=="battle":
		_change_screen("battle")
		set_paused(true,"" if _devices_ready() else "请重连手柄，或在游戏设置中切换为键盘。")
	else:show_title()

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
	sound.set_paused(value)
	_reset_inputs()
	pause_reason = reason
	gui.clear()
	gui.visible = value or not view.cinematic.is_video_visible()
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
	sound.reset_audio()

func _devices_ready() -> bool:
	return router.connected(devices[0]) and (mode != "local" or router.connected(devices[1]))

func _on_joy_connection(_device: int, _connected: bool) -> void:
	if screen == "settings":
		gui.settings_panel.refresh_controllers()
		return
	if screen in ["setup", "stage"]:
		if not _devices_ready():
			selection.ready.assign([false, false])
			if screen == "stage": show_setup()
		if screen == "setup": gui.refresh_setup()
		_validate_setup()
	elif screen == "battle":
		if not _devices_ready():
			set_paused(true, "手柄已断开，请重新连接；\n也可在游戏设置中切换为键盘。")
		elif paused:
			set_paused(true, "设备已连接，可以继续对战。")

func _refresh_awakening_hints() -> void:
	for slot in range(2):
		if str(devices[slot]).begins_with("keyboard"):
			var keyboard := int(str(devices[slot]).get_slice(":", 1))
			var keys: Array = router.current_keys(keyboard)
			view.hud.awakening_hints[slot] = router.key_name(keys[5]) + "+" + router.key_name(keys[6])
		else:
			view.hud.awakening_hints[slot] = "A+Y"
