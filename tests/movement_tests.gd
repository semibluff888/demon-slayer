extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const Flow = preload("res://scripts/round_flow.gd")
const Commands = preload("res://scripts/command_recognizer.gd")
const Camera = preload("res://scripts/presentation/duel_camera.gd")
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
	_dash()
	_bounds()
	_jump()
	_throws()
	_rolls()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("MOVEMENT TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func duel(x1: float = 380, x2: float = 620) -> Combat:
	var model = s.duel("tanjiro", 1 if x2 > x1 else -1)
	model.fighters[0].x = x1
	model.fighters[1].x = x2
	for f in model.fighters:
		f.previous_x = f.x
	return model

func dash(model: Combat, direction: int) -> float:
	s.tick(model, {"x": direction})
	s.tick(model)
	var start: float = model.fighters[0].x
	s.tick(model, {"x": direction})
	return start

func _dash() -> void:
	for facing in [-1, 1]:
		for backward in [false, true]:
			var model := duel(500, 260 if facing < 0 else 740)
			var direction: int = -facing if backward else facing
			var duration: int = Arena.DASH_BACK_TICKS if backward else Arena.DASH_FORWARD_TICKS
			var speed: float = Arena.DASH_BACK_SPEED if backward else Arena.DASH_FORWARD_SPEED
			var start := dash(model, direction)
			s.advance(model, duration - 1)
			check(is_equal_approx(model.fighters[0].x, start + direction * duration * speed), "exact dash duration/distance in both facings")
			s.advance(model, 3)
			check(model.fighters[0].state == "idle", "released dash returns to idle")
	for cancel in [{"buttons": Commands.A}, {"y": -1}, {"y": 1}, {"x": -1}]:
		var model := duel()
		dash(model, 1)
		s.tick(model, cancel)
		s.advance(model, 2, cancel)
		check(model.fighters[0].dash_ticks == 0, "attack/jump/crouch/reverse cancels dash")
	var model := duel(380, 420)
	dash(model, -1)
	var attacker = model.fighters[1]
	attacker.x = model.fighters[0].x + 30
	model._begin_move(attacker, model.definition(attacker).normals["5A"])
	attacker.move_frame = attacker.move.startup
	s.tick(model, {"x": -1})
	check(model.fighters[0].hp == 955 and model.fighters[0].dash_ticks == 0, "back dash has no invulnerability or automatic guard")
	model = duel(380, 425)
	dash(model, 1)
	s.advance(model, 6)
	check(model.fighters[0].dash_ticks == 0 and model.fighters[1].x - model.fighters[0].x >= 25.99, "body collision stops dash")
	model = duel(Arena.LEFT + 5, Arena.LEFT + 150)
	dash(model, -1)
	s.advance(model, 5)
	check(model.fighters[0].x == Arena.LEFT and model.fighters[0].dash_ticks == 0, "stage wall stops dash")

func _bounds() -> void:
	var model := duel(400, 610)
	s.advance(model, 180, {}, {"x": 1})
	check(is_equal_approx(model.fighters[0].x, 400), "retreat never drags stationary opponent")
	check(is_equal_approx(model.fighters[1].x - 400, Arena.MAX_SEPARATION), "screen distance blocks outward motion")
	model = duel(300, 480)
	s.advance(model, 350, {"x": 1}, {"x": 1})
	check(model.fighters[1].x == Arena.RIGHT and model.fighters[0].x <= Arena.RIGHT - 26, "traversal reaches right corner")
	for mechanism in ["jump", "skill", "knockback", "roll"]:
		model = duel(400, 400 + Arena.MAX_SEPARATION)
		var f = model.fighters[1]
		if mechanism == "jump":
			s.tick(model, {}, {"x": 1, "y": -1})
		elif mechanism == "skill":
			model._begin_move(f, model.definition(f).motions["236A"])
			f.move = model.catalog.characters.zenitsu.motions["236A"]
			f.move_frame = f.move.startup
			f.facing = 1
			s.tick(model)
		elif mechanism == "roll":
			f.roll_frame = 4
			f.roll_direction = 1
			s.tick(model)
		else:
			f.state = "hit"
			f.stun = 12
			f.vx = 6
			s.tick(model)
		check(is_equal_approx(model.fighters[0].x, 400), mechanism + " boundary keeps stationary opponent fixed")
		check(absf(f.x - model.fighters[0].x) <= Arena.MAX_SEPARATION + 0.001, mechanism + " obeys maximum separation")
	var camera := Camera.new()
	for positions in [[28,54], [906,932], [400,770], [594,366]]:
		model = duel(positions[0], positions[1])
		camera.reset(model.fighters)
		camera.update(model.fighters, 1.0 / 144, [Rect2(-200,-150,400,150)])
		check(camera.zoom == 3.0, "effects do not change camera scale")
		for f in model.fighters:
			check(camera.point(Vector2(f.x,286)).x >= 83.99 and camera.point(Vector2(f.x,286)).x <= 1196.01, "bodies remain in visible bounds")

func _jump() -> void:
	var model := duel(400, 450)
	s.tick(model, {"y": -1, "x": 1})
	check(model.fighters[0].flip_jump and model.fighters[0].jump_facing == 1, "jump records takeoff orientation")
	s.advance(model, 23)
	check(model.fighters[0].facing == -1 and model.fighters[0].jump_facing == 1, "cross-up preserves flip orientation")
	s.input(model, "A")
	check(model.fighters[0].move != null and model.fighters[0].move.stance == "air", "air attack interrupts flip")
	s.advance(model, 50)
	check(model.fighters[0].grounded and not model.fighters[0].flip_jump, "landing clears flip")
	model = duel()
	s.tick(model, {"y": -1, "x": -1})
	check(model.fighters[0].jump_back, "backward jump uses backflip")

func wait_grab(model: Combat) -> bool:
	for n in range(20):
		if not model.throw_link.is_empty():
			return true
		s.tick(model)
	return false

func _throws() -> void:
	for pair in [["tanjiro","zenitsu"], ["zenitsu","tanjiro"], ["tanjiro","tanjiro"], ["zenitsu","zenitsu"]]:
		for placement in [[400,430], [430,400], [28,58], [58,28], [902,932], [932,902]]:
			for back in [false, true]:
				var model := duel(placement[0], placement[1])
				model.fighters[0].character = pair[0]
				model.fighters[1].character = pair[1]
				var before := signf(model.fighters[1].x - model.fighters[0].x)
				s.input(model, "4D" if back else "6D")
				check(wait_grab(model), "near direction+D grabs: %s %s %s" % [pair, placement, back])
				check(model.fighters[1].hp == 1000, "grab has no early damage")
				s.advance(model, 19)
				check(model.fighters[1].hp == 1000, "throw damage waits for impact")
				s.tick(model)
				check(model.fighters[1].hp == 900 and model.hitstop == 7, "throw impact deals 100 exactly once")
				var position: float = model.fighters[1].x
				s.tick(model)
				check(model.fighters[1].x == position and model.fighters[1].throw_frame == 20, "throw hitstop freezes linked pose")
				s.advance(model, 50)
				check(signf(model.fighters[1].x - model.fighters[0].x) == before * (-1 if back else 1), "forward/back throw preserves/swaps sides")
				check(model.fighters[1].hp == 900 and model.throw_link.is_empty(), "throw releases without duplicate damage")
				check(minf(model.fighters[0].x,model.fighters[1].x) >= Arena.LEFT and maxf(model.fighters[0].x,model.fighters[1].x) <= Arena.RIGHT, "corner throw is bounded")
	var model := duel(400,430)
	s.tick(model, {"x": 1, "buttons": Commands.D}, {"x": -1, "buttons": Commands.D})
	s.advance(model, 14)
	check(model.throw_link.is_empty() and model.fighters[0].hp == 1000 and model.fighters[1].hp == 1000, "simultaneous throws tech")
	for attacker in [0,1]:
		model = duel(400,430)
		var a = model.fighters[attacker]
		var b = model.fighters[1-attacker]
		model._begin_move(a, model.definition(a).throw_move)
		a.move_frame = a.move.startup
		model._begin_move(b, model.definition(b).normals["5A"])
		b.move_frame = b.move.startup
		s.tick(model)
		check(model.throw_link.is_empty() and a.hp == 955, "same-frame strike beats grab regardless of slot")
	for delay in [6, 7]:
		model = duel(400,430)
		s.input(model, "6D")
		wait_grab(model)
		s.advance(model, delay)
		s.tick(model, {}, {"buttons": Commands.D})
		check(model.throw_link.is_empty() == (delay == 6), "seven-frame tech boundary")
	for lethal in [false, true]:
		model = duel(400,430)
		model.fighters[1].hp = 100 if lethal else 1000
		s.input(model, "6D")
		wait_grab(model)
		model.remaining = 1
		s.advance(model, 3)
		check(model.phase == "fight" and not model.throw_link.is_empty(), "timeout waits for linked throw")
		for tick in range(Arena.THROW_TICKS + Flow.FREEZE + Flow.SLOW):
			if model.phase == "round_end": break
			s.tick(model)
		check(model.throw_link.is_empty() and model.phase == "round_end" and model.round_winner == 0, "timeout/lethal throw completes linked landing before score")
	model = duel(400,520)
	s.input(model, "6D")
	check(model.fighters[0].move.kind == "heavy", "far direction+D becomes normal")
	model = duel(400,430)
	s.input(model, "5D")
	check(model.fighters[0].move.kind == "heavy", "neutral D never becomes a throw")
	model = duel(400,430)
	model.fighters[1].state = "knockdown"
	model.fighters[1].stun = 1
	s.tick(model)
	check(model.fighters[1].throw_invulnerable == 8 and not model._throwable(model.fighters[1]), "wakeup grants eight ticks of throw immunity")
	s.advance(model, 7)
	check(not model._throwable(model.fighters[1]), "throw immunity includes its final tick")
	s.tick(model)
	check(model._throwable(model.fighters[1]), "wakeup throw immunity expires")
	model = duel(400,430)
	s.input(model, "6D")
	wait_grab(model)
	model.start_round()
	check(model.throw_link.is_empty() and model.fighters[0].throw_role.is_empty(), "round reset clears throw linkage")

func _rolls() -> void:
	for facing in [-1, 1]:
		var model := duel(480, 480 + facing * 50)
		s.input(model, "AB")
		var start: float = model.fighters[0].x
		s.advance(model, 28)
		check(is_equal_approx(model.fighters[0].x, start + facing * 88), "forward roll travels twenty moving ticks")
		check(signf(model.fighters[1].x - model.fighters[0].x) == -facing, "roll passes through body and changes sides")
		check(model.fighters[0].meter == 0 and model.fighters[0].roll_frame < 0, "roll completes without resource cost")
	for frame in [0, 5, 17, 23]:
		var model := duel(400,430)
		var victim = model.fighters[0]
		victim.state = "roll"
		victim.roll_frame = frame
		victim.roll_direction = 0
		var attacker = model.fighters[1]
		model._begin_move(attacker, model.definition(attacker).normals["5A"])
		attacker.move_frame = attacker.move.startup
		s.tick(model)
		check((victim.hp == 1000) == (frame == 5), "roll strike immunity interval/recovery: " + str(frame))
	var model := duel(400,430)
	var victim = model.fighters[1]
	victim.state = "roll"
	victim.roll_frame = 5
	victim.roll_direction = 0
	model._begin_move(model.fighters[0], model.definition(model.fighters[0]).throw_move)
	model.fighters[0].move_frame = model.fighters[0].move.startup
	s.tick(model)
	check(not model.throw_link.is_empty(), "strike-invulnerable roll remains throwable")
	model = duel()
	s.input(model, "AB")
	s.advance(model, 17)
	s.input(model, "5A")
	check(model.fighters[0].move == null and model.fighters[0].roll_frame >= 0, "roll recovery cannot attack cancel")
	model = duel(Arena.LEFT, Arena.LEFT + 80)
	s.input(model, "4AB")
	s.advance(model, 35)
	check(model.fighters[0].x == Arena.LEFT, "back roll obeys wall")
