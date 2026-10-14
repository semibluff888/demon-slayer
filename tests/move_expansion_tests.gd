extends SceneTree
## Move-set expansion: target combos, command normals, air specials and air chains.
const Combat = preload("res://scripts/combat.gd")
const Move = preload("res://scripts/move_data.gd")
const Definition = preload("res://scripts/character_definition.gd")
const Support = preload("res://tests/combat_test_support.gd")
const Probe = preload("res://tests/frame_probe.gd")
const Verifier = preload("res://scripts/combat_verifier.gd")
var s := Support.new()
var passed := 0
var failures: Array[String] = []
var report: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(message)

func _initialize() -> void:
	_registration()
	_synthetic_rules()
	_target_combo()
	_command_normals()
	_air_specials()
	_air_chains()
	_frame_targets()
	_routes()
	_zenitsu()
	var file := FileAccess.open("res://artifacts/move-expansion.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	for failure in failures:
		printerr("FAIL: ", failure)
	print("MOVE EXPANSION TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _tanjiro(key: String) -> Move:
	return _move_of("tanjiro", key)

func _move_of(character: String, key: String) -> Move:
	var definition: Resource = Combat.new().catalog.characters[character]
	for table in ["normals", "motions", "command_normals", "air_motions"]:
		var entries: Dictionary = definition.get(table)
		if entries.has(key):
			return entries[key]
	for move in definition.all_moves():
		if move.id == key:
			return move
	return null

func _registration() -> void:
	var model := Combat.new()
	var tanjiro: Resource = model.catalog.characters.tanjiro
	var ids: Array[String] = []
	for move in tanjiro.all_moves():
		ids.append(move.id)
	for id in ["tanjiro_5AA", "tanjiro_5AAC", "tanjiro_6B", "tanjiro_6C", "tanjiro_j236A", "tanjiro_j236C", "tanjiro_j214B", "tanjiro_j214D"]:
		check(ids.count(id) == 1, "expansion move registered once: " + id)
		check(model.catalog.moves.has(id), "catalog knows expansion move: " + id)
	check(ids.size() == 29, "Tanjiro has 21 base and 8 expansion moves")
	check(ids.slice(0, 21) == ["tanjiro_5A", "tanjiro_5B", "tanjiro_5C", "tanjiro_5D", "tanjiro_2A", "tanjiro_2B", "tanjiro_2C", "tanjiro_2D",
		"tanjiro_jA", "tanjiro_jB", "tanjiro_jC", "tanjiro_jD", "tanjiro_236A", "tanjiro_236C", "tanjiro_623A", "tanjiro_623C",
		"tanjiro_214B", "tanjiro_214D", "tanjiro_super", "tanjiro_max", "tanjiro_throw"], "base moves keep their original order")
	check(tanjiro.normals.size() == 12 and tanjiro.motions.size() == 8, "base tables stay complete and unchanged in size")
	for id in ["nezuko", "akaza"]:
		var other: Resource = model.catalog.characters[id]
		check(other.all_moves().size() == 21 and other.command_normals.is_empty() and other.air_motions.is_empty(), "untouched roster: " + id)
	var manifest: Dictionary = JSON.parse_string(Verifier.resource_snapshot())
	check(str(manifest.tanjiro_5A.follow_ups).contains("tanjiro_5AA") and not str(manifest.tanjiro_5A.follow_ups).contains("Object"), "manifest records follow-ups by id")
	# A follow-up cycle must still terminate and register each move once.
	var a := Move.new()
	a.id = "cycle_a"
	var b := Move.new()
	b.id = "cycle_b"
	a.follow_ups = {"A": b}
	b.follow_ups = {"A": a}
	var fixture := Definition.new()
	fixture.normals = {"5A": a}
	check(fixture.all_moves().size() == 2, "follow-up cycles register each move once")
	a.follow_ups.clear() # Break the deliberate reference cycle so nothing leaks.

func _synthetic_rules() -> void:
	# Engine rules on a data-only fixture: velocity keyframes, gravity and landing recovery.
	var model := Probe.duel("tanjiro")
	var f = model.fighters[0]
	var dive := Move.new()
	dive.id = "fixture_dive"
	dive.kind = "skill"
	dive.stance = "air"
	dive.startup = 4
	dive.active = 30
	dive.recovery = 10
	dive.box = Rect2()
	dive.landing_recovery = 17
	dive.air_gravity_percent = 50
	dive.air_velocity_frames = PackedInt32Array([0, 4])
	dive.air_velocities = PackedVector2Array([Vector2(1, -2), Vector2(3, 6)])
	f.x = 300.0
	model.fighters[1].x = 700.0
	f.grounded = false
	f.state = "air"
	f.y = Combat.FLOOR_Y - 60
	f.vy = 0
	model._begin_move(f, dive)
	model.step([Combat.neutral(), Combat.neutral()])
	check(is_equal_approx(f.vx, 1.0) and is_equal_approx(f.vy, -2.0 + 0.21), "frame-0 velocity keyframe then half gravity")
	for n in range(4):
		model.step([Combat.neutral(), Combat.neutral()])
	check(is_equal_approx(f.vx, 3.0) and f.vy > 6.0, "later keyframe overrides velocity")
	for n in range(30):
		if f.grounded:
			break
		model.step([Combat.neutral(), Combat.neutral()])
	check(f.grounded and f.state == "landing" and f.stun == 17 and f.landing_move == "fixture_dive", "landing uses the move's landing recovery")
	check(f.air_chain.is_empty() and f.air_specials == 0, "landing clears air move bookkeeping")
	# Ordinary air normals keep the original five-tick landing.
	check(_tanjiro("jA").landing_recovery == 5 and _tanjiro("jA").air_gravity_percent == 100, "air normals keep default landing and gravity")

func _target_combo() -> void:
	for facing in [-1, 1]:
		var model = s.duel("tanjiro", facing)
		s.input(model, "5A")
		s.wait_contact(model)
		s.input(model, "5A")
		s.wait_contact(model)
		check(model.fighters[0].last_move == "tanjiro_5AA", "5A then A on hit reaches stage two, facing %d" % facing)
		s.input(model, "5C")
		s.wait_contact(model)
		check(model.fighters[0].last_move == "tanjiro_5AAC", "stage two then C reaches stage three, facing %d" % facing)
		# On block the string still continues.
		model = s.duel("tanjiro", facing)
		var guard := {"x": facing}
		s.input(model, "5A", guard)
		for n in range(12):
			if model.fighters[0].connected:
				break
			s.tick(model, {}, guard)
		s.input(model, "5A", guard)
		s.advance(model, 8, {}, guard)
		check(model.fighters[0].last_move == "tanjiro_5AA", "target combo continues on block, facing %d" % facing)
	# Never on whiff: far 5A then A repeats 5A after recovery.
	var model = s.duel()
	model.fighters[1].x = model.fighters[0].x + 140
	s.input(model, "5A")
	s.input(model, "5A")
	s.advance(model, 30)
	check(model.fighters[0].last_move != "tanjiro_5AA", "whiffed 5A cannot reach stage two")
	for pair in [["5C", "tanjiro_5C"], ["2A", "tanjiro_2A"], ["5B", "tanjiro_5B"]]:
		model = s.duel()
		s.input(model, "5A")
		s.wait_contact(model)
		s.input(model, pair[0])
		s.advance(model, 6)
		check(model.fighters[0].last_move == pair[1], "5A then %s keeps its original move" % pair[0])
	# The light-chain cap still applies: 2B -> 5A -> A would be a third light.
	model = s.duel()
	s.input(model, "2B")
	s.wait_contact(model)
	s.input(model, "5A")
	s.wait_contact(model)
	s.input(model, "5A")
	s.advance(model, 10)
	check(model.fighters[0].last_move == "tanjiro_5A", "third light in a chain is still rejected")

func _command_normals() -> void:
	for facing in [-1, 1]:
		# 6B is an overhead: it beats a crouching guard, a standing guard blocks it.
		for crouch in [true, false]:
			var model = s.duel("tanjiro", facing)
			var guard := {"x": facing, "y": 1 if crouch else 0}
			s.input(model, "6B", {"y": 1 if crouch else 0})
			_guard_until_contact(model, guard)
			s.advance(model, 40, {}, guard)
			check(model.fighters[0].last_move == "tanjiro_6B", "6B selects the headbutt, facing %d" % facing)
			check((model.fighters[1].hp < 1000) == crouch, "headbutt is an overhead (crouch=%s), facing %d" % [crouch, facing])
		var model = s.duel("tanjiro", facing)
		var stand := {"x": facing}
		s.input(model, "6B")
		_guard_until_contact(model, stand)
		check(model.fighters[0].connected and not model.fighters[0].confirmed, "standing guard blocks the headbutt, facing %d" % facing)
		s.input(model, "236A", stand)
		s.advance(model, 20, {}, stand)
		check(model.fighters[0].last_move == "tanjiro_6B", "blocked headbutt cannot cancel into a special, facing %d" % facing)
		model = s.duel("tanjiro", facing)
		model.fighters[1].x = model.fighters[0].x + facing * 100
		s.input(model, "6C")
		s.wait_contact(model)
		check(model.fighters[0].last_move == "tanjiro_6C" and model.fighters[1].hp == 954, "ripple thrust reaches 100 px, facing %d" % facing)
	var model = s.duel()
	for notation in ["236B", "2C", "5B"]:
		model = s.duel()
		s.input(model, notation)
		s.advance(model, 3)
		check(model.fighters[0].last_move == {"236B": "tanjiro_6B", "2C": "tanjiro_2C", "5B": "tanjiro_5B"}[notation], "fallback " + notation)
	model = s.duel()
	s.input(model, "4B")
	s.advance(model, 3)
	check(model.fighters[0].last_move == "tanjiro_5B", "back + B has no command normal and keeps 5B")
	model = s.duel()
	model.fighters[1].x = model.fighters[0].x + 30
	s.input(model, "6D")
	s.advance(model, 3)
	check(model.fighters[0].throw_role == "thrower" or not model.throw_link.is_empty() or model.fighters[0].last_move == "tanjiro_throw", "near 6D still throws")
	# A forward dash keeps the plain standing normal.
	model = s.duel()
	model.fighters[1].x = model.fighters[0].x + 200
	var f = model.fighters[0]
	f.dash_direction = 1
	f.dash_ticks = 10
	f.state = "dash"
	s.tick(model, {"x": 1, "buttons": 2})
	s.advance(model, 3, {"x": 1})
	check(f.last_move == "tanjiro_5B", "dash + B stays a standing normal")

## Holds neutral until the attack is about to become active, then guards.
func _guard_until_contact(model, guard: Dictionary) -> void:
	var f = model.fighters[0]
	for n in range(60):
		if f.connected or f.move == null:
			return
		s.tick(model, {}, guard if f.move_frame + 1 >= f.move.startup else {"y": int(guard.get("y", 0))})

func _jump(model) -> void:
	s.tick(model, {"y": -1})
	s.tick(model)

func _air_specials() -> void:
	for facing in [-1, 1]:
		var model = s.duel("tanjiro", facing)
		model.fighters[1].x = model.fighters[0].x + facing * 150
		_jump(model)
		s.advance(model, 10)
		s.input(model, "236A")
		var f = model.fighters[0]
		check(f.last_move == "tanjiro_j236A" and not f.grounded, "airborne 236A selects 泷壶, facing %d" % facing)
		s.input(model, "214B")
		check(f.last_move == "tanjiro_j236A", "one air special per jump, facing %d" % facing)
		for n in range(60):
			if f.grounded:
				break
			s.tick(model)
		check(f.state == "landing" and f.stun >= 17, "dive lands into its recovery, facing %d" % facing)
		# A late input near the floor gives the ground special after landing.
		model = s.duel("tanjiro", facing)
		model.fighters[1].x = model.fighters[0].x + facing * 150
		_jump(model)
		f = model.fighters[0]
		for n in range(60):
			if Combat.FLOOR_Y - f.y < 14 and f.vy > 0:
				break
			s.tick(model)
		s.input(model, "236A")
		s.advance(model, 4)
		check(f.last_move == "tanjiro_236A", "low air input buffers the ground 水面斩, facing %d" % facing)
	# Characters without air specials keep the original airborne behaviour.
	var model = s.duel("nezuko")
	model.fighters[1].x = model.fighters[0].x + 150
	_jump(model)
	s.advance(model, 10)
	s.input(model, "236A")
	check(model.fighters[0].move == null and not model.fighters[0].grounded, "Nezuko has no air special")
	# Juggled fighters cannot use an air special before landing.
	model = Probe.duel("tanjiro")
	var victim = model.fighters[0]
	victim.grounded = false
	victim.state = "air"
	victim.y = Combat.FLOOR_Y - 60
	var attacker = model.fighters[1]
	attacker.x = victim.x + 20
	model._resolve_contact(model._contact(attacker, victim, model.definition(attacker).normals["5A"], 77, 0, false))
	check(victim.air_specials == Combat.AIR_SPECIAL_LIMIT, "an air hit locks air specials until landing")
	# Air specials are high: a crouching guard cannot block them.
	for crouch in [true, false]:
		var sample: Dictionary = Probe.air("tanjiro", _tanjiro("j236A"), 18, "crouch" if crouch else "stand", 38)
		check(sample.contact == ("hit" if crouch else "block"), "泷壶 must be stand-blocked (crouch=%s, got %s)" % [crouch, sample.contact])

func _air_chains() -> void:
	var model := Probe.duel("tanjiro")
	var f = model.fighters[0]
	var d = model.fighters[1]
	f.x = 480.0
	d.x = 506.0
	d.grounded = false
	d.state = "air"
	d.y = Combat.FLOOR_Y - 40
	f.grounded = false
	f.state = "air"
	f.y = Combat.FLOOR_Y - 60
	f.vy = -3.0
	model._begin_move(f, _tanjiro("jA"))
	for n in range(12):
		if f.connected:
			break
		model.step([Combat.neutral(), Combat.neutral()])
	check(f.connected, "air-to-air jA connects")
	f.buffer_action = {"type": "normal", "button": "A", "x": 0, "y": 0}
	f.buffer_left = 6
	model._try_action(f)
	check(f.move.id == "tanjiro_jA" and f.attack_instance == 1, "jA cannot cancel into itself")
	f.buffer_action = {"type": "normal", "button": "C", "x": 0, "y": 0}
	model._try_action(f)
	check(f.move.id == "tanjiro_jC", "jA cancels into jC on contact")
	f.connected = true
	f.buffer_action = {"type": "normal", "button": "C", "x": 0, "y": 0}
	model._try_action(f)
	check(f.move.id == "tanjiro_jC" and f.air_chain == ["tanjiro_jA", "tanjiro_jC"], "jC cannot cancel into itself")
	f.buffer_action = {"type": "motion", "motion": "236", "button": "A", "x": 1, "y": 0}
	model._try_action(f)
	check(f.move.id == "tanjiro_j236A" and f.air_specials == 1, "jC cancels into an air special")
	# A whiffed jA cannot cancel.
	model = Probe.duel("tanjiro")
	f = model.fighters[0]
	model.fighters[1].x = f.x + 300
	f.grounded = false
	f.state = "air"
	f.y = Combat.FLOOR_Y - 60
	model._begin_move(f, _tanjiro("jA"))
	f.buffer_action = {"type": "normal", "button": "C", "x": 0, "y": 0}
	model._try_action(f)
	check(f.move.id == "tanjiro_jA", "whiffed jA cannot cancel")

func _frame_targets() -> void:
	var targets := {"5AA": [-4, 10], "5AAC": [-7, 7], "6B": [-5, 19], "6C": [-9, 4]}
	for key: String in targets:
		var move := _tanjiro("tanjiro_" + key)
		var blocked: Dictionary = Probe.ground("tanjiro", move, "stand")
		var struck: Dictionary = Probe.ground("tanjiro", move, "")
		check(blocked.contact == "block" and blocked.advantage == targets[key][0], "%s block advantage %d (got %s)" % [key, targets[key][0], blocked.advantage])
		check(struck.contact == "hit" and struck.advantage == targets[key][1], "%s hit advantage %d (got %s)" % [key, targets[key][1], struck.advantage])
		report.append({"move": key, "block": blocked.advantage, "hit": struck.advantage})
	# Air specials stay punishable by a four-frame light at every sampled height.
	for key in ["j236A", "j236C", "j214B", "j214D"]:
		var move := _tanjiro(key)
		var worst := -999
		for tick in [12, 16, 20, 24, 28]:
			for distance in [24.0, 32.0, 40.0]:
				var sample: Dictionary = Probe.air("tanjiro", move, tick, "stand", distance)
				if sample.contact == "block" and sample.advantage != null:
					worst = maxi(worst, int(sample.advantage))
		check(worst != -999 and worst <= -5, "%s is punishable on block (best case %d)" % [key, worst])
		report.append({"move": key, "best_block": worst})

func _routes() -> void:
	var routes := [
		{"route": [["5A", "tanjiro_5A"], ["5A", "tanjiro_5AA"], ["5C", "tanjiro_5AAC"], ["236A", "tanjiro_236A"]], "damage": 151},
		{"route": [["5A", "tanjiro_5A"], ["5A", "tanjiro_5AA"], ["5C", "tanjiro_5AAC"], ["236A", "tanjiro_236A"], ["236236A", "tanjiro_super"]], "damage": 333},
		{"route": [["5A", "tanjiro_5A"], ["5A", "tanjiro_5AA"], ["5C", "tanjiro_5AAC"], ["236236AC", "tanjiro_max"]], "damage": 383},
		{"route": [["6B", "tanjiro_6B"], ["5A", "tanjiro_5A", "link"], ["5A", "tanjiro_5AA"], ["236A", "tanjiro_236A"]], "damage": 148},
		{"route": [["6C", "tanjiro_6C"], ["236A", "tanjiro_236A", "delay"]], "damage": 110},
		{"route": [["6C", "tanjiro_6C"], ["236A", "tanjiro_236A", "delay"]], "damage": 110, "distance": 100}]
	for example in routes:
		for facing in [-1, 1]:
			for corner in [false, true]:
				_run_route(facing, corner, example)

func _run_route(facing: int, corner: bool, example: Dictionary) -> void:
	var model = s.duel(str(example.get("character", "tanjiro")), facing, corner)
	var distance: float = example.get("distance", 34.0)
	if corner:
		model.fighters[1].x = Combat.RIGHT if facing == 1 else Combat.LEFT
	model.fighters[0].x = model.fighters[1].x - facing * distance
	model.fighters[0].meter = 300
	s.events.clear()
	var connected := true
	for index in range(example.route.size()):
		var notation: String = example.route[index][0]
		var guard := {"x": facing} if index > 0 else {}
		var mode: String = example.route[index][2] if example.route[index].size() > 2 else ""
		if mode == "link":
			# A link: wait for the previous move to finish recovering.
			for frame in range(60):
				if model.fighters[0].move == null:
					break
				s.tick(model, {}, guard)
		elif mode == "delay":
			# 6C then an immediate 236 reads as 623; real players cancel a little later.
			s.advance(model, 8, {}, guard)
		s.input(model, notation, guard)
		if not s.wait_contact(model, 100, guard):
			connected = false
			break
	s.advance(model, 150, {}, {"x": facing})
	var hits: Array[String] = []
	var instances: Array[int] = []
	var blocked := false
	for event in s.events:
		if event.type == "hit" and event.attacker == 0 and not int(event.instance) in instances:
			instances.append(int(event.instance))
			hits.append(str(event.move))
		elif event.type == "block":
			blocked = true
	var expected: Array[String] = []
	for step in example.route:
		expected.append(step[1])
	var total: int = 1000 - model.fighters[1].hp
	var label := "%s facing%d corner%s" % [expected, facing, corner]
	check(connected and not blocked and hits == expected, "route connects in order (%s): %s" % [hits, label])
	check(total == int(example.damage), "route damage %d (got %d): %s" % [example.damage, total, label])
	report.append({"route": expected, "facing": facing, "corner": corner, "damage": total})

## Zenitsu: 稻魂 (5A > A > C), 热界雷 (6C, anti-air), 低身斩 (3C, low), 霹雳一闪·空 (j.236) and 远雷 (j.214).
func _zenitsu() -> void:
	var model := Combat.new()
	var zenitsu: Resource = model.catalog.characters.zenitsu
	var ids: Array[String] = []
	for move in zenitsu.all_moves():
		ids.append(move.id)
	for id in ["zenitsu_5AA", "zenitsu_5AAC", "zenitsu_6C", "zenitsu_3C", "zenitsu_j236A", "zenitsu_j236C", "zenitsu_j214B", "zenitsu_j214D"]:
		check(ids.count(id) == 1 and model.catalog.moves.has(id), "Zenitsu expansion move registered once: " + id)
	check(ids.size() == 29 and zenitsu.normals.size() == 12 and zenitsu.motions.size() == 8, "Zenitsu has 21 base and 8 expansion moves")
	check(ids.slice(0, 21) == ["zenitsu_5A", "zenitsu_5B", "zenitsu_5C", "zenitsu_5D", "zenitsu_2A", "zenitsu_2B", "zenitsu_2C", "zenitsu_2D",
		"zenitsu_jA", "zenitsu_jB", "zenitsu_jC", "zenitsu_jD", "zenitsu_236A", "zenitsu_236C", "zenitsu_623A", "zenitsu_623C",
		"zenitsu_214B", "zenitsu_214D", "zenitsu_super", "zenitsu_max", "zenitsu_throw"], "Zenitsu base moves keep their original order")
	for facing in [-1, 1]:
		# 稻魂: hit and block both continue.
		var duel = s.duel("zenitsu", facing)
		s.input(duel, "5A")
		s.wait_contact(duel)
		s.input(duel, "5A")
		s.wait_contact(duel)
		check(duel.fighters[0].last_move == "zenitsu_5AA", "Zenitsu 5A then A reaches 稻魂 two, facing %d" % facing)
		s.input(duel, "5C")
		s.wait_contact(duel)
		check(duel.fighters[0].last_move == "zenitsu_5AAC", "稻魂 two then C reaches stage three, facing %d" % facing)
		# 低身斩 is a low: a standing guard is hit, a crouching guard blocks.
		for crouch in [true, false]:
			duel = s.duel("zenitsu", facing)
			duel.fighters[0].x = duel.fighters[1].x - facing * 70
			var guard := {"x": facing, "y": 1 if crouch else 0}
			s.input(duel, "3C")
			_guard_until_contact(duel, guard)
			s.advance(duel, 40, {}, guard)
			check(duel.fighters[0].last_move == "zenitsu_3C", "3C selects 低身斩, facing %d" % facing)
			check((duel.fighters[1].hp < 1000) == (not crouch), "低身斩 is a low (crouch=%s), facing %d" % [crouch, facing])
		# 热界雷 is chosen by 6C; other inputs keep their original moves.
		duel = s.duel("zenitsu", facing)
		s.input(duel, "6C")
		s.advance(duel, 4)
		check(duel.fighters[0].last_move == "zenitsu_6C", "6C selects 热界雷, facing %d" % facing)
		for pair in [["2C", "zenitsu_2C"], ["5C", "zenitsu_5C"], ["3B", "zenitsu_2B"]]:
			duel = s.duel("zenitsu", facing)
			s.input(duel, pair[0])
			s.advance(duel, 4)
			check(duel.fighters[0].last_move == pair[1], "Zenitsu %s keeps %s" % [pair[0], pair[1]])
	# 热界雷 beats air attacks during its early frames, never ground attacks.
	var probe = Probe.duel("zenitsu")
	var zen = probe.fighters[0]
	var other = probe.fighters[1]
	probe._begin_move(zen, _move_of("zenitsu", "6C"))
	zen.move_frame = 5
	other.grounded = false
	check(not probe._can_be_struck(zen, other, _move_of("zenitsu", "jC"), 9, false), "热界雷 is safe from an air attack on frame 5")
	other.grounded = true
	check(probe._can_be_struck(zen, other, _move_of("zenitsu", "5A"), 9, false), "热界雷 can still be hit from the ground")
	zen.move_frame = 12
	other.grounded = false
	check(probe._can_be_struck(zen, other, _move_of("zenitsu", "jC"), 9, false), "热界雷's air protection ends on frame 10")
	# Air specials: one per jump; 远雷 stops the fall during its startup.
	for facing in [-1, 1]:
		var duel = s.duel("zenitsu", facing)
		duel.fighters[1].x = duel.fighters[0].x + facing * 150
		_jump(duel)
		s.advance(duel, 10)
		s.input(duel, "236A")
		var f = duel.fighters[0]
		check(f.last_move == "zenitsu_j236A" and not f.grounded, "airborne 236A selects 霹雳一闪·空, facing %d" % facing)
		s.input(duel, "214B")
		check(f.last_move == "zenitsu_j236A", "Zenitsu: one air special per jump, facing %d" % facing)
		for n in range(80):
			if f.grounded:
				break
			s.tick(duel)
		check(f.state == "landing" and f.stun >= 14, "霹雳一闪·空 lands into its recovery, facing %d" % facing)
		duel = s.duel("zenitsu", facing)
		duel.fighters[1].x = duel.fighters[0].x + facing * 150
		_jump(duel)
		s.advance(duel, 10)
		s.input(duel, "214B")
		f = duel.fighters[0]
		var height: float = f.y
		s.advance(duel, 5)
		check(f.last_move == "zenitsu_j214B" and is_equal_approx(f.y, height) and is_equal_approx(f.vy, 0.0), "远雷 stops in the air, facing %d (y %s -> %s, vy %s)" % [facing, height, f.y, f.vy])
	for key in ["j236A", "j214B"]:
		for crouch in [true, false]:
			# Both are mid-range dashes: point blank they pass over a crouching opponent, and
			# 远雷 started at the top of a jump stays above one, so it is sampled lower.
			var sample: Dictionary = Probe.air("zenitsu", _move_of("zenitsu", key), 18 if key == "j236A" else 26, "crouch" if crouch else "stand", 70)
			check(sample.contact == ("hit" if crouch else "block"), "%s must be stand-blocked (crouch=%s, got %s)" % [key, crouch, sample.contact])
	# Frame data on the ground; air specials punishable on block at every sampled height.
	var targets := {"5AA": [-3, 11], "5AAC": [-6, 7], "6C": [-9, 6], "3C": [-8, null]}
	for key: String in targets:
		var move := _move_of("zenitsu", "zenitsu_" + key)
		var blocked: Dictionary = Probe.ground("zenitsu", move, "crouch" if move.level == "low" else "stand")
		var struck: Dictionary = Probe.ground("zenitsu", move, "")
		check(blocked.contact == "block" and blocked.advantage == targets[key][0], "Zenitsu %s block advantage %d (got %s)" % [key, targets[key][0], blocked.advantage])
		if targets[key][1] != null:
			check(struck.contact == "hit" and struck.advantage == targets[key][1], "Zenitsu %s hit advantage %d (got %s)" % [key, targets[key][1], struck.advantage])
		report.append({"move": "zenitsu_" + key, "block": blocked.advantage, "hit": struck.advantage})
	for key in ["j236A", "j236C", "j214B", "j214D"]:
		var move := _move_of("zenitsu", key)
		var worst := -999
		for tick in [12, 16, 20, 24, 28]:
			for distance in [24.0, 32.0, 40.0]:
				var sample: Dictionary = Probe.air("zenitsu", move, tick, "stand", distance)
				if sample.contact == "block" and sample.advantage != null:
					worst = maxi(worst, int(sample.advantage))
		check(worst != -999 and worst <= -5, "Zenitsu %s is punishable on block (best case %d)" % [key, worst])
		report.append({"move": "zenitsu_" + key, "best_block": worst})
	var routes := [
		{"character": "zenitsu", "route": [["5A", "zenitsu_5A"], ["5A", "zenitsu_5AA"], ["5C", "zenitsu_5AAC"], ["236A", "zenitsu_236A"]], "damage": 122},
		{"character": "zenitsu", "route": [["5A", "zenitsu_5A"], ["5A", "zenitsu_5AA"], ["5C", "zenitsu_5AAC"], ["236A", "zenitsu_236A"], ["236236A", "zenitsu_super"]], "damage": 304},
		{"character": "zenitsu", "route": [["6C", "zenitsu_6C"], ["236A", "zenitsu_236A", "delay"]], "damage": 110}]
	for example in routes:
		for facing in [-1, 1]:
			for corner in [false, true]:
				_run_route(facing, corner, example)
