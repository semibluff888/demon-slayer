extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Router = preload("res://scripts/input_router.gd")
const AI = preload("res://scripts/ai_controller.gd")
var passed: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_resources_and_movement()
	_hits_blocks_and_throws()
	_buffer_and_combos()
	_trades_and_rounds()
	_inputs_and_ai()
	_full_matches()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("COMBAT TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(message)

func command(values: Dictionary = {}) -> Dictionary:
	var result := Combat.neutral()
	result.merge(values, true)
	return result

func duel(x1: float = 260, x2: float = 300) -> Combat:
	var model := Combat.new()
	model.phase = "fight"
	model.fighters[0].x = x1
	model.fighters[1].x = x2
	return model

func advance(model: Combat, count: int, a: Dictionary = {}, b: Dictionary = {}) -> void:
	for tick in range(count):
		model.step([command(a), command(b)])

func attack(model: Combat, input: Dictionary, defender: Dictionary = {}, count: int = 35) -> void:
	model.step([command(input), command(defender)])
	advance(model, count, {}, defender)

func _resources_and_movement() -> void:
	var model := duel()
	check(model.moves.size() == 11, "all eleven moves load")
	for move in model.moves.values():
		check(move.active > 0 and move.startup > 0 and move.recovery > 0 and move.box.has_area(), "valid move: " + move.id)
	advance(model, 90, {"x": 1}, {"x": -1})
	check(model.fighters[1].x - model.fighters[0].x >= 25.99, "grounded bodies cannot overlap")
	model = duel(28, 54)
	advance(model, 90, {"x": -1}, {"x": -1})
	check(model.fighters[0].x >= 28 and model.fighters[1].x >= 54, "left corner conserves push separation")
	model = duel(906, 932)
	advance(model, 90, {"x": 1}, {"x": 1})
	check(model.fighters[1].x <= 932 and model.fighters[0].x <= 906, "right corner conserves push separation")
	model = duel(260, 302)
	model.step([command({"jump": true, "x": 1}), command()])
	var crossed := false
	var minimum_y: float = model.fighters[0].y
	for n in range(55):
		model.step([command({"x": 1, "jump": n == 7}), command()])
		minimum_y = minf(minimum_y, model.fighters[0].y)
		if model.fighters[0].x > model.fighters[1].x:
			crossed = true
	check(crossed and model.fighters[0].facing == -1 and model.fighters[1].facing == 1, "jump crosses opponent and flips both facings")
	check(model.fighters[0].grounded and minimum_y > 210, "single jump cannot double jump")
	print("PASS movement / data")

func _hits_blocks_and_throws() -> void:
	var model := duel()
	attack(model, {"light": true}, {}, 60)
	check(model.fighters[1].hp == 955, "one light attack deals damage exactly once")
	model = duel(895, 932)
	attack(model, {"light": true}, {"x": 1})
	check(model.fighters[1].hp == 1000, "standing back blocks mid")
	model = duel(895, 932)
	attack(model, {"light": true}, {"x": 1, "down": true})
	check(model.fighters[1].hp == 1000, "crouch back blocks mid")
	model = duel(895, 932)
	attack(model, {"light": true, "down": true}, {"x": 1})
	check(model.fighters[1].hp == 960, "standing guard loses to low")
	model = duel(895, 932)
	attack(model, {"light": true, "down": true}, {"x": 1, "down": true})
	check(model.fighters[1].hp == 1000, "crouch guard blocks low")
	for duck in [false, true]:
		model = duel(895, 932)
		model.fighters[0].grounded = false
		model.fighters[0].y = 245
		attack(model, {"heavy": true}, {"x": 1, "down": duck})
		check(model.fighters[1].hp == (920 if duck else 1000), "air heavy requires standing guard: %s" % duck)
	model = duel(900, 932)
	attack(model, {"throw": true}, {"x": 1})
	check(model.fighters[1].hp == 900, "throw defeats grounded guard")
	model = duel(900, 932)
	model.step([command({"throw": true}), command({"jump": true})])
	advance(model, 15)
	check(model.fighters[1].hp == 1000 and model.fighters[0].move != null, "jump evades throw and whiff has recovery")
	model = duel(895, 932)
	model.fighters[1].hp = 1
	attack(model, {"skill": true}, {"x": 1})
	check(model.fighters[1].hp == 1, "special chip cannot defeat a blocking opponent")
	model = duel(300, 260)
	attack(model, {"skill": true, "x": -1}, {}, 1)
	check(model.fighters[0].move.id == "water_wheel", "forward skill is relative to facing left")
	print("PASS hits / guards / throws")

func _buffer_and_combos() -> void:
	var model := duel()
	model.step([command({"light": true}), command()])
	for tick in range(25):
		model.step([command(), command()])
		if model.fighters[1].hp < 1000:
			break
	check(model.hitstop > 0, "contact starts hitstop")
	var frozen: float = model.fighters[1].x
	model.step([command({"heavy": true}), command()])
	check(model.fighters[1].x == frozen, "hitstop freezes motion while accepting input")
	var heavy_seen := false
	var skill_queued := false
	for tick in range(110):
		var c := command()
		if model.fighters[0].move != null and model.fighters[0].move.id == "stand_heavy":
			heavy_seen = true
			if model.fighters[0].connected and not skill_queued:
				c.skill = true
				skill_queued = true
		model.step([c, command()])
	check(heavy_seen and skill_queued and model.fighters[1].hp == 765, "light-heavy-skill chain connects for 235 damage")
	check(model.fighters[0].combo == 3, "chain is counted as three hits")
	model = duel(150, 500)
	model.step([command({"light": true}), command()])
	advance(model, 6)
	model.step([command({"heavy": true}), command()])
	advance(model, 7)
	check(model.fighters[0].move.id == "stand_light", "whiffed normal cannot cancel")
	advance(model, 35)
	check(model.fighters[0].move == null, "expired command cannot fire after recovery")
	model = duel()
	model.fighters[0].stun = 3
	model.fighters[0].state = "hit"
	model.step([command({"light": true}), command()])
	advance(model, 3)
	check(model.fighters[0].move != null, "six-frame buffer carries input out of hitstun")
	model = duel(895, 932)
	model.step([command({"light": true}), command({"x": 1})])
	for tick in range(30):
		model.step([command(), command({"x": 1})])
		if model.fighters[0].connected:
			break
	model.step([command({"heavy": true}), command({"x": 1})])
	advance(model, 7, {}, {"x": 1})
	check(model.fighters[0].move != null and model.fighters[0].move.id == "stand_heavy", "blocked contact enables chain cancel")
	print("PASS buffers / combos")

func _trades_and_rounds() -> void:
	var model := duel()
	model.step([command({"light": true}), command({"light": true})])
	advance(model, 8)
	check(model.fighters[0].hp == 955 and model.fighters[1].hp == 955, "same-frame strikes trade symmetrically")
	model = duel(280, 310)
	model.step([command({"throw": true}), command({"throw": true})])
	advance(model, 8)
	check(model.fighters[0].hp == 1000 and model.fighters[1].hp == 1000, "simultaneous throws clash")
	model = duel()
	model.fighters[0].hp = 45
	model.fighters[1].hp = 45
	model.step([command({"light": true}), command({"light": true})])
	advance(model, 8)
	check(model.phase == "round_end" and model.reason == "DOUBLE K.O." and model.wins == [0, 0], "double KO awards no round")
	advance(model, 220)
	check(model.round_number == 1 and model.fighters[0].hp == 1000 and model.fighters[1].hp == 1000, "draw replays same round at full health")
	model = duel()
	model.remaining = 1
	model.fighters[0].hp = 500
	model.fighters[1].hp = 700
	advance(model, 1)
	check(model.reason == "TIME UP" and model.wins == [0, 1], "timeout awards higher remaining health")
	model = duel()
	model.remaining = 1
	advance(model, 1)
	check(model.reason == "DRAW" and model.wins == [0, 0], "equal health timeout is a draw")
	model = duel()
	for round_index in range(2):
		model.phase = "fight"
		model.fighters[1].hp = 0
		advance(model, 1)
		advance(model, 125)
	check(model.phase == "match_end" and model.match_winner == 0 and model.wins == [2, 0], "first to two rounds wins match")
	model.fighters[0].buffer_left = 6
	model.fighters[0].move = model.moves.thunder
	model.new_match("zenitsu", "zenitsu")
	check(model.wins == [0, 0] and model.remaining == 3600 and model.phase == "intro" and model.hitstop == 0, "rematch resets scores, timer, phase and hitstop")
	check(model.fighters[0].move == null and model.fighters[0].buffer_left == 0 and model.fighters[0].x == 366, "rematch clears movement and pending attacks")
	check(model.fighters[0].character == "zenitsu" and model.fighters[1].character == "zenitsu", "mirror matches retain selected characters")
	print("PASS trades / rounds / resets")

func _inputs_and_ai() -> void:
	var router := Router.new()
	var held := command({"light": true, "jump": true, "x": 1})
	var first := router.command_from_held(0, held)
	var second := router.command_from_held(0, held)
	check(first.light and first.jump and not second.light and not second.jump and second.x == 1, "buttons are edges; direction remains held")
	var pad := router.pad_held(0.1, -0.8, {JOY_BUTTON_X: true, JOY_BUTTON_A: true})
	check(pad.x == 0 and pad.jump and pad.light and pad.skill, "gamepad deadzone and face buttons map correctly")
	pad = router.pad_held(0.0, 0.0, {JOY_BUTTON_DPAD_LEFT: true, JOY_BUTTON_DPAD_DOWN: true, JOY_BUTTON_Y: true, JOY_BUTTON_B: true})
	check(pad.x == -1 and pad.down and pad.heavy and pad.throw, "gamepad d-pad and other face buttons map correctly")
	Input.action_press("p1_light")
	check(router.sample("keyboard:0").light and not router.sample("keyboard:1").light, "keyboard groups are isolated")
	router.reset(["keyboard:0", "keyboard:1"])
	check(not router.read(0, "keyboard:0").light, "screen transitions suppress already-held buttons")
	Input.action_release("p1_light")
	var physical := InputEventKey.new()
	physical.physical_keycode = KEY_F
	physical.keycode = KEY_F
	physical.pressed = true
	Input.parse_input_event(physical)
	Input.flush_buffered_events()
	check(router.sample("keyboard:0").light, "physical F key reaches the configured P1 light action")
	physical = physical.duplicate()
	physical.pressed = false
	Input.parse_input_event(physical)
	Input.flush_buffered_events()
	check(not router.sample("keyboard:0").light, "physical key release clears the action")
	check(not router.connected("pad:999"), "missing gamepad is detected")
	var model := duel()
	var ai := AI.new(22)
	for n in range(12):
		check(ai.command(model.fighters[1].observable(), model.fighters[0].observable()) == command(), "AI waits for reaction history")
	var ai2 := AI.new(22)
	ai.reset()
	for n in range(120):
		check(ai.command(model.fighters[1].observable(), model.fighters[0].observable()) == ai2.command(model.fighters[1].observable(), model.fighters[0].observable()), "AI decisions reproducible at tick %d" % n)
	# Drive an actual duel through keyboard input + simulated gamepad commands.
	model = duel()
	router = Router.new()
	Input.action_press("p1_light")
	model.step([router.read(0, "keyboard:0"), router.command_from_held(1, router.pad_held(0, 0, {JOY_BUTTON_X: true}))])
	Input.action_release("p1_light")
	advance(model, 8)
	check(model.fighters[0].hp == 955 and model.fighters[1].hp == 955, "keyboard and simulated gamepad can complete a simultaneous exchange")
	print("PASS keyboard / virtual gamepad / AI")

func _full_matches() -> void:
	for pair in [["tanjiro", "zenitsu"], ["zenitsu", "tanjiro"], ["tanjiro", "tanjiro"], ["zenitsu", "zenitsu"]]:
		var model := Combat.new()
		model.new_match(pair[0], pair[1])
		var a := AI.new(10)
		var b := AI.new(82)
		var ticks := 0
		while model.phase != "match_end" and ticks < 40000:
			model.step([a.command(model.fighters[0].observable(), model.fighters[1].observable()),
				b.command(model.fighters[1].observable(), model.fighters[0].observable())])
			ticks += 1
		check(model.phase == "match_end" and model.wins.max() == 2, "full match completes: %s/%s" % pair)
		print("MATCH %s vs %s: %s after %d ticks" % [pair[0], pair[1], model.wins, ticks])
