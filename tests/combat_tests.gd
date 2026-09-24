extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Commands = preload("res://scripts/command_recognizer.gd")
const AI = preload("res://scripts/ai_controller.gd")
const Definition = preload("res://scripts/character_definition.gd")
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
	_resources()
	_guards()
	_meters()
	_projectiles()
	_cancels()
	_edge_cases()
	_rounds()
	_ai()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("COMBAT TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _resources() -> void:
	var model := Combat.new()
	for id in model.catalog.characters:
		var definition: Resource = model.catalog.characters[id]
		check(definition.normals.size() == 12 and definition.motions.size() == 8, "complete four-button roster: " + id)
		for move in definition.all_moves():
			check(move.startup > 0 and move.active > 0 and move.recovery > 0 and not move.clip_id().is_empty(), "valid frame data and visual mapping: " + move.id)
		for notation in ["5A","5B","5C","5D","2A","2B","2C","2D","236A","236C","623A","623C","214B","214D","236236A","236236AC"]:
			model = s.duel(id)
			model.fighters[0].meter = 300
			s.input(model, notation)
			s.advance(model, 160)
			check(model.fighters[1].hp < 1000, "real command hits: " + id + "/" + notation)
			check(model.fighters[0].move == null, "move completes: " + id + "/" + notation)
	# A third definition shares existing resources without any core character branch.
	var fixture := Definition.new()
	fixture.id = "fixture"
	fixture.normals = model.catalog.characters.tanjiro.normals
	fixture.motions = model.catalog.characters.tanjiro.motions
	fixture.throw_move = model.catalog.characters.tanjiro.throw_move
	fixture.walk_speed = 3.0
	model.catalog.register(fixture)
	model.new_match("fixture", "fixture")
	model.phase = "fight"
	var before: float = model.fighters[0].x
	s.tick(model, {"x": 1})
	check(model.fighters[0].x == before + 3, "new character consumes data-defined movement")
	s.input(model, "236A")
	check(model.fighters[0].move != null, "new character uses registered command table")

func _guards() -> void:
	for facing in [-1, 1]:
		for pair in [["5A", false, true], ["5A", true, true], ["2B", false, false], ["2B", true, true]]:
			var model = s.duel("tanjiro", facing)
			var guard := {"x": facing, "y": 1 if pair[1] else 0}
			s.input(model, pair[0], guard)
			s.advance(model, 45, {}, guard)
			check((model.fighters[1].hp == 1000) == pair[2], "standing/crouching guard " + str(pair) + " facing " + str(facing))
	var model = s.duel()
	s.input(model, "5A")
	s.advance(model, 90, {"buttons": Commands.A})
	check(model.fighters[1].hp == 955, "held attack and active frames cannot duplicate damage")
	model = s.duel()
	model.fighters[1].hp = 1
	s.input(model, "236A", {"x": 1})
	s.advance(model, 75, {}, {"x": 1})
	check(model.fighters[1].hp == 1 and model.phase == "fight", "special chip cannot KO")
	for crouch in [false, true]:
		model = s.duel()
		var f = model.fighters[0]
		f.grounded = false
		f.y -= 38
		f.vy = -1
		model._begin_move(f, model.definition(f).normals.jC)
		f.move_frame = f.move.startup
		s.tick(model, {}, {"x": 1, "y": 1 if crouch else 0})
		check((model.fighters[1].hp < 1000) == crouch, "jump attack requires standing guard")
	model = s.duel()
	s.input(model, "2D")
	s.wait_contact(model)
	check(model.fighters[1].state == "knockdown", "2D is a knockdown finisher")
	var hp: int = model.fighters[1].hp
	model._begin_move(model.fighters[0], model.definition(model.fighters[0]).normals["5C"])
	model.fighters[0].move_frame = model.fighters[0].move.startup
	model.hitstop = 0
	s.tick(model)
	check(model.fighters[1].hp == hp, "knocked down opponent cannot be hit again")

func _meters() -> void:
	var model = s.duel()
	s.input(model, "5A")
	s.wait_contact(model)
	check(model.fighters[0].meter == 11 and model.fighters[1].meter == 6, "meter derives from actual landed damage")
	model = s.duel()
	model.fighters[1].x += 230
	s.input(model, "5C")
	s.advance(model, 70)
	check(model.fighters[0].meter == 0, "whiff grants no meter")
	model = s.duel()
	s.input(model, "214B", {"x": 1})
	s.advance(model, 85, {}, {"x": 1})
	check(model.fighters[1].meter == 3 and model.fighters[0].meter == 0, "multi-hit block grants once per attack")
	for pair in [["236236A", 99, false, 99], ["236236A", 100, true, 0],
		["236236AC", 299, false, 299], ["236236AC", 300, true, 0]]:
		model = s.duel()
		model.fighters[0].meter = pair[1]
		s.input(model, pair[0])
		s.advance(model, 150)
		check((model.fighters[1].hp < 1000) == pair[2], "exact resource boundary: " + str(pair))
		check(model.fighters[0].meter == pair[3], "deduct once, never refund super, no downgrade: " + str(pair))
		if not pair[2]:
			check(model.fighters[0].last_move.is_empty(), "insufficient MAX does not cast a normal or cheaper special")
	model = s.duel()
	model.fighters[0].meter = 297
	s.input(model, "5A")
	s.wait_contact(model)
	check(model.fighters[0].meter == 300, "meter clamps at three stocks")
	model = s.duel()
	model.fighters[1].hp = 2
	s.input(model, "5C")
	s.advance(model, 15)
	check(model.fighters[0].meter == 0, "overkill does not farm meter")
	model = s.duel()
	model.fighters[0].meter = 300
	s.input(model, "236236A")
	check(model.super_freeze > 0, "super freeze belongs to simulation")
	var remaining: int = model.remaining
	var frame: int = model.fighters[0].move_frame
	s.tick(model)
	check(model.remaining == remaining and model.fighters[0].move_frame == frame, "super freeze pauses timer and motion")

func _projectiles() -> void:
	var model = s.duel()
	model.fighters[1].x += 125
	s.input(model, "236A")
	while model.projectiles.is_empty() and model.ticks < 30:
		s.tick(model)
	check(model.projectiles.size() == 1, "water slash spawns an independent projectile")
	model.fighters[0].move = null
	model.fighters[0].state = "hit"
	model.fighters[0].stun = 40
	s.advance(model, 55)
	check(model.fighters[1].hp < 1000 and model.projectiles.is_empty(), "already emitted projectile survives owner interruption and hits once")
	model = s.duel()
	model.fighters[1].character = "tanjiro"
	model.fighters[1].x += 100
	for f in model.fighters:
		model._begin_move(f, model.definition(f).motions["236A"])
	s.advance(model, 60)
	check(model.projectiles.is_empty() and model.fighters[0].hp == 1000 and model.fighters[1].hp == 1000, "opposing projectiles clash")
	model = s.duel()
	model.fighters[1].x += 280
	s.input(model, "236A")
	s.advance(model, 45)
	check(model.fighters[1].hp == 1000 and model.projectiles.is_empty(), "short-range projectile expires")
	model = s.duel("zenitsu")
	s.input(model, "236A")
	s.advance(model, 25)
	check(model.projectiles.is_empty(), "Zenitsu 236 remains a physical dash")
	for id in ["tanjiro", "zenitsu"]:
		model = s.duel(id)
		model.fighters[0].meter = 100
		s.input(model, "236236A")
		s.advance(model, 160)
		check(model.fighters[0].combo == (4 if id == "tanjiro" else 6), "super resolves every segment once: " + id)
		check(model.fighters[1].hp == 720, "raw multi-hit super sums to its authored damage")

func _cancels() -> void:
	var model = s.duel()
	model.fighters[1].x += 230
	s.input(model, "5A")
	s.input(model, "5C")
	check(model.fighters[0].move.id.ends_with("_5A"), "whiff cannot cancel")
	model = s.duel()
	s.input(model, "5A", {"x": 1})
	for n in range(18):
		if model.fighters[0].connected:
			break
		s.tick(model, {}, {"x": 1})
	s.input(model, "5C", {"x": 1})
	s.advance(model, 7, {}, {"x": 1})
	check(model.fighters[0].last_move.ends_with("_5C"), "normal block contact permits chain cancel")
	model = s.duel()
	s.input(model, "5A")
	s.wait_contact(model)
	s.input(model, "5A")
	s.advance(model, 9)
	check(model.fighters[0].attack_instance == 1, "same ground normal cannot repeat inside hitstun")
	model = s.duel()
	model.fighters[0].state = "hit"
	model.fighters[0].stun = 5
	s.input(model, "5A")
	s.advance(model, 4)
	check(model.fighters[0].move != null, "action buffer survives ending hitstun")
	model = s.duel()
	s.input(model, "5A")
	s.wait_contact(model)
	model.hitstop = 10
	s.input(model, "5C")
	s.advance(model, 12)
	check(model.fighters[0].last_move.ends_with("_5C"), "hitstop accepts buffered cancels without aging their execution window")
	# Artificial airborne dummy isolates the per-combo juggle limit from gravity.
	model = s.duel()
	var dummy = model.fighters[1]
	dummy.grounded = false
	dummy.y -= 25
	for n in range(4):
		var f = model.fighters[0]
		model._begin_move(f, model.definition(f).normals["5A"])
		f.move_frame = f.move.startup
		dummy.y = Combat.FLOOR_Y - 25
		dummy.vy = 0
		model.hitstop = 0
		s.tick(model)
	check(model.fighters[0].combo == 3, "airborne target accepts initial hit and only two extra attack instances")

func _rounds() -> void:
	var model = s.duel()
	s.tick(model, {"buttons": Commands.A}, {"buttons": Commands.A})
	s.advance(model, 12)
	check(model.fighters[0].hp == 955 and model.fighters[1].hp == 955, "same-frame strikes trade symmetrically")
	model = s.duel()
	for f in model.fighters:
		f.hp = 45
	s.tick(model, {"buttons": Commands.A}, {"buttons": Commands.A})
	s.advance(model, 12)
	check(model.reason == "DOUBLE K.O." and model.wins == [0,0], "double KO awards neither side")
	model = s.duel()
	model.round_open_meter.assign([70, 90])
	model.fighters[0].meter = 200
	model.fighters[1].meter = 250
	model.remaining = 1
	s.tick(model)
	s.advance(model, Combat.Flow.OUTRO)
	check(model.fighters[0].meter == 70 and model.fighters[1].meter == 90, "draw restores round-opening meter")
	model = s.duel()
	model.fighters[0].hp = 800
	model.fighters[1].hp = 500
	model.fighters[0].meter = 130
	model.fighters[1].meter = 190
	model.remaining = 1
	s.tick(model)
	check(model.round_winner == 0 and model.reason == "TIME UP", "timeout awards higher HP")
	s.advance(model, Combat.Flow.OUTRO)
	check(model.fighters[0].meter == 130 and model.fighters[1].meter == 190, "both sides carry meter between decisive rounds")
	model.phase = "fight"
	model.fighters[1].hp = 0
	s.tick(model)
	s.advance(model, Combat.Flow.OUTRO)
	check(model.phase == "match_end" and model.match_winner == 0, "first to two wins the match")
	model.new_match("zenitsu", "zenitsu")
	check(model.fighters[0].meter == 0 and model.projectiles.is_empty() and model.super_freeze == 0 and model.wins == [0,0], "new match clears resource and transient state")

func _ai() -> void:
	var model = s.duel()
	var a := AI.new(41)
	var b := AI.new(41)
	for n in range(160):
		var one := a.command(model.fighters[0].observable(), model.fighters[1].observable())
		var two := b.command(model.fighters[0].observable(), model.fighters[1].observable())
		check(one == two, "AI seed is reproducible")
		if n < 12:
			check(one == Combat.neutral(), "AI waits for observation history")
	for pair in [["tanjiro","zenitsu"], ["zenitsu","tanjiro"], ["tanjiro","tanjiro"], ["zenitsu","zenitsu"]]:
		model = Combat.new()
		model.new_match(pair[0], pair[1])
		a = AI.new(10)
		b = AI.new(82)
		var ticks := 0
		while model.phase != "match_end" and ticks < 40000:
			model.step([a.command(model.fighters[0].observable(), model.fighters[1].observable()),
				b.command(model.fighters[1].observable(), model.fighters[0].observable())])
			ticks += 1
		check(model.phase == "match_end" and model.wins.max() == 2, "complete AI match: " + str(pair))
		print("MATCH ", pair, " ", model.wins, " ticks=", ticks)



func _edge_cases() -> void:
	var model = s.duel()
	model.fighters[0].meter = 100
	s.input(model, "236A", {"x": 1})
	for n in range(40):
		if model.fighters[0].connected:
			break
		s.tick(model, {}, {"x": 1})
	s.input(model, "236236A", {"x": 1})
	s.advance(model, 50, {}, {"x": 1})
	check(model.fighters[0].meter == 100 and not model.fighters[0].last_move.ends_with("_super"), "blocked special cannot cancel into super")
	model = s.duel()
	model.fighters[0].meter = 100
	s.input(model, "5C")
	s.wait_contact(model)
	s.input(model, "236236A")
	check(s.wait_contact(model), "confirmed heavy can skip special and cancel directly to super")
	s.advance(model, 130)
	check(model.fighters[0].meter < 100 and model.fighters[0].last_move.ends_with("_super"), "direct normal-to-super spends resource")
	model = s.duel()
	model.fighters[1].x += 280
	s.input(model, "236C")
	while model.fighters[0].move != null:
		s.tick(model)
	check(model.projectiles.size() == 1, "heavy water blade can outlive its owner's recovery")
	var instance: int = model.next_instance
	s.input(model, "236A")
	s.advance(model, 3)
	check(model.projectiles.size() == 1 and model.next_instance == instance, "existing blade prevents a second projectile cast")
	model = s.duel()
	var a = model.fighters[0]
	var d = model.fighters[1]
	model._begin_move(a, model.definition(a).motions["236A"])
	model._spawn_projectile(a)
	var projectile: Dictionary = model.projectiles[0]
	projectile.x = d.x - projectile.vx
	d.roll_frame = 4
	d.roll_direction = 0
	d.state = "roll"
	s.tick(model)
	check(d.hp == 1000 and model.projectiles.size() == 1, "rolling through a projectile neither takes damage nor consumes it")
	# Mixed projectile/strike contact must trade regardless of owner slot.
	for owner in [0,1]:
		model = s.duel()
		a = model.fighters[owner]
		d = model.fighters[1-owner]
		a.character = "tanjiro"
		model._begin_move(a, model.definition(a).motions["236A"])
		model._spawn_projectile(a)
		projectile = model.projectiles[0]
		projectile.x = d.x - projectile.vx
		model._begin_move(d, model.definition(d).normals["5A"])
		d.move_frame = d.move.startup
		s.tick(model)
		check(a.hp == 955 and d.hp == 895, "projectile and normal trade in either player slot")
	model = s.duel()
	model.hitstop = 9
	s.input(model, "236236AC")
	check(not model.fighters[0].buffer_action.is_empty(), "motion can wait during hitstop")
	model.clear_inputs([{"buttons": 5}, Combat.neutral()])
	s.advance(model, 20, {"buttons": 5})
	check(model.fighters[0].move == null and model.fighters[0].buffer_action.is_empty(), "pause reset clears pending super and suppresses already-held chord")
	model = s.duel()
	model.fighters[0].meter = 300
	s.input(model, "236236AC")
	s.input(model, "5A")
	check(not model.fighters[0].buffer_action.is_empty(), "super freeze accepts the next input")
	model.remaining = 1
	model.super_freeze = 0
	s.tick(model)
	check(model.phase == "round_end" and model.projectiles.is_empty() and model.super_freeze == 0, "round end clears projectile and super-freeze state")
	check(model.fighters[0].buffer_action.is_empty() and model.fighters[0].input.directions.is_empty(), "round end clears queued input and directions")
