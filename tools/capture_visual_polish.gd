extends SceneTree
## Actual combat commands and rendered frames for the visual-polish review.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Router = preload("res://scripts/input_router.gd")
var game: Node2D
var frame_number: int = 0
var cues: Array[Dictionary] = []
const OUT = "res://artifacts/visual-polish/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "frames")
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	root.size = Vector2i(1280, 720)
	for character: String in ["tanjiro", "zenitsu"]:
		for scenario: String in ["idle", "walk", "walk_back", "dash_forward", "dash_back", "jump_forward", "jump_back", "air_light", "air_heavy", "forward_skill"]:
			game.characters.assign([character, "zenitsu" if character == "tanjiro" else "tanjiro"])
			game.start_match()
			game.combat.phase = "fight"
			game.combat.fighters[0].x = 410
			game.combat.fighters[1].x = 690
			game.view.camera.reset(game.combat.fighters)
			game.view.stage.sync_camera()
			var router := Router.new()
			var total := 204 if scenario == "idle" else 72
			cues.append({"character":character,"scenario":scenario,"start_frame":frame_number})
			for tick in range(total):
				var held := Combat.neutral()
				if scenario in ["walk", "walk_back"] and tick >= 12 and tick < 52:
					held.x = -1 if scenario == "walk_back" else 1
				elif scenario in ["dash_forward", "dash_back"] and tick in [10, 14]:
					held.x = -1 if scenario == "dash_back" else 1
				elif scenario in ["jump_forward", "jump_back", "air_light", "air_heavy"]:
					if tick == 12:
						held.y = -1
						held.x = -1 if scenario == "jump_back" else 1
					if tick == 27:
						held.buttons = 1 if scenario == "air_light" else (4 if scenario == "air_heavy" else 0)
				elif scenario == "forward_skill" and tick in [10, 11, 12]:
					var motion := "623" if character == "tanjiro" else "236"
					var direction := int(motion[tick - 10])
					held.x = (direction - 1) % 3 - 1
					held.y = 1 - int((direction - 1) / 3)
					held.buttons = 1 if tick == 12 else 0
				game.combat.step([router.command_from_held(0, held), Combat.neutral()])
				game.view.consume(game.combat.events)
				await process_frame
				if tick % 3 == 0:
					await RenderingServer.frame_post_draw
					var picture := root.get_texture().get_image()
					picture.save_jpg(OUT + "frames/frame-%04d.jpg" % frame_number, 0.9)
					if tick in [0, 24, 30, 36, 48]:
						picture.save_png(OUT + "%s-%s-%02d.png" % [character,scenario,tick])
					frame_number += 1
	# Wide and narrow screenshots at both camera limits, with feet on the same floor.
	for resolution in [Vector2i(960,540),Vector2i(1920,1080)]:
		root.size = resolution
		for side: String in ["left", "center", "right"]:
			game.characters.assign(["zenitsu","tanjiro"])
			game.start_match()
			game.combat.phase = "fight"
			game.combat.fighters[0].x = 70 if side == "left" else 660 if side == "right" else 325
			game.combat.fighters[1].x = 300 if side == "left" else 890 if side == "right" else 635
			game.view.camera.reset(game.combat.fighters)
			for tick in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT + "stage-%s-%d.png" % [side,resolution.x])
	var report := FileAccess.open(OUT + "cues.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"fps":20,"frames":frame_number,"cues":cues},"  "))
	game.queue_free()
	await process_frame
	print("VISUAL POLISH CAPTURE COMPLETE: ", frame_number, " frames")
	quit()
