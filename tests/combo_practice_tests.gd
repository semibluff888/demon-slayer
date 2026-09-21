extends SceneTree
const Support = preload("res://tests/combat_test_support.gd")
const Practice = preload("res://scripts/practice_controller.gd")
const Combat = preload("res://scripts/combat.gd")
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
	_combo_matrix()
	_practice()
	var file := FileAccess.open("res://artifacts/combo-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	for failure in failures:
		printerr("FAIL: ", failure)
	print("COMBO / PRACTICE TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _combo_matrix() -> void:
	var cases := [
		{"route": ["2B","2A","5C","236A"], "damage": [226,226]},
		{"route": ["jC","5A","5C","214B"], "damage": [274,269]},
		{"route": ["5A","5C","236A","236236A"], "damage": [495,495]},
		{"route": ["5C","214D","236236AC"], "damage": [584,582]}]
	var prefixes := [
		{"route": [], "damage": [0,0]},
		{"route": ["5A"], "damage": [45,45]},
		{"route": ["5B"], "damage": [32,32]},
		{"route": ["2A"], "damage": [40,40]},
		{"route": ["2B"], "damage": [27,27]},
		{"route": ["5A","2A"], "damage": [83,83]},
		{"route": ["5A","2A","5C"], "damage": [155,155]},
		{"route": ["5A","2A","5C","236A"], "damage": [244,244]},
		{"route": ["jC","5A","2A","5C","236A"], "damage": [305,305]},
		{"route": ["jC","5A","2A","5C","236C"], "damage": [325,325]},
		{"route": ["jC","5A","2A","5C","623C"], "damage": [329,321]},
		{"route": ["236A"], "damage": [105,105]},
		{"route": ["5A","236A"], "damage": [144,144]}]
	for prefix in prefixes:
		for finisher in ["236236A", "236236AC"]:
			var route: Array = prefix.route.duplicate()
			route.append(finisher)
			var base := 280 if finisher == "236236A" else 445
			cases.append({"route": route, "damage": [prefix.damage[0] + base, prefix.damage[1] + base]})
	for character in ["tanjiro","zenitsu"]:
		for facing in [-1,1]:
			for corner in [false,true]:
				var totals := {}
				for example in cases:
					var route: Array = example.route
					var expected: int = example.damage[0 if character == "tanjiro" else 1]
					totals[JSON.stringify(route)] = _run_route(character, facing, corner, route, expected)
				for example in cases:
					var route: Array = example.route
					if route[-1] not in ["236236A", "236236AC"]:
						continue
					for index in range(route.size() - 1):
						var shorter: Array = route.duplicate()
						shorter.remove_at(index)
						var key := JSON.stringify(shorter)
						if totals.has(key):
							check(totals[JSON.stringify(route)] > totals[key], "real same-cost extension gains damage: %s/%s over %s/facing%d/corner%s" % [character, route, shorter, facing, corner])
	# Deliberately leave a gap: guard must reject a fake combo.
	var model = s.duel()
	s.input(model, "5A")
	s.wait_contact(model)
	s.advance(model, 50, {}, {"x": 1})
	var hp: int = model.fighters[1].hp
	s.input(model, "5C", {"x": 1})
	s.advance(model, 40, {}, {"x": 1})
	check(model.fighters[1].hp == hp, "first-hit guard catches deliberately disconnected normals")

func _run_route(character: String, facing: int, corner: bool, route: Array, expected: int) -> int:
	var model = s.duel(character, facing, corner)
	if corner:
		model.fighters[1].x = Combat.RIGHT if facing == 1 else Combat.LEFT
		model.fighters[0].x = model.fighters[1].x - facing * 34
	model.fighters[0].meter = 300
	var all_connected := true
	var requested_moves: Array[String] = []
	for index in range(route.size()):
		var notation: String = route[index]
		var definition = model.definition(model.fighters[0])
		var key := "super" if notation == "236236A" else ("max" if notation == "236236AC" else notation)
		var move = definition.normals.get(key, definition.motions.get(key))
		requested_moves.append(move.id)
		var guard := {"x": facing, "y": 1 if notation.begins_with("2") else 0} if index > 0 else {}
		if notation == "jC":
			s.tick(model, {"y": -1})
			s.advance(model, 18)
			s.input(model, "C")
		else:
			if index == 1 and str(route[0]).begins_with("j"):
				for frame in range(60):
					if model.fighters[0].grounded:
						break
					s.tick(model, {}, guard)
			s.input(model, notation, guard)
		if not s.wait_contact(model, 100, guard):
			all_connected = false
			break
	s.advance(model, 150, {}, {"x": facing})
	var f = model.fighters[0]
	var label := "%s/%s/facing%d/corner%s" % [character, route, facing, corner]
	var total: int = 1000 - model.fighters[1].hp
	var expected_cost := 300 if route[-1] == "236236AC" else (100 if route[-1] == "236236A" else 0)
	var spent := 0
	var hit_damage := 0
	var blocked := false
	var hit_moves: Array[String] = []
	var instances: Array[int] = []
	for event in s.events:
		if event.type == "meter" and event.attacker == 0 and event.amount < 0:
			spent -= int(event.amount)
		elif event.type == "hit" and event.attacker == 0:
			hit_damage += int(event.damage)
			if int(event.instance) not in instances:
				instances.append(int(event.instance))
				hit_moves.append(str(event.move))
		elif event.type == "block":
			blocked = true
	check(all_connected and not blocked, "first-hit guard sees continuous hits: " + label)
	check(hit_moves == requested_moves, "every requested move hits in order: " + label)
	check(f.combo >= route.size(), "combo counts all requested moves: " + label)
	check(f.combo_damage == total and hit_damage == total, "HUD and hit events equal actual lost HP: " + label)
	check(total == expected, "exact damage %d (got %d): %s" % [expected, total, label])
	check(spent == expected_cost and f.meter == 300 - expected_cost, "spend the same resource exactly once: " + label)
	report.append({"character": character, "route": route, "facing": facing, "corner": corner,
		"damage": total, "expected_damage": expected, "hits": f.combo, "remaining_meter": f.meter,
		"meter_spent": spent, "connected": all_connected and not blocked})
	return total

func _practice() -> void:
	var model = s.duel()
	var practice := Practice.new()
	practice.reset(model)
	check(model.practice and model.phase == "fight" and model.fighters[0].meter == 300, "practice starts immediately with three stocks")
	for mode in range(4):
		practice.meter_mode = mode
		practice.apply_meter(model)
		check(model.fighters[0].meter == [0,100,300,300][mode], "practice meter selector " + str(mode))
	practice.guard_mode = 1
	check(practice.command(model).x == -model.fighters[1].facing and practice.command(model).y == 0, "standing guard dummy")
	practice.guard_mode = 2
	check(practice.command(model).y == 1, "crouching guard dummy")
	practice.guard_mode = 3
	check(practice.command(model).x == 0, "first hit mode initially leaves dummy open")
	model.fighters[0].x = model.fighters[1].x - 34
	s.input(model, "5A")
	for n in range(35):
		var dummy := practice.command(model)
		s.tick(model, {}, dummy)
		practice.after_step(model)
		if practice.first_hit:
			break
	check(practice.first_hit and practice.command(model).x != 0, "first hit mode arms guard after actual damage")
	check(practice.last_combo == 1 and practice.last_damage == 45, "practice records actual combo results")
	practice.meter_mode = 3
	model.fighters[0].meter = 0
	practice.after_step(model)
	check(model.fighters[0].meter == 300, "infinite meter refills after normal resolution")
	model.remaining = 1
	model.fighters[1].hp = 0
	for n in range(110):
		s.tick(model, {}, practice.command(model))
		practice.after_step(model)
	check(model.phase == "fight" and model.remaining == 1 and model.wins == [0,0], "practice has no timeout or KO award")
	check(model.fighters[1].hp == 1000, "practice heals once combat returns to neutral")
	model.fighters[0].x += 100
	model.fighters[0].roll_frame = 5
	model.fighters[0].meter = 17
	practice.meter_mode = 1
	practice.reset(model)
	check(model.fighters[0].x == 430 and model.fighters[1].x == 490 and model.fighters[0].meter == 100, "manual reset restores positions and configured meter")
	check(model.fighters[0].roll_frame < 0 and model.projectiles.is_empty() and model.fighters[0].input.history.is_empty(), "practice reset clears transient state")
