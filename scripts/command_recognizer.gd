class_name DuelCommands
extends RefCounted
## All input is sampled in simulation ticks, including hitstop.
const A := 1
const B := 2
const C := 4
const D := 8
const MOTION_WINDOW := 30
const BUTTON_WINDOW := 12
const DP_WINDOW := 20
const SUPER_WINDOW := 36
const STRICT_BUTTON_WINDOW := 6
const CHORD_WINDOW := 2
const FEEDBACK_WINDOW := 90
const FEEDBACK_DURATION := 180
const PATTERNS := {
	"236236": [[2], [3, 0], [6], [2], [3, 0], [6]],
	"623": [[6], [2], [3], [6, 0]],
	"236": [[2], [3, 0], [6]],
	"214": [[2], [1, 0], [4]]}
const PRIORITY := ["236236", "623", "236", "214", ""]
var tick: int = 0
var last_buttons: int = 0
var last_x: int = 0
var last_y: int = 0
var last_facing: int = 1
var directions: Array[Dictionary] = []
var history: Array[Dictionary] = []
var pending: Dictionary = {}
var tap_direction: int = 0
var tap_tick: int = -99
var tap_released: bool = false
var last_action: String = ""
var consumed_tick: int = -1
var feedback: String = ""
var feedback_until: int = 0

func reset(held: Dictionary = {}) -> void:
	last_buttons = int(held.get("buttons", 0))
	last_x = int(held.get("x", 0))
	last_y = int(held.get("y", 0))
	directions.clear()
	history.clear()
	pending.clear()
	tap_direction = 0
	tap_tick = -99
	tap_released = false
	last_action = ""
	consumed_tick = tick
	feedback = ""
	feedback_until = 0

func sample(command: Dictionary, facing: int) -> Dictionary:
	tick += 1
	var x := clampi(int(command.get("x", 0)), -1, 1)
	var y := clampi(int(command.get("y", 0)), -1, 1)
	var buttons := int(command.get("buttons", 0)) & 15
	var pressed := buttons & ~last_buttons
	var result := {"x": x, "y": y, "jump": y == -1 and last_y != -1,
		"dash": 0, "pressed": pressed, "action": {}}
	if tick >= feedback_until:
		feedback = ""
		feedback_until = 0
	if facing != last_facing:
		directions.clear()
		# Preserve an already pressed normal, but do not complete its old motion
		# with directions entered after crossing to the other side.
		if not pending.is_empty():
			pending.allow_completion = false
		feedback = ""
		feedback_until = 0
	last_facing = facing
	var direction := 5 + x * facing - y * 3
	if directions.is_empty() or int(directions.back().direction) != direction:
		directions.append({"direction": direction, "tick": tick, "end_tick": tick})
	else:
		directions.back().end_tick = tick
	# Keep occupied intervals, including a long initial crouch. Only the first
	# down in 236/214 uses its last occupied tick; later holds cannot refresh it.
	while directions.size() > 1 and tick - int(directions[0].end_tick) > FEEDBACK_WINDOW:
		directions.pop_front()
	if history.is_empty() or direction != int(history.back().direction) or pressed != 0:
		history.append({"direction": direction, "buttons": pressed, "tick": tick})
		if history.size() > 18:
			history.pop_front()
	if command.get("direction_conflict", false):
		tap_direction = 0
		tap_released = false
	elif x == 0:
		tap_released = true
	elif x != last_x:
		if last_x == 0 and tap_released and tap_direction == x and tick - tap_tick <= 12:
			result.dash = x
			tap_direction = 0
			tap_tick = -99
		else:
			tap_direction = x
			tap_tick = tick
		tap_released = false
	if pressed != 0:
		if pending.is_empty():
			pending = {"buttons": pressed, "tick": tick, "x": x * facing, "y": y,
				"motion": motion(), "allow_completion": true, "feedback": _diagnose(pressed)}
		elif tick - int(pending.tick) <= CHORD_WINDOW:
			pending.buttons = int(pending.buttons) | pressed
	if not pending.is_empty():
		# Reuse the existing chord wait: a final direction may arrive up to two
		# ticks after the attack, without adding any latency to ordinary normals.
		if pending.allow_completion and tick > int(pending.tick) and tick - int(pending.tick) <= CHORD_WINDOW:
			var completed := motion()
			if PRIORITY.find(completed) < PRIORITY.find(str(pending.motion)):
				pending.motion = completed
		if tick - int(pending.tick) >= CHORD_WINDOW:
			var mask := int(pending.buttons)
			var action := pending.duplicate()
			if (mask & (A | B)) == (A | B):
				action.type = "roll"
			elif (mask & (A | C)) == (A | C) and action.motion == "236236":
				action.type = "max"
			elif (mask & (A | C)) != 0 and action.motion in ["236236", "623", "236"]:
				action.type = "motion"
				action.button = "C" if mask & C else "A"
			elif (mask & (B | D)) != 0 and action.motion == "214":
				action.type = "motion"
				action.button = "D" if mask & D else "B"
			else:
				action.type = "normal"
				action.button = "D" if mask & D else ("C" if mask & C else ("B" if mask & B else "A"))
			feedback = ""
			if action.type == "normal" and pending.allow_completion:
				feedback = str(pending.feedback)
				if feedback.is_empty():
					feedback = _diagnose(mask)
			feedback_until = tick + FEEDBACK_DURATION if not feedback.is_empty() else 0
			if action.type in ["motion", "max", "roll"]:
				# A second button press needs a fresh motion, even inside the wider
				# button window. This also stops an old 236 becoming a later super.
				consumed_tick = tick
			action.erase("allow_completion")
			action.erase("feedback")
			result.action = action
			pending.clear()
	last_buttons = buttons
	last_x = x
	last_y = y
	return result

