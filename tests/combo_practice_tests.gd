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
	var routes := [
		["2B","2A","5C","236A"],
		["jC","5A","5C","214B"],
		["5A","5C","236A","236236A"],
		["5C","214D","236236AC"]]
	for character in ["tanjiro","zenitsu"]:
		for facing in [-1,1]:
			for corner in [false,true]:
				for route_index in range(routes.size()):
					var model = s.duel(character, facing, corner)
					if corner:
						model.fighters[1].x = Combat.RIGHT if facing == 1 else Combat.LEFT
						model.fighters[0].x = model.fighters[1].x - facing * 34
					model.fighters[0].meter = 300
					var route: Array = routes[route_index]
					var all_connected := true
					var after_first := false
					for notation: String in route:
						var guard := {"x": facing, "y": 1 if notation.begins_with("2") else 0} if after_first else {}
						if notation == "jC":
							s.tick(model, {"y": -1})
							s.advance(model, 18)
							s.input(model, "C")
						else:
							if route_index == 1 and notation == "5A":
								while not model.fighters[0].grounded:
									s.tick(model, {}, guard)
							s.input(model, notation, guard)
						if not s.wait_contact(model, 100, guard):
							all_connected = false
							break
						after_first = true
					s.advance(model, 150, {}, {"x": facing})
					var f = model.fighters[0]
					var label := "%s/%s/facing%d/corner%s" % [character, route, facing, corner]
					check(all_connected, "all requested moves connect: " + label)
					check(f.combo >= route.size(), "first-hit-then-guard sees one continuous combo: " + label)
					var total: int = 1000 - model.fighters[1].hp
					check(f.combo_damage == total, "combo counter excludes no hidden gaps: " + label)
					if route_index == 2:
						check(f.meter == 200, "one-bar route spends exactly 100: " + label)
						check(total >= 350 and total <= 450, "one-bar damage budget: " + label)
					elif route_index == 3:
						check(f.meter == 0, "MAX route spends exactly 300: " + label)
						check(total >= 450 and total <= 550, "MAX damage budget: " + label)
					else:
						check(total >= 195 and total <= 300, "meterless damage budget: " + label)
					report.append({"character": character, "route": route, "facing": facing, "corner": corner,
						"damage": total, "hits": f.combo, "remaining_meter": f.meter, "connected": all_connected})
	# Deliberately leave a gap: guard must reject a fake combo.
	var model = s.duel()
	s.input(model, "5A")
	s.wait_contact(model)
	s.advance(model, 50, {}, {"x": 1})
	var hp: int = model.fighters[1].hp
	s.input(model, "5C", {"x": 1})
	s.advance(model, 40, {}, {"x": 1})
	check(model.fighters[1].hp == hp, "first-hit guard catches deliberately disconnected normals")

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
