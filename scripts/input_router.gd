class_name DuelInput
extends RefCounted
## Every input source returns the same command shape. Edge detection lives here,
## so holding a button never repeatedly starts a move or a jump.

const Combat = preload("res://scripts/combat.gd")
const ACTIONS: Array[String] = ["left", "right", "down", "jump", "light", "heavy", "skill", "throw"]
const KEYS: Array = [
	[KEY_A, KEY_D, KEY_S, KEY_W, KEY_F, KEY_G, KEY_H, KEY_R],
	[KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_J, KEY_K, KEY_L, KEY_U]
]
var previous: Array[Dictionary] = [{}, {}]

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
		held.x = int(Input.is_action_pressed(prefix + "right")) - int(Input.is_action_pressed(prefix + "left"))
		for action in ["down", "jump", "light", "heavy", "skill", "throw"]:
			held[action] = Input.is_action_pressed(prefix + action)
	elif device.begins_with("pad:") and connected(device):
		var id := int(device.get_slice(":", 1))
		var horizontal := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		var vertical := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
		var buttons: Dictionary = {}
		for button in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
			JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_A, JOY_BUTTON_B]:
			buttons[button] = Input.is_joy_button_pressed(id, button)
		held = pad_held(horizontal, vertical, buttons)
	return held

func pad_held(horizontal: float, vertical: float, buttons: Dictionary) -> Dictionary:
	var held := Combat.neutral()
	held.x = int(horizontal > 0.35 or buttons.get(JOY_BUTTON_DPAD_RIGHT, false)) \
		- int(horizontal < -0.35 or buttons.get(JOY_BUTTON_DPAD_LEFT, false))
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
	for action in ["jump", "light", "heavy", "skill", "throw"]:
		command[action] = bool(held.get(action, false)) and not bool(previous[slot].get(action, false))
	previous[slot] = held.duplicate()
	return command

func reset(devices: Array) -> void:
	for i in range(2):
		previous[i] = sample(devices[i])
