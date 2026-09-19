extends SceneTree
## Offline showcase capture: real Combat.step commands and the shipped presentation.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(960, 540)
	var game := Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	DirAccess.make_dir_recursive_absolute("res://artifacts/combat-preview-frames")
	var frames := 0
	for id: String in ["water_slash", "water_wheel", "iai", "thunder"]:
		var character := "tanjiro" if id.begins_with("water") else "zenitsu"
		game.characters.assign([character, "zenitsu" if character == "tanjiro" else "tanjiro"])
		game.start_match()
		game.combat.phase = "fight"
		game.combat.fighters[0].x = 275
		game.combat.fighters[1].x = 320 if id == "water_wheel" else 350
		for tick in range(108):
			var command := Combat.neutral()
			if tick == 24:
				command.skill = true
				command.x = 1 if id in ["water_wheel", "thunder"] else 0
			game.combat.step([command, Combat.neutral()])
			game.view.consume(game.combat.events)
			await process_frame
			if tick % 4 == 0:
				await RenderingServer.frame_post_draw
				var frame := root.get_texture().get_image()
				var error := frame.save_png("res://artifacts/combat-preview-frames/frame-%03d.png" % frames)
				if error != OK:
					printerr("Preview write failed: ", error)
					quit(1)
					return
				frames += 1
	game.queue_free()
	await process_frame
	print("COMBAT PREVIEW: %d rendered frames, 15 FPS playback" % frames)
	quit()
