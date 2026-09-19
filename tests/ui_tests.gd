extends SceneTree
const MainScene = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const AI = preload("res://scripts/ai_controller.gd")
var game: Node2D
var failures: Array[String] = []
var passed: int = 0
var capture: bool = false

class VirtualPadRouter extends "res://scripts/input_router.gd":
	var simulated: Dictionary = preload("res://scripts/combat.gd").neutral()
	var present: bool = true
	func connected(device: String) -> bool:
		return present if device == "pad:99" else super.connected(device)
	func sample(device: String) -> Dictionary:
		return simulated.duplicate() if device == "pad:99" else super.sample(device)
	func available_devices() -> Array[Dictionary]:
		var result := super.available_devices()
		if present:
			result.append({"id": "pad:99", "label": "模拟手柄（测试专用）"})
		return result

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(message)

func _run() -> void:
	create_timer(30).timeout.connect(func(): printerr("UI test watchdog expired"); quit(1))
	game = MainScene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	print("CONNECTED PHYSICAL GAMEPADS: ", Input.get_connected_joypads())
	await process_frame
	check(game.screen == "title", "boot reaches title")
	await _capture("01-title")
	_click("help")
	check(game.screen == "help", "guide button works")
	await _capture("02-controls")
	_click("home")
	_click("mode_cpu")
	check(game.screen == "setup" and game.mode == "cpu", "CPU button opens setup")
	await _capture("03-select")
	# Exercise the actual character card callback, including a mirror match.
	_click("p2_tanjiro")
	check(game.characters == ["tanjiro", "tanjiro"], "both slots can select the same character")
	_click("p2_zenitsu")
	_click("start")
	check(game.screen == "battle" and game.combat.phase == "intro", "start button begins ready sequence")
	var before: Dictionary = game.combat.snapshot()
	game.set_paused(true)
	for n in range(30):
		game._physics_process(1.0 / 60)
	check(game.combat.snapshot() == before, "pause freezes the entire combat state")
	await _capture("04-pause")
	_click("resume")
	for n in range(90):
		game._physics_process(1.0 / 60)
	check(game.combat.phase == "fight", "ready sequence ends after 90 ticks")
	# Render a real active water slash and contact; no hand-painted screenshot.
	game.combat.fighters[0].x = 268
	game.combat.fighters[1].x = 341
	Input.action_press("p1_skill")
	game._physics_process(1.0 / 60)
	Input.action_release("p1_skill")
	for n in range(10):
		game._physics_process(1.0 / 60)
	await _capture("05-fight")
	game.view.debug_boxes = true
	await _capture("06-hitboxes")
	game.view.debug_boxes = false
	# Full scene-level matches through the input router and real screen transitions.
	for selected_mode in ["cpu", "local", "virtual_pad"]:
		game.mode = "cpu" if selected_mode == "cpu" else "local"
		game.devices.assign(["keyboard:0", "keyboard:1"])
		if selected_mode == "virtual_pad":
			game.router = VirtualPadRouter.new()
			game.devices[1] = "pad:99"
		game.start_match()
		var human1 := AI.new(55)
		var human2 := AI.new(83)
		var steps := 0
		while game.screen == "battle" and steps < 40000:
			var a: Dictionary = human1.command(game.combat.fighters[0].observable(), game.combat.fighters[1].observable())
			_drive_keyboard(1, a)
			if selected_mode != "cpu":
				var b: Dictionary = human2.command(game.combat.fighters[1].observable(), game.combat.fighters[0].observable())
				if selected_mode == "virtual_pad":
					game.router.simulated = game.router.pad_held(float(b.x), -1.0 if b.jump else (1.0 if b.down else 0.0),
						{JOY_BUTTON_X: b.light, JOY_BUTTON_Y: b.heavy, JOY_BUTTON_A: b.skill, JOY_BUTTON_B: b.throw})
				else:
					_drive_keyboard(2, b)
			game._physics_process(1.0 / 60)
			game.view._process(1.0 / 60)
			steps += 1
		_drive_keyboard(1, Combat.neutral())
		_drive_keyboard(2, Combat.neutral())
		check(game.screen == "result" and game.combat.wins.max() == 2, "complete match reaches results: " + selected_mode)
		print("UI MATCH ", selected_mode, " -> ", game.combat.wins, " in ", steps, " ticks")
		if selected_mode == "cpu":
			await _capture("07-results")
		_click("replay")
		check(game.screen == "battle" and game.combat.wins == [0, 0] and game.combat.fighters[0].hp == 1000, "rematch button fully resets " + selected_mode)
	# Missing controller pauses automatically; reconnect leaves deliberate resume.
	game.router.present = false
	game._on_joy_connection(99, false)
	check(game.paused and not game._devices_ready(), "disconnect pauses a match")
	game.set_paused(false)
	check(game.paused, "cannot resume with a disconnected assigned controller")
	game.router.present = true
	game._on_joy_connection(99, true)
	check(game.paused and game._devices_ready(), "reconnect waits for manual resume")
	game.set_paused(false)
	check(not game.paused, "reconnected match can resume")
	game.show_setup()
	game.devices.assign(["keyboard:0", "keyboard:0"])
	game._validate_setup()
	check(game.start_button.disabled, "same device cannot control both players")
	game.devices.assign(["keyboard:0", "keyboard:1"])
	game._validate_setup()
	check(not game.start_button.disabled, "two keyboard groups are valid independent inputs")
	game.show_title()
	await _test_native_menu_input()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("UI TESTS: %d passed, %d failed" % [passed, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_native_menu_input() -> void:
	await process_frame
	check(game.gui.actions.mode_cpu.has_focus(), "title starts with a keyboard focus target")
	await _key(KEY_TAB)
	check(game.gui.actions.mode_local.has_focus(), "native Tab moves to local mode")
	await _key(KEY_ENTER)
	check(game.screen == "setup" and game.mode == "local", "native Enter activates the focused mode")
	game.show_title()
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(210, 458)
	motion.global_position = motion.position
	root.push_input(motion, true)
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = motion.position
	click.global_position = motion.position
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	check(game.screen == "setup" and game.mode == "cpu", "native mouse click activates CPU mode")
	game.show_title()
	await process_frame
	var pad := InputEventJoypadButton.new()
	pad.device = 99
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	root.push_input(pad, true)
	pad = pad.duplicate()
	pad.pressed = false
	root.push_input(pad, true)
	await process_frame
	check(game.gui.actions.mode_local.has_focus(), "native gamepad D-pad changes menu focus")
	game.show_title()

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _drive_keyboard(player: int, command: Dictionary) -> void:
	var values := command.duplicate()
	values.left = command.x < 0
	values.right = command.x > 0
	for action in ["left", "right", "down", "jump", "light", "heavy", "skill", "throw"]:
		var name := "p%d_%s" % [player, action]
		if values[action]:
			Input.action_press(name)
		else:
			Input.action_release(name)

func _click(text: String) -> void:
	for child in game.gui.get_children():
		if child is Button and child.name == text:
			child.pressed.emit()
			return
	check(false, "button exists: " + text)

func _capture(name: String) -> void:
	if capture:
		await create_timer(0.32).timeout
	await process_frame
	# Detect Controls whose font minimum size has expanded beyond the viewport.
	for child in game.gui.get_children():
		if child is Control:
			var bounds: Rect2 = child.get_rect()
			check(bounds.end.x <= 1281 and bounds.end.y <= 721, "control fits viewport in %s: %s bounds=%s" % [name, child.get("text"), bounds])
	if capture:
		await RenderingServer.frame_post_draw
		var path := "res://artifacts/%s.png" % name
		var result := root.get_texture().get_image().save_png(path)
		check(result == OK, "screenshot saved: " + name)

