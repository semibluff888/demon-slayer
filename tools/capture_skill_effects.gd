extends SceneTree
## Render active skill poses in both directions, with optional combat boxes.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
var game: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var label := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
	var directory := "res://artifacts/skill-effects/" + label + "/"
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 720)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for id: String in ["water_slash", "water_wheel", "iai", "thunder"]:
		for facing: int in [1, -1]:
			var character := "tanjiro" if id.begins_with("water") else "zenitsu"
			game.characters.assign([character, "zenitsu" if character == "tanjiro" else "tanjiro"])
			game.start_match()
			game.combat.phase = "fight"
			var fighter = game.combat.fighters[0]
			var opponent = game.combat.fighters[1]
			fighter.x = 360 if facing > 0 else 600
			opponent.x = fighter.x + 210 * facing
			fighter.facing = facing
			opponent.facing = -facing
			game.view.camera.reset(game.combat.fighters)
			var move = game.combat.moves[id]
			var samples := [move.startup, move.startup + int(move.active / 2), move.startup + move.active - 1]
			for tick in range(move.startup + move.active + 2):
				var command := Combat.neutral()
				if tick == 0:
					command.skill = true
					command.x = facing if id in ["water_wheel", "thunder"] else 0
				game.combat.step([command, Combat.neutral()])
				await process_frame
				if fighter.move != null and fighter.move_frame in samples:
					var pose := samples.find(fighter.move_frame)
					for boxes: bool in [false, true]:
						game.view.debug_boxes = boxes
						await process_frame
						await process_frame
						await RenderingServer.frame_post_draw
						var name := "%s-%s-%d%s.png" % [id, "right" if facing > 0 else "left", pose, "-boxes" if boxes else ""]
						var error := root.get_texture().get_image().save_png(directory + name)
						if error != OK:
							printerr("Skill capture failed: ", name)
							quit(1)
							return
					game.view.debug_boxes = false
	game.queue_free()
	await process_frame
	print("SKILL EFFECT CAPTURE COMPLETE: ", label)
	quit()
