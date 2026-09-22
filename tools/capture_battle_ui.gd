extends "res://tools/capture_battle_v5.gd"
## Reuses real held-input cinematic captures; --hud adds explicit HUD/menu fixtures.

func _initialize() -> void:
	folder = "res://artifacts/battle-ui"
	super._initialize()

func _run() -> void:
	if "--hud" not in OS.get_cmdline_user_args():
		await super._run()
		return
	folder += "/hud"
	DirAccess.make_dir_recursive_absolute(folder)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage, game.view.super_view]:
		node.set_process(false)
	for width in [960, 1280, 1920, 3840]:
		root.size = Vector2i(width, width * 9 / 16)
		game.mode = "practice"
		game.characters.assign(["tanjiro", "zenitsu"])
		for value in [0, 99, 100, 175, 299, 300]:
			game.start_match()
			game.view.hud.practice_details = false
			game.combat.fighters[0].meter = value
			game.combat.fighters[1].meter = 300 - value
			game.combat.fighters[0].hp = 210
			game.combat.fighters[1].hp = 560
			game.combat.wins.assign([1, 2])
			await _hud_save("%d-meter-%d" % [width, value])
		game.combat.fighters[0].combo = 12
		game.combat.fighters[0].combo_damage = 495
		game.combat.fighters[0].combo_display = 100
		game.combat.fighters[1].combo = 108
		game.combat.fighters[1].combo_damage = 999
		game.combat.fighters[1].combo_display = 100
		await _hud_save("%d-combos" % width)
		game.start_match()
		game.view.hud.consume([{"type":"meter_empty", "attacker":0, "cost":300}, {"type":"meter", "attacker":1, "amount":-100}])
		await _hud_save("%d-meter-feedback" % width)
		game.view.hud.practice_details = true
		await _hud_save("%d-details" % width)
		game.set_paused(true)
		await _hud_save("%d-pause" % width)
		game.show_practice_options()
		await _hud_save("%d-settings" % width)
		game.set_paused(false)
		game.start_match()
		helper.events.clear()
		helper.input(game.combat, "236236AC")
		game.view.consume(helper.events)
		await _hud_save("%d-max-before-pause" % width)
		game.set_paused(true)
		await _hud_save("%d-max-paused" % width)
		game.set_paused(false)
		await _hud_save("%d-max-resumed" % width)
		game.mode = "local"
		game.devices.assign(["keyboard:0", "keyboard:1"])
		game.start_match()
		await _hud_save("%d-round-intro" % width)
		game.combat.phase_frames = 30
		await _hud_save("%d-round-start" % width)
		game.combat.phase = "round_end"
		game.combat.round_winner = 0
		await _hud_save("%d-round-end" % width)
	_json(folder + "/captures.json", {"captures":captures, "method":"Actual OpenGL; explicit HUD fixtures, native pause and practice controls."})
	game.queue_free()
	await process_frame
	print("BATTLE HUD CAPTURE COMPLETE ", captures.size())
	quit()

func _hud_save(label: String) -> void:
	if game.gui.transition != null:
		game.gui.transition.kill()
	game.gui.modulate = Color.WHITE
	_sync()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := folder + "/" + label + ".png"
	_window_capture().save_png(path)
	captures.append({"path":path, "size":[root.size.x, root.size.y], "case":label})
