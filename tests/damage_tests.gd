extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Move = preload("res://scripts/move_data.gd")
const Support = preload("res://tests/combat_test_support.gd")
var s := Support.new()
var passed := 0
var failures: Array[String] = []
var audit: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(message)

func _initialize() -> void:
	_rounding()
	_scaling_floor()
	_partial_hits()
	_actual_damage_and_reset()
	_route_extensions()
	var file := FileAccess.open("res://artifacts/combo-damage-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"runs": audit, "failures": failures}, "  "))
	for failure in failures:
		printerr("FAIL: ", failure)
	print("DAMAGE TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _rounding() -> void:
	var move := Move.new()
	move.damage = 100
	move.hit_frames = PackedInt32Array([5, 10, 15])
	check([move.segment_damage(0, 85), move.segment_damage(1, 85), move.segment_damage(2, 85)] == [28, 28, 29], "scale whole move before splitting; final hit receives remainder")
	for count in [1, 2, 3, 4, 6]:
		move.hit_frames.clear()
		for index in range(count):
			move.hit_frames.append(5 + index * 5)
		var total := 0
		var unscaled := 0
		for index in range(count):
			total += move.segment_damage(index, 85)
			unscaled += move.segment_damage(index)
		check(total == 85 and unscaled == 100, "identical total damage regardless of hit count: %d" % count)
	move.damage = 1
	check(move.segment_damage(0, 40) == 1 and move.segment_damage(5, 40) == 1, "very low damage still grants at least one point per landed segment")
	move.hit_frames.clear()
	check(move.hit_count() == 1 and move.segment_damage(0, 40) == 1, "empty hit frames represent one hit")

func _scaling_floor() -> void:
	# Isolate the formula beyond the playable chain limit without changing resources.
	var expected := [80,76,72,68,64,60,56,52,48,44,40,36,32,32]
	for character in ["tanjiro", "zenitsu"]:
		for finisher in ["super", "max"]:
			var model = s.duel(character)
			var a = model.fighters[0]
			var d = model.fighters[1]
			d.hp = 10000
			var heavy: Move = model.definition(a).normals["5C"]
			for index in range(expected.size()):
				var before: int = d.hp
				model._resolve_contact(model._contact(a, d, heavy, index + 1, 0, false))
				check(before - d.hp == expected[index], "five-point progression and 40 percent floor: %s/%d" % [character, index])
			var move: Move = model.definition(a).motions[finisher]
			var before: int = d.hp
			for segment in range(move.hit_count()):
				model._resolve_contact(model._contact(a, d, move, 100, segment, false))
			check(before - d.hp == (280 if finisher == "super" else 445), "super ignores even maximum accumulated scaling: %s/%s" % [character, finisher])
			check(a.combo_instances.size() == expected.size() + 1, "multi-hit finisher consumes only one scaling instance")
			var instances: int = a.combo_instances.size()
			var chip_before: int = d.hp
			var blocked := model._contact(a, d, heavy, 101, 0, false)
			blocked.blocked = true
			model._resolve_contact(blocked)
			check(a.combo_instances.size() == instances and d.hp == chip_before, "blocked normal never advances hit damage scaling")

func _partial_hits() -> void:
	for character in ["tanjiro", "zenitsu"]:
		for finisher in ["236236A", "236236AC"]:
			var cost := 100 if finisher == "236236A" else 300
			for interrupted in [false, true]:
				var model = s.duel(character)
				var a = model.fighters[0]
				var d = model.fighters[1]
				a.meter = cost
				var move: Move = model.definition(a).motions["super" if cost == 100 else "max"]
				s.input(model, finisher)
				check(s.wait_contact(model), "first segment of finisher connects: %s/%s" % [character, finisher])
				if interrupted:
					a.move = null
					a.state = "idle"
				else:
					d.x = Combat.RIGHT
				s.advance(model, 160)
				check(1000 - d.hp == move.segment_damage(0) and a.combo == 1, "missing or interrupted later segments never award whole super damage: %s/%s/%s" % [character, finisher, interrupted])
				check(a.meter == 0, "partial super spends full cost once and does not refund")
			var model = s.duel(character)
			model.fighters[0].meter = cost
			model.fighters[0].x = Combat.LEFT
			model.fighters[1].x = Combat.RIGHT
			s.input(model, finisher)
			s.advance(model, 160)
			check(model.fighters[1].hp == 1000 and model.fighters[0].combo == 0 and model.fighters[0].meter == 0, "fully whiffed super deals no damage and still spends meter")
		# Only the final segment connects; the missed first segment is not made up.
		var model = s.duel(character)
		var a = model.fighters[0]
		var d = model.fighters[1]
		var move: Move = model.definition(a).motions["214D"]
		d.x = Combat.RIGHT
		s.input(model, "214D")
		for frame in range(60):
			if a.move != null and a.move_frame >= move.segment_start(1):
				break
			s.tick(model)
		d.x = a.x + a.facing * 34
		s.advance(model, 90)
		check(1000 - d.hp == (63 if character == "tanjiro" else 60) and a.combo == 1, "late single segment keeps only its authored share: " + character)
		model = s.duel(character)
		s.input(model, "214D", {"x": 1})
		s.advance(model, 90, {}, {"x": 1})
		check(1000 - model.fighters[1].hp == (9 if character == "tanjiro" else 8), "chip retains original unscaled segment calculation: " + character)
		check(model.fighters[1].meter == 3 and model.fighters[0].combo_damage == 0, "multi-hit guard grants meter once without combo damage")

func _actual_damage_and_reset() -> void:
	var model = s.duel()
	var a = model.fighters[0]
	var d = model.fighters[1]
	s.input(model, "5A")
	check(s.wait_contact(model), "normal opener hits")
	s.input(model, "5C", {"x": 1})
	check(s.wait_contact(model, 100, {"x": 1}), "scaled heavy cancels continuously")
	check(a.combo_damage == 121 and 1000 - d.hp == 121, "actual normal combo damage includes 95 percent heavy")
	check(a.meter == 30 and d.meter == 17, "both players gain meter from actual scaled damage")
	s.advance(model, 60)
	check(not a.combo_active and a.combo_instances.is_empty() and a.combo_display > 0, "scaling resets on recovery while old HUD result remains visible")
	d.x = a.x + a.facing * 34
	var before: int = d.hp
	s.input(model, "5C")
	check(s.wait_contact(model), "new combo heavy hits after recovery")
	check(before - d.hp == 80 and a.combo_damage == 80 and a.combo == 1, "next combo starts at full damage and replaces old HUD total")
	for character in ["tanjiro", "zenitsu"]:
		for finisher in ["236236A", "236236AC"]:
			model = s.duel(character)
			a = model.fighters[0]
			d = model.fighters[1]
			var cost := 100 if finisher == "236236A" else 300
			a.meter = cost
			d.hp = 50
			s.input(model, "5A")
			check(s.wait_contact(model), "low-health opener hits")
			s.input(model, finisher)
			s.advance(model, 45)
			var dealt := 0
			var spent := 0
			for event in s.events:
				if event.type == "hit" and event.attacker == 0:
					dealt += int(event.damage)
				elif event.type == "meter" and event.attacker == 0 and event.amount < 0:
					spent -= int(event.amount)
			check(d.hp == 0 and a.combo_damage == 50 and dealt == 50, "lethal super clamps events and HUD to remaining HP: %s/%s" % [character, finisher])
			check(a.meter == (11 if cost == 100 else 0) and d.meter == 6 and spent == cost, "overkill neither generates extra meter nor repeats the cost")

func _route_extensions() -> void:
	# These are contact-level arithmetic candidates, not proof of reach or hitstun.
	# Real motion inputs and guard continuity are covered by combo_practice_tests.
	var light_routes: Array = [[]]
	for first in ["5A", "5B", "2A", "2B"]:
		light_routes.append([first])
		for second in ["5A", "5B", "2A", "2B"]:
			if first != second:
				light_routes.append([first, second])
	var routes: Array[Array] = []
	for jump in ["", "jA", "jB", "jC", "jD"]:
		for lights in light_routes:
			for heavy in ["", "5C", "5D", "2C"]:
				for special in ["", "236A", "236C", "623A", "623C", "214B", "214D"]:
					for finisher in ["", "super", "max"]:
						var route: Array = []
						if not jump.is_empty():
							route.append(jump)
						route.append_array(lights)
						for move in [heavy, special, finisher]:
							if not move.is_empty():
								route.append(move)
						if not route.is_empty():
							routes.append(route)
	for character in ["tanjiro", "zenitsu"]:
		var model = s.duel(character)
		for cancel_on_first in [false, true]:
			var totals := {}
			var highest := 0
			var best: Array = []
			for route in routes:
				var total := _resolve_route(model, route, cancel_on_first)
				totals[JSON.stringify(route)] = total
				if total > highest:
					highest = total
					best = route
			var comparisons := 0
			for route in routes:
				for index in range(route.size()):
					if route[index] in ["super", "max"]:
						continue
					var shorter: Array = route.duplicate()
					shorter.remove_at(index)
					if shorter.is_empty():
						continue
					var key := JSON.stringify(shorter)
					if totals.has(key):
						comparisons += 1
						check(totals[JSON.stringify(route)] > totals[key], "contact-level extension gains damage: %s/%s over %s/first-segment cancel %s" % [character, route, shorter, cancel_on_first])
			check(routes.size() == 7139 and comparisons == 28930, "enumeration covers every supported route shape")
			audit.append({"character": character, "cancel_on_first": cancel_on_first,
				"candidate_routes": routes.size(), "extension_comparisons": comparisons,
				"highest_damage": highest, "highest_route": best, "checks_reach_and_hitstun": false})

func _resolve_route(model: Combat, route: Array, cancel_on_first: bool) -> int:
	var a = model.fighters[0]
	var d = model.fighters[1]
	d.stun = 0
	d.state = "idle"
	d.hp = 10000
	model._update_sequences()
	model.events.clear()
	var definition = model.definition(a)
	for index in range(route.size()):
		var move: Move = definition.normals.get(route[index], definition.motions.get(route[index]))
		var count := move.hit_count()
		if cancel_on_first and move.kind == "skill" and index < route.size() - 1:
			count = 1
		for segment in range(count):
			model._resolve_contact(model._contact(a, d, move, index + 1, segment, false))
	return a.combo_damage
