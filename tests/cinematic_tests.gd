extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Settings = preload("res://scripts/game_settings.gd")
var passed := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func setup(cid: String, kind: String, slot: int = 0, facing: int = 1, corner: bool = false) -> Combat:
	var model := Combat.new()
	model.new_match(cid if slot == 0 else "tanjiro", cid if slot == 1 else "zenitsu")
	model.phase = "fight"
	var a = model.fighters[slot]
	var d = model.fighters[1 - slot]
	a.x = (840 if facing > 0 else 120) if corner else 480
	d.x = a.x + facing * 34
	a.facing = facing; d.facing = -facing
	for f in model.fighters:
		f.previous_x = f.x; f.input.last_facing = f.facing
	a.meter = 300
	var attack = model.definition(a).motions[kind]
	model.cinematic_moves = {attack.id:true}
	model._begin_move(a, attack)
	return model
func until_capture(model: Combat, slot: int = 0, block: bool = false) -> void:
	for n in range(130):
		var commands: Array = [Combat.neutral(), Combat.neutral()]
		if block: commands[1 - slot].x = -model.fighters[1 - slot].facing
		model.step(commands)
		if not model.cinematic.is_empty(): return
func _initialize() -> void:
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		for kind in ["super", "max"]:
			for slot in [0, 1]:
				for facing in [-1, 1]:
					var model := setup(cid, kind, slot, facing, true)
					var a = model.fighters[slot]
					var d = model.fighters[1 - slot]
					var attack = model.definition(a).motions[kind]
					until_capture(model, slot)
					var label := "%s %s P%d facing%d" % [cid,kind,slot+1,facing]
					check(not model.cinematic.is_empty(), label + " real hit captures")
					if model.cinematic.is_empty(): continue
					check(a.meter == 300 - attack.meter_cost, label + " meter spent once")
					var before := model.snapshot()
					for n in range(60): model.step([{"x":1,"buttons":15}, {"x":-1,"buttons":15}])
					check(model.snapshot() == before, label + " no clock, input, stun or movement advances")
					for n in range(101): model.advance_cinematic(n / 100.0)
					check(d.hp == 1000 - attack.damage and a.combo == attack.hit_count(), label + " exact damage and hit count")
					var hp: int = d.hp
					model.advance_cinematic(1); model.advance_cinematic(0.5); model.advance_cinematic(1)
					check(d.hp == hp, label + " no duplicate segments")
					model.begin_cinematic_tail(cid == "zenitsu")
					check(a.facing == (-facing if cid == "zenitsu" else facing), label + " recovery orientation")
					check(a.x >= model.LEFT and d.x <= model.RIGHT and absf(a.x-d.x) < model.Arena.MAX_SEPARATION, label + " recovery fits arena")
					model.finish_cinematic()
					check(model.phase == "fight" and d.state == "knockdown" and d.reaction == "cinematic_landed", label + " controlled knockdown")
					for n in range(90): model.step([Combat.neutral(),Combat.neutral()])
					check(d.hp == hp and d.stun == 0 and a.move == null, label + " resumes without repeating attack")
	# Early release must allow real inputs without advancing or hitting the victim.
	for cid in ["tanjiro", "zenitsu", "nezuko", "akaza"]:
		for kind in ["super", "max"]:
			for slot in [0, 1]:
				var model := setup(cid, kind, slot)
				until_capture(model, slot)
				model.begin_cinematic_tail(cid == "zenitsu")
				model.release_cinematic_actor()
				var a = model.fighters[slot]
				var d = model.fighters[1-slot]
				var hp: int = d.hp
				var target_x: float = d.x
				var start_x: float = a.x
				var label := "%s %s P%d early release" % [cid,kind,slot+1]
				for n in range(30):
					var commands := [Combat.neutral(),Combat.neutral()]
					commands[slot].x = 1
					commands[1-slot] = {"x":-1,"y":-1,"buttons":15}
					model.step(commands)
				check(a.x > start_x and a.state == "walk", label + " movement")
				check(d.x == target_x and d.stun == 24 and d.state == "knockdown", label + " victim stays in place")
				var commands := [Combat.neutral(),Combat.neutral()]
				commands[slot].buttons = model.Commands.A
				model.step(commands)
				for n in range(model.Commands.CHORD_WINDOW): model.step([Combat.neutral(),Combat.neutral()])
				check(a.move != null, label + " attack input accepted")
				for n in range(8): model.step([Combat.neutral(),Combat.neutral()])
				check(d.hp == hp and model.cinematic.move == cid + "_" + kind, label + " no extra hit or recapture")
				var move = a.move
				var frame: int = a.move_frame
				model.finish_cinematic()
				check(a.move == move and a.move_frame == frame, label + " action survives completion")
	for mode in ["block", "whiff", "disabled"]:
		var model := setup("zenitsu", "super")
		if mode == "whiff": model.fighters[1].x = model.RIGHT
		if mode == "disabled": model.cinematic_moves.clear()
		until_capture(model, 0, mode == "block")
		check(model.cinematic.is_empty(), "no video on " + mode)
		check(model.phase == "fight", "ordinary combat continues on " + mode)
	for hp in [1, 90]:
		var model := setup("akaza", "max")
		model.fighters[1].hp = hp
		until_capture(model)
		check(model.phase == "fight" and model.wins == [0,0], "KO deferred at initial hit")
		model.advance_cinematic(1)
		check(model.phase == "fight" and model.fighters[1].hp == 0, "KO deferred through video")
		model.begin_cinematic_tail(false)
		check(model.phase == "fight", "KO deferred through landing")
		model.release_cinematic_actor()
		for n in range(25): model.step([{"x":-1,"y":0,"buttons":0},Combat.neutral()])
		check(model.phase == "fight" and model.wins == [0,0], "KO still deferred during free movement")
		model.finish_cinematic()
		check(model.phase == "round_end" and model.wins == [1,0], "KO scored once after landing")
		var position: float = model.fighters[1].x
		for n in range(40): model.step([Combat.neutral(),Combat.neutral()])
		check(model.fighters[1].grounded and model.fighters[1].x == position and model.defeat_frame(1) == 11, "KO does not relaunch landed victim")
	var reset_model := setup("nezuko", "max")
	until_capture(reset_model)
	reset_model.new_match("tanjiro", "zenitsu")
	check(reset_model.cinematic.is_empty(), "reset clears capture")
	var config := Settings.new()
	check(config.cinematic_enabled, "setting defaults on")
	config.path = "res://artifacts/cinematic-settings.cfg"
	config.cinematic_enabled = false
	config.save_config()
	var loaded := Settings.new(); loaded.path = config.path; loaded.load_config()
	check(not loaded.cinematic_enabled, "disabled setting persists")
	var legacy := ConfigFile.new(); legacy.set_value("audio", "volume", 0.5); legacy.save(config.path)
	loaded.load_config()
	check(loaded.cinematic_enabled, "legacy config defaults on")
	for failure in failures: printerr("FAIL: ", failure)
	print("CINEMATIC TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)
