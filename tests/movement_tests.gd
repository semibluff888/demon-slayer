extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const Router = preload("res://scripts/input_router.gd")
const Camera = preload("res://scripts/presentation/duel_camera.gd")
var passed: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_input()
	_test_dash()
	_test_bounds()
	_test_flip()
	_test_throw()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("MOVEMENT TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(message)

func command(values: Dictionary = {}) -> Dictionary:
	var result := Combat.neutral()
	result.merge(values, true)
	return result

func duel(x1: float = 380, x2: float = 620) -> Combat:
	var model := Combat.new()
	model.phase = "fight"
	for i in range(2):
		model.fighters[i].x = x1 if i == 0 else x2
		model.fighters[i].previous_x = model.fighters[i].x
	return model

func advance(model: Combat, count: int, a: Dictionary = {}, b: Dictionary = {}) -> void:
	for i in range(count):
		model.step([command(a), command(b)])

func _test_input() -> void:
	for direction in [-1, 1]:
		var router := Router.new()
		check(router.command_from_held(0, command({"x": direction})).dash == 0, "first tap walks")
		router.command_from_held(0, command())
		check(router.command_from_held(0, command({"x": direction})).dash == direction, "second independent tap dashes in world direction")
		for i in range(30):
			check(router.command_from_held(0, command({"x": direction})).dash == 0, "holding never retriggers")
		router.command_from_held(0, command())
		check(router.command_from_held(0, command({"x": direction})).dash == 0, "expired tap cannot dash")
	var router := Router.new()
	router.command_from_held(0, command({"x": 1}))
	for i in range(11):
		router.command_from_held(0, command())
	check(router.command_from_held(0, command({"x": 1})).dash == 1, "inclusive twelve sample window")
	router = Router.new()
	router.command_from_held(0, command({"x": 1}))
	for i in range(12):
		router.command_from_held(0, command())
	check(router.command_from_held(0, command({"x": 1})).dash == 0, "thirteen sample window expires")
	router.command_from_held(0, command({"x": 0, "direction_conflict": true}))
	check(router.command_from_held(0, command({"x": 1})).dash == 0, "opposing directions invalidate pending tap")
	router.command_from_held(0, command())
	router.reset(["keyboard:0", "keyboard:1"])
	check(router.command_from_held(0, command({"x": 1})).dash == 0, "pause/device reset clears taps")
	router = Router.new()
	router.command_from_held(0, router.pad_held(0.8, 0, {}))
	for axis in [0.36, 0.28, 0.42, 0.31, 0.8]:
		check(router.command_from_held(0, router.pad_held(axis, 0, {})).dash == 0, "stick threshold jitter is not a release")
	router.command_from_held(0, router.pad_held(0.0, 0, {}))
	check(router.command_from_held(0, router.pad_held(0.8, 0, {})).dash == 1, "stick neutral and second deflection dashes")
	router = Router.new()
	router.command_from_held(1, router.pad_held(0, 0, {JOY_BUTTON_DPAD_LEFT: true}))
	router.command_from_held(1, router.pad_held(0, 0, {}))
	check(router.command_from_held(1, router.pad_held(0, 0, {JOY_BUTTON_DPAD_LEFT: true})).dash == -1, "dpad uses the same tap rule")

func _test_dash() -> void:
	for facing in [-1, 1]:
		for backward in [false, true]:
			var model := duel(500, 260 if facing < 0 else 740)
			var direction: int = -facing if backward else facing
			var duration: int = Arena.DASH_BACK_TICKS if backward else Arena.DASH_FORWARD_TICKS
			var speed: float = Arena.DASH_BACK_SPEED if backward else Arena.DASH_FORWARD_SPEED
			model.step([command({"x": direction, "dash": direction}), command()])
			advance(model, duration - 1)
			check(is_equal_approx(model.fighters[0].x, 500 + direction * duration * speed), "dash has exact fixed duration and distance in both facings")
			advance(model, 3)
			check(model.fighters[0].state == "idle", "released dash returns to idle")
	for cancel in [{"light": true}, {"jump": true}, {"down": true}, {"x": -1}]:
		var model := duel()
		model.step([command({"dash": 1, "x": 1}), command()])
		model.step([command(cancel), command()])
		check(model.fighters[0].dash_ticks == 0, "attack/jump/crouch/reverse immediately cancels dash")
	var model := duel(380, 420)
	model.step([command({"dash": -1, "x": -1}), command({"light": true})])
	# Put attacker into range on its active frame without changing the dash state.
	model.fighters[1].x = model.fighters[0].x + 30
	model.fighters[1].move_frame = model.moves.stand_light.startup
	model.step([command({"x": -1}), command()])
	check(model.fighters[0].hp == 955 and model.fighters[0].dash_ticks == 0, "back dash has no invulnerability or automatic guard")
	model = duel(380, 412)
	model.step([command({"dash": 1}), command()])
	advance(model, 4)
	check(model.fighters[0].dash_ticks == 0 and model.fighters[1].x - model.fighters[0].x >= 25.99, "body collision stops dash")
	model = duel(Arena.LEFT + 1, Arena.LEFT + 150)
	model.step([command({"dash": -1}), command()])
	check(model.fighters[0].x == Arena.LEFT and model.fighters[0].dash_ticks == 0, "stage wall stops dash")

func _test_bounds() -> void:
	var model := duel(400, 610)
	advance(model, 180, {}, {"x": 1})
	check(is_equal_approx(model.fighters[0].x, 400), "one player retreating never drags stationary opponent")
	check(is_equal_approx(model.fighters[1].x - 400, Arena.MAX_SEPARATION), "screen distance limit blocks outward movement")
	model = duel(400, 770)
	var midpoint: float = (model.fighters[0].x + model.fighters[1].x) * 0.5
	model.step([command({"dash": -1}), command({"dash": 1})])
	check(absf(model.fighters[1].x - model.fighters[0].x) <= Arena.MAX_SEPARATION + 0.001, "simultaneous outward dashes stay visible")
	check(is_equal_approx((model.fighters[0].x + model.fighters[1].x) * 0.5, midpoint), "simultaneous limited retreat clips symmetrically")
	model = duel(300, 480)
	advance(model, 250, {"x": 1}, {"x": 1})
	check(model.fighters[1].x == Arena.RIGHT and model.fighters[0].x <= Arena.RIGHT - 26, "both can traverse the expanded stage to right corner")
	for mechanism in ["jump", "skill", "knockback"]:
		model = duel(400, 400 + Arena.MAX_SEPARATION)
		model.fighters[1].character = "zenitsu"
		if mechanism == "jump":
			model.step([command(), command({"x": 1, "jump": true})])
		elif mechanism == "skill":
			model.fighters[1].move = model.moves.thunder
			model.fighters[1].move_frame = model.moves.thunder.startup
			model.fighters[1].facing = 1
			model.step([command(), command()])
		else:
			model.fighters[1].state = "hit"
			model.fighters[1].stun = 12
			model.fighters[1].vx = 6
			model.step([command(), command()])
		check(is_equal_approx(model.fighters[0].x, 400), mechanism + " boundary leaves stationary opponent alone")
		check(absf(model.fighters[1].x - model.fighters[0].x) <= Arena.MAX_SEPARATION + 0.001, mechanism + " obeys maximum separation")
	var camera := Camera.new()
	for positions in [[28,54], [906,932], [400,770], [594,366]]:
		model = duel(positions[0], positions[1])
		camera.reset(model.fighters)
		camera.update(model.fighters, 1.0 / 144, [Rect2(-200,-150,400,150)])
		check(camera.zoom == 3.0, "distance and oversized effects never change scale")
		for f in model.fighters:
			check(camera.point(Vector2(f.x,286)).x >= 83.99 and camera.point(Vector2(f.x,286)).x <= 1196.01, "bodies remain within visible horizontal bounds")

func _test_flip() -> void:
	var model := duel(400, 450)
	model.step([command({"jump": true, "x": 1}), command()])
	check(model.fighters[0].flip_jump and model.fighters[0].jump_facing == 1, "jump records immutable flip direction")
	advance(model, 23)
	check(model.fighters[0].facing == -1 and model.fighters[0].jump_facing == 1, "cross-up changes combat facing but not flip orientation")
	model.step([command({"light": true}), command()])
	check(model.fighters[0].move.id == "air_light" and model.fighters[0].air_used_move, "air attack interrupts somersault")
	advance(model, 35)
	check(model.fighters[0].grounded and not model.fighters[0].flip_jump, "landing clears flip state")
	model = duel()
	model.step([command({"jump": true, "x": -1}), command()])
	check(model.fighters[0].jump_back, "back jump selects backflip")

func _test_throw() -> void:
	for pair in [["tanjiro","zenitsu"], ["zenitsu","tanjiro"], ["tanjiro","tanjiro"], ["zenitsu","zenitsu"]]:
		for placement in [[400,430], [430,400], [28,58], [58,28], [902,932], [932,902]]:
			var model := duel(placement[0], placement[1])
			model.fighters[0].character = pair[0]
			model.fighters[1].character = pair[1]
			var sign_before := signf(model.fighters[1].x - model.fighters[0].x)
			model.step([command({"throw": true}), command()])
			advance(model, 5)
			check(not model.throw_link.is_empty(), "near grounded target is grabbed")
			check(model.fighters[1].hp == 1000, "grab does not damage before impact")
			advance(model, 19)
			check(model.fighters[1].hp == 1000, "damage waits through lift and rotation")
			advance(model, 1)
			check(model.fighters[1].hp == 900 and model.hitstop == 7, "twentieth throw frame deals damage exactly once")
			var frozen := model.snapshot()
			advance(model, 1)
			check(model.fighters[1].x == frozen.fighters[1][1] and model.fighters[1].throw_frame == 20, "throw hitstop freezes linked motion")
			advance(model, 50)
			check(signf(model.fighters[1].x - model.fighters[0].x) == -sign_before, "back throw swaps sides")
			check(model.fighters[1].hp == 900 and model.throw_link.is_empty(), "linked throw releases cleanly without duplicate damage")
			check(minf(model.fighters[0].x,model.fighters[1].x) >= Arena.LEFT and maxf(model.fighters[0].x,model.fighters[1].x) <= Arena.RIGHT, "corner throw keeps both bodies in stage")
	var model := duel(400,430)
	model.step([command({"throw": true}), command({"throw": true})])
	advance(model, 8)
	check(model.throw_link.is_empty() and model.fighters[0].hp == 1000 and model.fighters[1].hp == 1000, "simultaneous throws still clash")
	for attacker in [0,1]:
		model = duel(400,430)
		model.fighters[attacker].move = model.moves.throw
		model.fighters[attacker].move_frame = model.moves.throw.startup
		model.fighters[1-attacker].move = model.moves.stand_light
		model.fighters[1-attacker].move_frame = model.moves.stand_light.startup
		model.step([command(),command()])
		check(model.throw_link.is_empty() and model.fighters[attacker].hp == 955, "same-frame strike interrupts throw regardless of player slot")
	for lethal in [false,true]:
		model = duel(400,430)
		model.fighters[1].hp = 100 if lethal else 1000
		model.step([command({"throw": true}),command()])
		advance(model,5)
		model.remaining = 1
		advance(model,3)
		check(model.phase == "fight" and not model.throw_link.is_empty(), "timeout waits for active throw")
		advance(model,45)
		check(model.phase == "round_end" and model.round_winner == 0, "timeout/lethal throw settles before round award")
	model = duel(400,430)
	model.step([command({"throw": true}),command({"jump":true})])
	advance(model,8)
	check(model.throw_link.is_empty() and model.fighters[1].hp == 1000, "jump evades grounded grab")
	model = duel(400,430)
	model.step([command({"throw":true}),command()])
	advance(model,8)
	model.start_round()
	check(model.throw_link.is_empty() and model.fighters[0].throw_role.is_empty() and model.fighters[0].dash_ticks == 0, "round reset clears linked motion")
