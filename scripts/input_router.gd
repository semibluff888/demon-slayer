class_name DuelInput
extends RefCounted
## Device adapter only. Edge/motion/dash recognition belongs to the model.
const Commands = preload("res://scripts/command_recognizer.gd")
const ACTIONS: Array[String] = ["left", "right", "down", "up", "a", "b", "c", "d"]
const KEYS: Array = [
	[KEY_A, KEY_D, KEY_S, KEY_W, KEY_U, KEY_I, KEY_J, KEY_K],
	[KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_KP_5, KEY_KP_6, KEY_KP_2, KEY_KP_3]]
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

func apply_keymaps(maps: Array) -> void:
	for player in range(2):
		for n in range(ACTIONS.size()):
			var action := "p%d_%s" % [player+1,ACTIONS[n]]
			Input.action_release(action)
			InputMap.action_erase_events(action)
			var event := InputEventKey.new()
			event.physical_keycode=maps[player][n]
			InputMap.action_add_event(action,event)
	suppressed.clear()

static func current_keys(player: int) -> Array:
	var result: Array=[]
	for n in range(ACTIONS.size()):
		var code: int=KEYS[player][n]
		var action := "p%d_%s" % [player+1,ACTIONS[n]]
		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action):
				if event is InputEventKey:
					code=event.physical_keycode if event.physical_keycode else event.keycode
					break
		result.append(code)
	return result

static func key_name(code: int) -> String:
	if code>=KEY_KP_0 and code<=KEY_KP_9:return "Num%d" % [code-KEY_KP_0]
	var special := {KEY_LEFT:"←",KEY_RIGHT:"→",KEY_UP:"↑",KEY_DOWN:"↓",KEY_KP_ENTER:"NumEnter"}
	return special.get(code,OS.get_keycode_string(code))

static func movement_hint(player: int) -> String:
	var keys:=current_keys(player)
	return " ".join([key_name(keys[3]),key_name(keys[0]),key_name(keys[2]),key_name(keys[1])])

static func device_hint(device: String) -> String:
	if not device.begins_with("keyboard:"):return "手柄 X A / Y B"
	var player:=int(device.get_slice(":",1))
	var keys:=current_keys(player)
	return "%s / %s %s · %s %s" % [movement_hint(player),key_name(keys[4]),key_name(keys[5]),key_name(keys[6]),key_name(keys[7])]

static func selection_hint(device: String) -> String:
	if not device.begins_with("keyboard:"):return "十字键 · A 确认 · B 返回"
	var keys:=current_keys(int(device.get_slice(":",1)))
	return "%s 确认 · %s 返回" % [key_name(keys[4]),key_name(keys[5])]

static func motion_hints(device: String, facing: int) -> Array[String]:
	var keyboard:=device.begins_with("keyboard:")
	var keys:=current_keys(int(device.get_slice(":",1))) if keyboard else []
	var left:=key_name(keys[0]) if keyboard else "←"
	var right:=key_name(keys[1]) if keyboard else "→"
	var down:=key_name(keys[2]) if keyboard else "↓"
	var slash:="%s / %s" % [key_name(keys[4]),key_name(keys[6])] if keyboard else "X / Y"
	var body:="%s / %s" % [key_name(keys[5]),key_name(keys[7])] if keyboard else "A / B"
	var forward:=right if facing>0 else left
	var back:=left if facing>0 else right
	return ["236：%s → %s + (%s)" % [down,forward,slash],
		"214：%s → %s + (%s)" % [down,back,body],
		"朝%s · 松开%s · 0.5秒完成，攻击可晚0.2秒" % ["右" if facing>0 else "左",down]]

func available_devices() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id": "keyboard:0", "label": "键盘 1 · WASD / UI·JK"},
		{"id": "keyboard:1", "label": "键盘 2 · 方向键 / Num56·Num23"}]
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
