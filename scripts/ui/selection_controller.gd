extends RefCounted
## Device-owned selection cursors. Combat input remains entirely separate.
var app: Node
var ready: Array[bool] = [false, false]
var active_slot: int = 0
var modal: bool = false
var held: Dictionary = {}
var repeat_time: Dictionary = {}
const COLS := 6

func reset() -> void:
	ready.assign([false, false])
	active_slot = 0
	modal = false
	held.clear()
	repeat_time.clear()

func activate(slot: int) -> void:
	active_slot = slot
	ready[slot] = false
	app.gui.refresh_setup()

func choose(slot: int, id: String) -> void:
	if ready[slot] or not app.catalog.characters.has(id):
		return
	active_slot = slot
	app.characters[slot] = id
	app.sound.play("select", 0.45)
	app.gui.refresh_setup()

func move_cursor(slot: int, direction: Vector2i) -> void:
	if app.screen == "stage":
		var ids: Array = app.catalog.stages.keys()
		var index := ids.find(app.stage_id)
		app.stage_id = ids[posmod(index + (direction.x if direction.x != 0 else direction.y), ids.size())]
		app.gui.refresh_stages()
		return
	if ready[slot]:
		return
	var ids: Array = app.catalog.characters.keys()
	var columns := mini(COLS, ids.size())
	var current := ids.find(app.characters[slot])
	var target := current + direction.x + direction.y * columns
	if direction.x != 0:
		var row_start := int(current / columns) * columns
		var row_count := mini(columns, ids.size() - row_start)
		target = row_start + posmod(current - row_start + direction.x, row_count)
	else:
		target = clampi(target, 0, ids.size() - 1)
	choose(slot, ids[target])

func confirm(slot: int) -> void:
	if not app._devices_ready() or (app.mode == "local" and app.devices[0] == app.devices[1]):
		app._validate_setup()
		return
	if app.screen == "stage":
		if slot == 0:
			app.start_match()
		return
	if ready[slot]:
		return
	ready[slot] = true
	app.sound.play("select")
	if ready[0] and ready[1]:
		app.show_stages()
	else:
		active_slot = 1 if ready[0] else 0
		app.gui.refresh_setup()

func cancel(slot: int) -> void:
	if app.screen == "stage":
		app.show_setup()
		return
	if ready[slot]:
		ready[slot] = false
		active_slot = slot
	elif app.mode != "local" and slot == 1:
		ready[0] = false
		active_slot = 0
	else:
		app.show_title()
		return
	app.gui.refresh_setup()

func _owner(device: String) -> int:
	if device == app.devices[0]:
		return 0 if app.screen == "stage" or app.mode == "local" else active_slot
	if app.mode == "local" and device == app.devices[1]:
		return 1
	return -1

func handle(event: InputEvent) -> bool:
	if modal or app.screen not in ["setup", "stage"]:
		return false
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var slot := -1
		var direction := Vector2i.ZERO
		var operation := ""
		for keyboard in range(2):
			var mapping: Array = app.router.current_keys(keyboard)
			var keys: Array = [mapping[0],mapping[1],mapping[3],mapping[2],mapping[4],mapping[5]]
			var index := keys.find(key)
			if index >= 0:
				slot = _owner("keyboard:%d" % keyboard)
				if index < 4:
					direction = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][index]
				else:
					operation = "confirm" if index == 4 else "cancel"
				break
		if slot < 0 and key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			var focused: Control = app.get_viewport().gui_get_focus_owner()
			if focused != null and not str(focused.name).begins_with("character_") and not str(focused.name).begins_with("stage_"):
				return false
			slot = 0 if app.screen == "stage" else active_slot
			operation = "confirm"
		if slot < 0:
			return false
		if app.screen == "stage" and slot != 0:
			return true
		if event.pressed:
			if direction != Vector2i.ZERO:
				move_cursor(slot, direction)
			elif not event.echo:
				if operation == "confirm": confirm(slot)
				elif operation == "cancel": cancel(slot)
		return true
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var slot := _owner("pad:%d" % event.device)
		if slot < 0 or (app.screen == "stage" and slot != 0):
			return true
		var direction := Vector2i.ZERO
		var key := "%d" % event.device
		if event is InputEventJoypadMotion:
			if event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
				return true
			var value := int(signf(event.axis_value)) if absf(event.axis_value) > 0.55 else 0
			direction = Vector2i(value, 0) if event.axis == JOY_AXIS_LEFT_X else Vector2i(0, value)
			key += ":%d" % event.axis
		else:
			if event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START] and event.pressed:
				confirm(slot)
				return true
			if event.button_index == JOY_BUTTON_B and event.pressed:
				cancel(slot)
				return true
			var dirs := {JOY_BUTTON_DPAD_LEFT: Vector2i.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2i.RIGHT, JOY_BUTTON_DPAD_UP: Vector2i.UP, JOY_BUTTON_DPAD_DOWN: Vector2i.DOWN}
			if not dirs.has(event.button_index):
				return true
			direction = dirs[event.button_index] if event.pressed else Vector2i.ZERO
			key += ":%d" % event.button_index
		if direction != held.get(key, Vector2i.ZERO):
			held[key] = direction
			repeat_time[key] = 0.34
			if direction != Vector2i.ZERO:
				move_cursor(slot, direction)
		return true
	return false

func tick(delta: float) -> void:
	if modal or app.screen not in ["setup", "stage"]:
		held.clear()
		return
	for key: String in held:
		if held[key] == Vector2i.ZERO: continue
		repeat_time[key] = float(repeat_time[key]) - delta
		if repeat_time[key] <= 0:
			repeat_time[key] = 0.11
			var slot := _owner("pad:" + key.get_slice(":", 0))
			if slot >= 0 and (app.screen != "stage" or slot == 0):
				move_cursor(slot, held[key])
