extends RefCounted
## Device-owned selection cursors. Combat input remains entirely separate.
## The grid is COLS wide: every roster character, then 「敬请期待」 placeholders up to
## MIN_CELLS, then the random cell last. A cursor on a character is that player's pick
## (app.characters); `special` only records a cursor resting on a placeholder or random.
var app: Node
var ready: Array[bool] = [false, false]
var active_slot: int = 0
var modal: bool = false
var held: Dictionary = {}
var repeat_time: Dictionary = {}
var special: Array[int] = [-1, -1]
## Slots locked through the random cell; the showcase plays its roulette for them.
var rolled: Array[bool] = [false, false]
var rng := RandomNumberGenerator.new()
## After a random pick completes both locks, the stage screen waits this long so the
## roulette and seal are seen. Selection input is held meanwhile.
var reveal_delay: float = 0.0
const COLS := 4
const MIN_CELLS := 16
const RANDOM := "@random"
const REVEAL_SECONDS := 0.75

func _init() -> void:
	rng.randomize()

func reset() -> void:
	ready.assign([false, false])
	active_slot = 0
	modal = false
	held.clear()
	repeat_time.clear()
	special.assign([-1, -1])
	rolled.assign([false, false])
	reveal_delay = 0.0

## Grid cells in display order: character ids, "" placeholders, RANDOM last.
func cells() -> Array[String]:
	var result: Array[String] = []
	for id: String in app.catalog.characters:
		result.append(id)
	var count := maxi(MIN_CELLS, ceili((result.size() + 1) / float(COLS)) * COLS)
	while result.size() < count - 1:
		result.append("")
	result.append(RANDOM)
	return result

func cursor_cell(slot: int) -> int:
	if special[slot] >= 0:
		return special[slot]
	return maxi(0, cells().find(app.characters[slot]))

## Character id, "" (placeholder) or RANDOM under `slot`'s cursor.
func cell_id(slot: int) -> String:
	return cells()[cursor_cell(slot)]

func revealing() -> bool:
	return reveal_delay > 0.0

func activate(slot: int) -> void:
	if revealing():
		return
	active_slot = slot
	ready[slot] = false
	rolled[slot] = false
	app.gui.refresh_setup()

func choose(slot: int, id: String) -> void:
	if ready[slot] or revealing() or not app.catalog.characters.has(id):
		return
	active_slot = slot
	special[slot] = -1
	app.characters[slot] = id
	app.sound.play("ui_move", 0.35)
	app.gui.refresh_setup()

## Puts `slot`'s cursor on any grid cell (mouse clicks, and every keyboard/pad move).
func point(slot: int, index: int) -> void:
	var grid := cells()
	if ready[slot] or revealing() or index < 0 or index >= grid.size():
		return
	if app.catalog.characters.has(grid[index]):
		choose(slot, grid[index])
		return
	active_slot = slot
	special[slot] = index
	app.sound.play("ui_move", 0.35)
	app.gui.refresh_setup()

func move_cursor(slot: int, direction: Vector2i) -> void:
	if app.screen == "stage":
		var ids: Array = app.catalog.stages.keys()
		var index := ids.find(app.stage_id)
		app.stage_id = ids[posmod(index + (direction.x if direction.x != 0 else direction.y), ids.size())]
		app.gui.refresh_stages()
		return
	if ready[slot] or revealing():
		return
	var rows := int(cells().size() / float(COLS))
	var current := cursor_cell(slot)
	var row := int(current / float(COLS))
	var column := current % COLS
	if direction.x != 0:
		column = posmod(column + direction.x, COLS)
	else:
		row = posmod(row + direction.y, rows)
	point(slot, row * COLS + column)

func confirm(slot: int) -> void:
	if revealing():
		return
	if not app._devices_ready() or (app.mode == "local" and app.devices[0] == app.devices[1]):
		app._validate_setup()
		return
	if app.screen == "stage":
		if slot == 0:
			app.start_match()
		return
	if ready[slot]:
		return
	var id := cell_id(slot)
	if id.is_empty():
		app.sound.play("ui_back", 0.5)
		return
	rolled[slot] = id == RANDOM
	if rolled[slot]:
		var ids: Array = app.catalog.characters.keys()
		app.characters[slot] = ids[rng.randi_range(0, ids.size() - 1)]
		special[slot] = -1
	ready[slot] = true
	app.sound.play("select")
	if ready[0] and ready[1] and rolled[slot]:
		reveal_delay = REVEAL_SECONDS
		app.gui.refresh_setup()
	elif ready[0] and ready[1]:
		app.show_stages()
	else:
		active_slot = 1 if ready[0] else 0
		app.gui.refresh_setup()

func cancel(slot: int) -> void:
	if revealing():
		return
	if app.screen == "stage":
		app.show_setup()
		return
	if ready[slot]:
		ready[slot] = false
		rolled[slot] = false
		active_slot = slot
	elif app.mode != "local" and slot == 1:
		ready[0] = false
		rolled[0] = false
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
	if revealing() and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return true
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
			if focused != null and not focused.has_meta("select_cell") and not str(focused.name).begins_with("stage_"):
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
	if revealing():
		reveal_delay = maxf(reveal_delay - delta, 0.0)
		held.clear()
		if not revealing() and app.screen == "setup" and ready[0] and ready[1]:
			app.show_stages()
		return
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
