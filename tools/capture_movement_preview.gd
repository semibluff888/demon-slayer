extends SceneTree
## Reproducible engine recording. Commands go through real input edge/double-tap routing.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Router = preload("res://scripts/input_router.gd")
var game: Node2D
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	var scenarios := ["scroll_left", "scroll_right", "separation", "dash", "front_flip", "back_flip", "air_attack",
		"throw_tanjiro", "throw_zenitsu", "throw_left_corner", "throw_right_corner", "throw_mirror"]
	for resolution in [Vector2i(960,540), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = resolution
		var directory := "res://artifacts/movement-%d" % resolution.x
		DirAccess.make_dir_recursive_absolute(directory)
		var frame_number := 0
		var cue_sheet: Array[Dictionary] = []
		for scenario: String in scenarios:
			var first: String = "zenitsu" if scenario in ["throw_zenitsu", "back_flip", "throw_mirror"] else "tanjiro"
			var second: String = "zenitsu" if first == "tanjiro" or scenario == "throw_mirror" else "tanjiro"
			game.characters.assign([first,second])
			game.start_match()
			game.combat.phase = "fight"
			var a = game.combat.fighters[0]
			var b = game.combat.fighters[1]
			a.x = 410
			b.x = 650
			if scenario.begins_with("throw"):
				b.x = 442
			if scenario == "throw_left_corner":
				a.x = 28
				b.x = 60
			if scenario == "throw_right_corner":
				a.x = 932
				b.x = 900
			var router := Router.new()
			game.view.camera.reset(game.combat.fighters)
			game.view.stage.sync_camera()
			cue_sheet.append({"scenario":scenario,"start_frame":frame_number})
			var duration: int = 180 if scenario.begins_with("scroll") else 120 if scenario=="separation" else 84
			for tick in range(duration):
				var held := Combat.neutral()
				var other := Combat.neutral()
				if scenario == "scroll_left":
					held.x = -1
					other.x = -1
				elif scenario == "scroll_right":
					held.x = 1
					other.x = 1
				elif scenario == "separation":
					other.x = 1
				elif scenario == "dash":
					if tick in [8,12]:
						held.x = 1
					elif tick in [42,46]:
						held.x = -1
				elif scenario in ["front_flip","back_flip","air_attack"]:
					if tick == 12:
						held.jump = true
						held.x = -1 if scenario=="back_flip" else 1
					if scenario=="air_attack" and tick==27:
						held.heavy = true
				elif scenario.begins_with("throw") and tick==12:
					held.throw = true
				game.combat.step([router.command_from_held(0,held),router.command_from_held(1,other)])
				game.view.consume(game.combat.events)
				await process_frame
				if tick % 4 == 0:
					await RenderingServer.frame_post_draw
					var rendered := root.get_texture().get_image()
					if rendered.get_size()!=resolution:
						failures.append("Wrong capture dimensions")
					rendered.save_jpg(directory+"/frame-%04d.jpg" % frame_number,0.90)
					if tick in [0,24,32,40,60] or (scenario.begins_with("scroll") and tick==176):
						rendered.save_png(directory+"/%s-%03d.png" % [scenario,tick])
					frame_number += 1
		var file := FileAccess.open(directory+"/cues.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"resolution":[resolution.x,resolution.y],"fps":15,"frames":frame_number,"cues":cue_sheet},"  "))
		print("MOVEMENT CAPTURE: ",resolution," frames=",frame_number)
	game.queue_free()
	await process_frame
	for failure in failures:
		printerr("FAIL: ",failure)
	print("MOVEMENT CAPTURE COMPLETE")
	quit(0 if failures.is_empty() else 1)
