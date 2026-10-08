extends "res://tools/capture_awakening.gd"

func _run() -> void:
	awakening_out = "res://output/imagegen/awakening-v3-preview/review/runtime"
	DirAccess.make_dir_recursive_absolute(awakening_out)
	root.size = Vector2i(1280, 720)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage, game.view.super_view]:
		node.set_process(false)
	await process_frame
	game.mode = "practice"
	game.characters.assign(["akaza", "akaza"])
	game.stage_id = "infinity_castle"
	game.start_match()
	for slot in range(2):
		var fighter = game.combat.fighters[slot]
		fighter.x = 405 + slot * 150
		fighter.previous_x = fighter.x
	game.view.camera.reset(game.combat.fighters)
	_step()
	var portrait = game.catalog.characters.akaza.awakened_portrait
	_check(portrait != null, "Akaza awakened portrait loads")
	if portrait != null:
		_check(portrait.resource_path.ends_with("akaza/awakening/portrait.png"), "Approved portrait path selected")
		_check(portrait.get_size() == Vector2(512, 512), "Runtime portrait uses 512 square texture")
	await _shot("akaza-normal")
	_step({"buttons": 6})
	for tick in range(45): _step()
	_check(game.combat.fighters[0].awakening_ticks > 0, "P1 awakened with real BC input")
	_check(game.combat.fighters[1].awakening_ticks == 0, "P2 remains ordinary")
	await _shot("akaza-p1-awakened")
	game.combat.fighters[0].awakening_ticks = 1
	_step()
	_check(game.combat.fighters[0].awakening_ticks == 0, "P1 expires")
	await _shot("akaza-expired")
	game.combat.fighters[1].meter = 300
	_step({}, {"buttons": 6})
	for tick in range(45): _step()
	_check(game.combat.fighters[1].awakening_ticks > 0, "P2 awakened with real BC input")
	_check(game.combat.fighters[0].awakening_ticks == 0, "P1 remains ordinary")
	await _shot("akaza-p2-awakened")
	game.practice_controller.reset(game.combat)
	game.view._process(0)
	_check(game.combat.fighters.all(func(f): return f.awakening_ticks == 0), "Practice reset clears both forms")
	var report := FileAccess.open(awakening_out + "/captures.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"captures": captures, "checks": checks, "failures": failures, "method": "Actual Godot rendering and BC inputs"}, "  "))
	game.queue_free()
	await process_frame
	print("AKAZA PORTRAIT CAPTURE: %d passed, %d failed" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
