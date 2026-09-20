class_name DuelInput
extends RefCounted
## Direction taps use fixed simulation samples, never OS key-repeat or render time.
const Combat = preload("res://scripts/combat.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const ACTIONS: Array[String] = ["left", "right", "down", "jump", "light", "heavy", "skill", "throw"]
const KEYS: Array = [
	[KEY_A, KEY_D, KEY_S, KEY_W, KEY_F, KEY_G, KEY_H, KEY_R],
	[KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_J, KEY_K, KEY_L, KEY_U]
]
var previous: Array[Dictionary] = [{}, {}]
var tap_direction: Array[int] = [0, 0]
var tap_age: Array[int] = [99, 99]
var tap_released: Array[bool] = [false, false]
var stick_directions: Dictionary = {}

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

func available_devices() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id": "keyboard:0", "label": "键盘 1 · WASD / FGHR"},
		{"id": "keyboard:1", "label": "键盘 2 · 方向键 / JKLU"}
	]
	for id in Input.get_connected_joypads():
		result.append({"id": "pad:%d" % id, "label": "手柄 %d · %s" % [id + 1, Input.get_joy_name(id)]})
	return result

func connected(device: String) -> bool:
	return not device.begins_with("pad:") or int(device.get_slice(":", 1)) in Input.get_connected_joypads()

func sample(device: String) -> Dictionary:
	var held := Combat.neutral()
	if device.begins_with("keyboard:"):
		var number := int(device.get_slice(":", 1)) + 1
		var prefix := "p%d_" % number
		var right := Input.is_action_pressed(prefix + "right")
		var left := Input.is_action_pressed(prefix + "left")
		held.x = int(right) - int(left)
		held.direction_conflict = right and left
		for action in ["down", "jump", "light", "heavy", "skill", "throw"]:
			held[action] = Input.is_action_pressed(prefix + action)
	elif device.begins_with("pad:") and connected(device):
		var id := int(device.get_slice(":", 1))
		var buttons: Dictionary = {}
		for button in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
			JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_A, JOY_BUTTON_B]:
			buttons[button] = Input.is_joy_button_pressed(id, button)
		held = pad_held(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y), buttons, id)
	return held

func pad_held(horizontal: float, vertical: float, buttons: Dictionary, device: int = -1) -> Dictionary:
	var held := Combat.neutral()
	var stick: int = stick_directions.get(device, 0)
	# Hysteresis requires returning to neutral before another tap, filtering jitter.
	if absf(horizontal) <= 0.2:
		stick = 0
	elif horizontal >= 0.55:
		stick = 1
	elif horizontal <= -0.55:
		stick = -1
	stick_directions[device] = stick
	var right: bool = stick == 1 or buttons.get(JOY_BUTTON_DPAD_RIGHT, false)
	var left: bool = stick == -1 or buttons.get(JOY_BUTTON_DPAD_LEFT, false)
	held.x = int(right) - int(left)
	held.direction_conflict = right and left
	held.down = vertical > 0.35 or buttons.get(JOY_BUTTON_DPAD_DOWN, false)
	held.jump = vertical < -0.35 or buttons.get(JOY_BUTTON_DPAD_UP, false)
	held.light = buttons.get(JOY_BUTTON_X, false)
	held.heavy = buttons.get(JOY_BUTTON_Y, false)
	held.skill = buttons.get(JOY_BUTTON_A, false)
	held.throw = buttons.get(JOY_BUTTON_B, false)
	return held

func read(slot: int, device: String) -> Dictionary:
	return command_from_held(slot, sample(device))

func command_from_held(slot: int, held: Dictionary) -> Dictionary:
	var command := held.duplicate()
	command.dash = 0
	tap_age[slot] = mini(99, tap_age[slot] + 1)
	var axis := clampi(int(held.get("x", 0)), -1, 1)
	var previous_axis: int = previous[slot].get("x", 0)
	if held.get("direction_conflict", false):
		tap_direction[slot] = 0
		tap_released[slot] = false
	elif axis == 0:
		tap_released[slot] = true
	elif axis != previous_axis:
		if previous_axis == 0 and tap_released[slot] and tap_direction[slot] == axis and tap_age[slot] <= Arena.DASH_WINDOW:
			command.dash = axis
			tap_direction[slot] = 0
			tap_age[slot] = 99
		else:
			tap_direction[slot] = axis
			tap_age[slot] = 0
		tap_released[slot] = false
	for action in ["jump", "light", "heavy", "skill", "throw"]:
		command[action] = bool(held.get(action, false)) and not bool(previous[slot].get(action, false))
	previous[slot] = held.duplicate()
	return command

func reset(devices: Array) -> void:
	stick_directions.clear()
	for i in range(2):
		previous[i] = sample(devices[i])
		tap_direction[i] = 0
		tap_age[i] = 99
		tap_released[i] = false