func motion() -> String:
	for name: String in PRIORITY:
		if name.is_empty():
			break
		var match_data := _motion_match(name)
		if not match_data.is_empty() and match_data.reason.is_empty():
			return name
	return ""

func _motion_match(name: String) -> Dictionary:
	var quarter := name in ["236", "214"]
	var window := MOTION_WINDOW if quarter else (DP_WINDOW if name == "623" else SUPER_WINDOW)
	return _match_pattern(PATTERNS[name], window, BUTTON_WINDOW if quarter else STRICT_BUTTON_WINDOW, quarter)

func _match_pattern(pattern: Array, window: int, button_window: int, held_start: bool = false) -> Dictionary:
	var samples: Array[Dictionary] = []
	for entry in directions:
		if int(entry.direction) != 5 and int(entry.end_tick) > consumed_tick:
			samples.append(entry)
	if samples.is_empty():
		return {}
	var cursor := samples.size() - 1
	for n in range(pattern.size() - 1, -1, -1):
		var accepted: Array = pattern[n]
		if cursor >= 0 and int(samples[cursor].direction) in accepted:
			cursor -= 1
		elif 0 not in accepted:
			return {}
	var first: Dictionary = samples[cursor + 1]
	var start: int = first.end_tick if held_start else first.tick
	var completed: int = samples.back().tick
	if start <= consumed_tick:
		return {}
	var reason := ""
	if tick - start > window:
		reason = "motion_timeout"
	elif tick - completed > button_window:
		reason = "attack_late"
	return {"reason": reason, "completed": completed}

func _diagnose(mask: int) -> String:
	for name in ["236", "214"]:
		var compatible := (mask & (A | C)) != 0 if name == "236" else (mask & (B | D)) != 0
		var match_data := _motion_match(name)
		if not match_data.is_empty():
			if compatible:
				return str(match_data.reason)
			if match_data.reason.is_empty():
				return "wrong_button"
		if compatible:
			var incomplete := _match_pattern([[2], [3 if name == "236" else 1]], MOTION_WINDOW, BUTTON_WINDOW, true)
			if not incomplete.is_empty() and incomplete.reason.is_empty():
				return "release_down"
	return ""

func snapshot() -> Dictionary:
	return {"tick": tick, "last_buttons": last_buttons, "last_x": last_x, "last_y": last_y,
		"facing": last_facing, "directions": directions.duplicate(true), "pending": pending.duplicate(true),
		"tap_direction": tap_direction, "tap_tick": tap_tick, "released": tap_released,
		"history": history.duplicate(true), "last_action": last_action, "consumed_tick": consumed_tick,
		"feedback": feedback, "feedback_until": feedback_until}
