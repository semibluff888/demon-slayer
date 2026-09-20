extends SceneTree
const Commands = preload("res://scripts/command_recognizer.gd")
const Router = preload("res://scripts/input_router.gd")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
var s := Support.new()
var passed := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(message)

func _initialize() -> void:
	_motions()
	_leniency()
	_early_attacks()
	_early_in_combat()
	_feedback()
	_device_motions()
	_buttons()
	_devices()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("INPUT TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func action(digits: String, mask: int, facing: int = 1, duration: int = 1) -> Dictionary:
	var reader := Commands.new()
	reader.last_facing = facing
	var result: Dictionary = {}
	for i in range(digits.length()):
		var held := s.relative(int(digits[i]), facing, mask if i == digits.length() - 1 else 0)
		for n in range(duration if i < digits.length() - 1 else 3):
			var sample := reader.sample(held, facing)
			if not sample.action.is_empty():
				result = sample.action
	return result

func _motions() -> void:
	for facing in [-1, 1]:
		for pair in [["236", "236"], ["26", "236"], ["214", "214"], ["24", "214"], ["623", "623"], ["6236", "623"], ["236236", "236236"], ["2626", "236236"]]:
			var mask := Commands.B if pair[1] == "214" else Commands.A
			var result := action(pair[0], mask, facing)
			check(result.get("motion", "") == pair[1] and result.get("type", "") == "motion", "relative motion %s facing %d" % [pair, facing])
		check(action("236236", Commands.A | Commands.C, facing).type == "max", "MAX chord wins over 1-bar super")
		check(action("236", Commands.A | Commands.B, facing).type == "roll", "roll chord suppresses quarter-circle A")
		check(action("214", Commands.A, facing).type == "normal", "wrong button family does not cast a special")
	check(action("236", Commands.A, 1, 32).type == "normal", "overlong quarter-circle expires")
	check(action("236236", Commands.A, 1, 10).motion != "236236", "overlong double quarter-circle cannot become a super")
	var reader := Commands.new()
	reader.sample(s.relative(2, 1), 1)
	reader.sample(s.relative(3, 1), 1)
	reader.sample(s.relative(6, -1, Commands.A), -1)
	reader.sample(Combat.neutral(), -1)
	check(reader.sample(Combat.neutral(), -1).action.type == "normal", "cross-up clears unfinished world-direction history")
	reader = Commands.new()
	reader.sample(s.relative(2, 1), 1)
	reader.sample(Combat.neutral(), 1)
	reader.sample(s.relative(3, 1), 1)
	reader.sample(Combat.neutral(), 1)
	reader.sample(s.relative(6, 1, Commands.A), 1)
	reader.sample(Combat.neutral(), 1)
	check(reader.sample(Combat.neutral(), 1).action.motion == "236", "brief neutral is tolerated")

func _buttons() -> void:
	for gap in [0, 1, 2]:
		var reader := Commands.new()
		var outputs: Array = []
		for frame in range(8):
			var buttons := Commands.A
			if frame >= gap:
				buttons |= Commands.B
			var result := reader.sample({"buttons": buttons}, 1)
			if not result.action.is_empty():
				outputs.append(result.action.type)
		check(outputs == ["roll"], "chord tolerance emits one action at gap %d" % gap)
	var crossed := Commands.new()
	crossed.sample({"buttons": Commands.A}, 1)
	crossed.sample({}, -1)
	check(crossed.sample({}, -1).action.type == "normal", "cross-up does not erase an already pressed normal")
	var reader := Commands.new()
	var count := 0
	for frame in range(90):
		if not reader.sample({"buttons": Commands.A}, 1).action.is_empty():
			count += 1
	check(count == 1, "held button never repeats")
	reader.reset({"buttons": Commands.A, "y": -1})
	check(not reader.sample({"buttons": Commands.A, "y": -1}, 1).jump, "reset suppresses held jump")
	check(reader.sample({"buttons": Commands.A}, 1).action.is_empty(), "reset suppresses held attack")
	for facing in [-1, 1]:
		for direction in [-1, 1]:
			reader = Commands.new()
			check(reader.sample({"x": direction}, facing).dash == 0, "first direction tap walks")
			reader.sample({}, facing)
			check(reader.sample({"x": direction}, facing).dash == direction, "double tap is world-space")
			for frame in range(20):
				check(reader.sample({"x": direction}, facing).dash == 0, "direction hold does not retrigger")
	for gap in [11, 12]:
		reader = Commands.new()
		reader.sample({"x": 1}, 1)
		for frame in range(gap):
			reader.sample({}, 1)
		check(reader.sample({"x": 1}, 1).dash == (1 if gap == 11 else 0), "dash 12/13 tick boundary")
	reader = Commands.new()
	reader.sample({"x": 1}, 1)
	reader.sample({"direction_conflict": true}, 1)
	check(reader.sample({"x": 1}, 1).dash == 0, "SOCD invalidates double tap")

func _devices() -> void:
	var router := Router.new()
	check(router.pad_held(0.1, 0.1, {}).buttons == 0, "pad deadzone neutral")
	var pad := router.pad_held(-0.8, 0.8, {JOY_BUTTON_X: true, JOY_BUTTON_B: true})
	check(pad.x == -1 and pad.y == 1 and pad.buttons == (Commands.A | Commands.D), "pad axes and X/B map to A/D")
	pad = router.pad_held(0, 0, {JOY_BUTTON_Y: true, JOY_BUTTON_A: true, JOY_BUTTON_DPAD_UP: true})
	check(pad.y == -1 and pad.buttons == (Commands.C | Commands.B), "pad Y/A map to C/B")
	var reader := Commands.new()
	reader.sample(router.pad_held(0.8, 0, {}), 1)
	for amount in [0.36, 0.28, 0.42, 0.31, 0.8]:
		check(reader.sample(router.pad_held(amount, 0, {}), 1).dash == 0, "stick hysteresis avoids false releases")
	reader.sample(router.pad_held(0, 0, {}), 1)
	check(reader.sample(router.pad_held(0.8, 0, {}), 1).dash == 1, "pad neutral enables second tap")
	for pair in [["a", KEY_F, Commands.A], ["b", KEY_G, Commands.B], ["c", KEY_V, Commands.C], ["d", KEY_B, Commands.D]]:
		var event := InputEventKey.new()
		event.physical_keycode = pair[1]
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		check(router.sample("keyboard:0").buttons == pair[2] and router.sample("keyboard:1").buttons == 0, "physical P1 key %s is isolated" % pair[0])
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	Input.action_press("p1_a")
	router.reset(["keyboard:0", "keyboard:1"])
	check(router.read(0, "keyboard:0").buttons == 0, "screen transition suppresses held buttons")
	Input.action_release("p1_a")
	router.read(0, "keyboard:0")
	Input.action_press("p1_a")
	check(router.read(0, "keyboard:0").buttons == Commands.A, "release rearms suppressed button")
	Input.action_release("p1_a")
	check(not router.connected("pad:999"), "missing pad detected")


func probe(sequence: Array, facing: int = 1) -> Dictionary:
	var reader := Commands.new()
	reader.last_facing = facing
	var outputs: Array[Dictionary] = []
	for part in sequence:
		var held := s.relative(part[0], facing, part[2] if part.size() > 2 else 0)
		for n in range(part[1]):
			var sample := reader.sample(held, facing)
			if not sample.action.is_empty():
				var emitted: Dictionary = sample.action.duplicate()
				emitted.emitted = reader.tick
				outputs.append(emitted)
	return {"reader": reader, "actions": outputs}

func _leniency() -> void:
	for facing in [-1, 1]:
		for pair in [[6, 3, Commands.A, "236"], [6, 3, Commands.C, "236"], [4, 1, Commands.B, "214"], [4, 1, Commands.D, "214"]]:
			var end: int = pair[0]
			var diagonal: int = pair[1]
			var mask: int = pair[2]
			for duration in [1, 180]:
				var p := probe([[2, duration], [5, 4], [end, 10], [end, 3, mask]], facing)
				check(p.actions.size() == 1 and p.actions[0].type == "motion" and p.actions[0].motion == pair[3],
					"two-beat motion accepts neutral, delayed attack and initial hold: %s facing %d hold %d" % [pair, facing, duration])
			for delay in [12, 13, 95]:
				var p := probe([[2, 1], [end, delay], [end, 3, mask]], facing)
				check(p.actions.size() == 1 and p.actions[0].type == ("motion" if delay == 12 else "normal"),
					"last horizontal direction 12/13 tick limit never refreshes on hold: %s delay %d" % [pair, delay])
			for duration in [29, 30]:
				var p := probe([[2, 180], [diagonal, duration], [end, 3, mask]], facing)
				check(p.actions.size() == 1 and p.actions[0].type == ("motion" if duration == 29 else "normal"),
					"30/31 tick motion boundary measures from leaving initial down: %s duration %d" % [pair, duration])
			var once := probe([[2, 1], [end, 3, mask], [end, 1], [end, 3, mask]], facing)
			check(once.actions.size() == 2 and once.actions[0].type == "motion" and once.actions[1].type == "normal",
				"a completed motion cannot be reused by a second attack")
			var again := probe([[2, 1], [end, 3, mask], [5, 1], [2, 1], [end, 3, mask]], facing)
			check(again.actions.size() == 2 and again.actions[1].motion == pair[3],
				"a fresh quarter-circle does not combine with an already consumed motion into super")
	# The easier quarter-circles do not change DP or super timing.
	check(probe([[6, 20], [2, 1], [3, 3, Commands.A]]).actions[0].type == "normal", "DP retains its 20 tick sequence limit")
	check(probe([[6, 1], [2, 1], [3, 7], [3, 3, Commands.A]]).actions[0].type == "normal", "DP retains its 6 tick button limit")

func _early_attacks() -> void:
	for facing in [-1, 1]:
		for pair in [[6, 3, Commands.A, "236"], [6, 3, Commands.C, "236"], [4, 1, Commands.B, "214"], [4, 1, Commands.D, "214"]]:
			for lead in [1, 2, 3]:
				var p := probe([[2, 1], [pair[1], lead, pair[2]], [pair[0], 4, pair[2]]], facing)
				check(p.actions.size() == 1 and p.actions[0].type == ("motion" if lead <= 2 else "normal"),
					"early attack 2/3 tick boundary emits one action: %s lead %d" % [pair, lead])
				check(p.actions[0].emitted == 4, "early completion adds no delay beyond the existing chord wait")
			var omitted := probe([[2, 1, pair[2]], [pair[0], 3, pair[2]]], facing)
			check(omitted.actions.size() == 1 and omitted.actions[0].motion == pair[3], "early attack works with omitted diagonal")
			var incomplete := probe([[2, 1], [pair[1], 5, pair[2]]], facing)
			check(incomplete.actions.size() == 1 and incomplete.actions[0].type == "normal", "held diagonal alone remains a crouching normal")
		for digit in [2, 5, 6]:
			var ordinary := probe([[digit, 7, Commands.A]], facing)
			check(ordinary.actions.size() == 1 and ordinary.actions[0].type == "normal" and ordinary.actions[0].emitted == 3,
				"ordinary attack timing and long-hold behavior are unchanged")
		var dp := probe([[6, 1], [2, 1], [3, 1, Commands.A], [6, 3, Commands.A]], facing)
		check(dp.actions[0].motion == "623", "DP priority survives early attack and final forward")
		for mask in [Commands.A, Commands.A | Commands.C]:
			var super_move := probe([[2, 1], [3, 1], [6, 1], [2, 1], [3, 1, mask], [6, 3, mask]], facing)
			check(super_move.actions.size() == 1 and super_move.actions[0].motion == "236236" and
				super_move.actions[0].type == ("max" if mask == 5 else "motion"), "early final attack upgrades overlapping DP to super/MAX")
		var roll := probe([[2, 1], [3, 1, Commands.A], [6, 3, Commands.A | Commands.B]], facing)
		check(roll.actions.size() == 1 and roll.actions[0].type == "roll", "roll chord still wins over an early quarter-circle")
		var crossed := Commands.new()
		crossed.last_facing = facing
		crossed.sample(s.relative(2, facing), facing)
		crossed.sample(s.relative(3, facing, Commands.A), facing)
		crossed.sample(s.relative(6, -facing, Commands.A), -facing)
		check(crossed.sample(s.relative(6, -facing, Commands.A), -facing).action.type == "normal", "cross-up cannot complete a pending early motion")

func _feedback() -> void:
	for pair in [[6, 3, Commands.A], [4, 1, Commands.B]]:
		for attempt in [
			[[[2, 1], [pair[1], 3, pair[2]]], "release_down"],
			[[[2, 1], [pair[1], 31], [pair[0], 3, pair[2]]], "motion_timeout"],
			[[[2, 1], [pair[0], 13], [pair[0], 3, pair[2]]], "attack_late"]]:
			var p := probe(attempt[0])
			check(p.reader.feedback == attempt[1], "practice diagnoses " + attempt[1])
			check(p.reader.snapshot().feedback == attempt[1] and p.reader.snapshot().feedback_until > p.reader.tick, "diagnostic state is deterministic")
			for n in range(Commands.FEEDBACK_DURATION):
				p.reader.sample({}, 1)
			check(p.reader.feedback.is_empty(), "diagnostic expires after three logical seconds")
	var wrong := probe([[2, 1], [6, 3, Commands.B]])
	check(wrong.reader.feedback == "wrong_button", "wrong attack family receives a practice hint")
	var ordinary := probe([[2, 5, Commands.A]])
	check(ordinary.reader.feedback.is_empty(), "plain crouching normal is not diagnosed as a failed motion")
	var pending := Commands.new()
	pending.sample(s.relative(2, 1), 1)
	pending.sample(s.relative(3, 1, Commands.A), 1)
	pending.reset({"buttons": Commands.A})
	for n in range(5):
		check(pending.sample(s.relative(6, 1, Commands.A), 1).action.is_empty(), "pause/device reset clears early action and suppresses held key")
	check(pending.feedback.is_empty() and pending.pending.is_empty(), "reset clears diagnostic and pending recognition")

func _device_motions() -> void:
	var router := Router.new()
	for device in ["keyboard:0", "keyboard:1", "pad:0"]:
		for facing in [-1, 1]:
			for character in ["tanjiro", "zenitsu"]:
				for pair in [[6, Commands.A, "236A"], [6, Commands.C, "236C"], [4, Commands.B, "214B"], [4, Commands.D, "214D"]]:
					var model := s.duel(character, facing)
					model.fighters[1].x = model.fighters[0].x + facing * 180
					for part in [[2, 90, 0], [5, 4, 0], [pair[0], 10, 0], [pair[0], 3, pair[1]]]:
						for n in range(part[1]):
							var held := s.relative(part[0], facing, part[2])
							s.tick(model, _from_device(router, device, held))
					check(model.fighters[0].move != null and model.fighters[0].move.id == character + "_" + pair[2],
						"actual slow device motion starts expected character move: %s %s facing %d %s" % [device, character, facing, pair[2]])
					_from_device(router, device, Combat.neutral())

func _from_device(router: RefCounted, device: String, held: Dictionary) -> Dictionary:
	if device.begins_with("keyboard:"):
		var slot := int(device.get_slice(":", 1))
		var flags: Array = [held.x < 0, held.x > 0, held.y > 0, held.y < 0]
		for n in range(4):
			flags.append((int(held.buttons) & (1 << n)) != 0)
		for n in range(flags.size()):
			var event := InputEventKey.new()
			event.physical_keycode = Router.KEYS[slot][n]
			event.pressed = flags[n]
			Input.parse_input_event(event)
		Input.flush_buffered_events()
		return router.sample(device)
	return router.pad_held(float(held.x), float(held.y), {JOY_BUTTON_X: (held.buttons & 1) != 0,
		JOY_BUTTON_A: (held.buttons & 2) != 0, JOY_BUTTON_Y: (held.buttons & 4) != 0, JOY_BUTTON_B: (held.buttons & 8) != 0})


func _early_in_combat() -> void:
	for facing in [-1, 1]:
		for character in ["tanjiro", "zenitsu"]:
			for pair in [[6, 3, Commands.A, "236A"], [4, 1, Commands.B, "214B"]]:
				var model := s.duel(character, facing)
				model.hitstop = 10
				s.tick(model, s.relative(2, facing))
				s.advance(model, 2, s.relative(pair[1], facing, pair[2]))
				s.tick(model, s.relative(pair[0], facing, pair[2]))
				check(model.fighters[0].buffer_action.get("type", "") == "motion", "early attack completes its motion during hitstop")
				s.advance(model, 7)
				check(model.fighters[0].move != null and model.fighters[0].move.id == character + "_" + pair[3], "buffered early special starts when hitstop ends")
			var poor := s.duel(character, facing)
			for digit in [2, 3, 6, 2]:
				s.tick(poor, s.relative(digit, facing))
			s.tick(poor, s.relative(3, facing, Commands.A | Commands.C))
			s.advance(poor, 3, s.relative(6, facing, Commands.A | Commands.C))
			check(poor.fighters[0].move == null and poor.fighters[0].meter == 0, "early MAX recognition cannot fall back when meter is insufficient")
			check(s.events.any(func(event: Dictionary) -> bool: return event.type == "meter_empty"), "insufficient early MAX emits the usual resource feedback")
