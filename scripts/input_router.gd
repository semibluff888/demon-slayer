class_name DuelInput
extends RefCounted
## Device adapter only. Edge/motion/dash recognition belongs to the model.
const Commands = preload("res://scripts/command_recognizer.gd")
const ACTIONS: Array[String] = ["left", "right", "down", "up", "a", "b", "c", "d"]
const KEYS: Array = [
	[KEY_A, KEY_D, KEY_S, KEY_W, KEY_F, KEY_G, KEY_V, KEY_B],
	[KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_J, KEY_K, KEY_N, KEY_M]]
var stick_directions: Dictionary = {}
var suppressed: Dictionary = {}

func _init() -> void:
	for player in range(2):
		for n in range(ACTIONS.size()):
			var action := "p%d_%s" % [player + 1, ACTIONS[n]]
			if InputMap.has_action(action):
				continue
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = KEYS[player][n]
			InputMap.action_add_event(action, event)

static func motion_hints(device: String, facing: int) -> Array[String]:
	var left := "A" if device == "keyboard:0" else "←"
	var right := "D" if device == "keyboard:0" else "→"
	var down := "S" if device == "keyboard:0" else "↓"
	var slash := "F / V" if device == "keyboard:0" else ("J / N" if device == "keyboard:1" else "X / Y")
	var body := "G / B" if device == "keyboard:0" else ("K / M" if device == "keyboard:1" else "A / B")
	var forward := right if facing > 0 else left
	var back := left if facing > 0 else right
	return ["236：%s → %s + (%s)" % [down, forward, slash],
		"214：%s → %s + (%s)" % [down, back, body],
		"朝%s · 松开%s · 0.5秒完成，攻击可晚0.2秒" % ["右" if facing > 0 else "左", down]]

func available_devices() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id": "keyboard:0", "label": "键盘 1 · WASD / FG·VB"},
		{"id": "keyboard:1", "label": "键盘 2 · 方向键 / JK·NM"}]
	for id in Input.get_connected_joypads():
		result.append({"id": "pad:%d" % id, "label": "手柄 %d · %s" % [id + 1, Input.get_joy_name(id)]})
	return result

func connected(device: String) -> bool:
	return not device.begins_with("pad:") or int(device.get_slice(":", 1)) in Input.get_connected_joypads()

func sample(device: String) -> Dictionary:
	var held := {"x": 0, "y": 0, "buttons": 0}
	if device.begins_with("keyboard:"):
		var prefix := "p%d_" % (int(device.get_slice(":", 1)) + 1)
		var right := Input.is_action_pressed(prefix + "right")
		var left := Input.is_action_pressed(prefix + "left")
		held.x = int(right) - int(left)
		if right and left:
			held.direction_conflict = true
		held.y = int(Input.is_action_pressed(prefix + "down")) - int(Input.is_action_pressed(prefix + "up"))
		for n in range(4):
			if Input.is_action_pressed(prefix + ["a", "b", "c", "d"][n]):
				held.buttons = int(held.buttons) | (1 << n)
	elif device.begins_with("pad:") and connected(device):
		var id := int(device.get_slice(":", 1))
		var buttons: Dictionary = {}
		for button in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
			JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_A, JOY_BUTTON_B]:
			buttons[button] = Input.is_joy_button_pressed(id, button)
		held = pad_held(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y), buttons, id)
	return held

func pad_held(horizontal: float, vertical: float, buttons: Dictionary, device: int = -1) -> Dictionary:
	var previous: Vector2i = stick_directions.get(device, Vector2i.ZERO)
	var stick := Vector2i(_axis(horizontal, previous.x), _axis(vertical, previous.y))
	stick_directions[device] = stick
	var right: bool = stick.x == 1 or buttons.get(JOY_BUTTON_DPAD_RIGHT, false)
	var left: bool = stick.x == -1 or buttons.get(JOY_BUTTON_DPAD_LEFT, false)
	var down: bool = stick.y == 1 or buttons.get(JOY_BUTTON_DPAD_DOWN, false)
	var up: bool = stick.y == -1 or buttons.get(JOY_BUTTON_DPAD_UP, false)
	var held := {"x": int(right) - int(left), "y": int(down) - int(up), "buttons": 0}
	if right and left:
		held.direction_conflict = true
	for n in range(4):
		if buttons.get([JOY_BUTTON_X, JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_B][n], false):
			held.buttons = int(held.buttons) | (1 << n)
	return held

func _axis(value: float, previous: int) -> int:
	if absf(value) <= 0.2:
		return 0
	if value >= 0.55:
		return 1
	if value <= -0.55:
		return -1
	return previous

func read(_slot: int, device: String) -> Dictionary:
	var held := sample(device)
	var mask: int = suppressed.get(device, 0)
	mask &= int(held.buttons)
	suppressed[device] = mask
	held.buttons = int(held.buttons) & ~mask
	return held

func command_from_held(_slot: int, held: Dictionary) -> Dictionary:
	return held.duplicate()

func reset(devices: Array) -> void:
	stick_directions.clear()
	for device: String in devices:
		suppressed[device] = int(sample(device).buttons)
