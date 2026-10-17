extends SceneTree
## Records a fighter idling in a real match (normal and awakened form) for review.
## Run with a window and a fixed clock:
##   godot --path . --fixed-fps 60 --script res://tools/capture_idle_loop.gd -- --character=tanjiro [--seconds=4]
## Video goes to artifacts/art-v3/<character>/idle-loop/<form>/capture.mp4.
## Add --keep-frames for bounded lossless PNG output.
const Main = preload("res://scenes/main.tscn")
const CaptureOutput = preload("res://tools/capture_output.gd")
const Combat = preload("res://scripts/combat.gd")
var game: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var character := "tanjiro"
	var seconds := 4.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="):
			character = argument.trim_prefix("--character=")
		elif argument.begins_with("--seconds="):
			seconds = float(argument.trim_prefix("--seconds="))
	if seconds <= 0.0 or seconds > 300.0:
		printerr("CAPTURE ERROR: --seconds must be in (0, 300]")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	var saved := 0
	for form: String in ["normal", "awakened"]:
		var folder := "res://artifacts/art-v3/%s/idle-loop/%s/" % [character, form]
		var capture := CaptureOutput.new()
		if not capture.begin(folder):
			return
		game.characters.assign([character, "zenitsu" if character != "zenitsu" else "tanjiro"])
		game.start_match()
		var model = game.combat
		model.phase = "fight"
		model.practice = true
		model.fighters[0].x = 440
		model.fighters[1].x = 760
		if form == "awakened":
			model.awakening_infinite = true
			model.fighters[0].awakening_ticks = 600
			model.fighters[0].awakening_duration = 600
		game.view.camera.reset(model.fighters)
		game.view.stage.sync_camera()
		for tick in range(int(seconds * 60)):
			model.step([Combat.neutral(), Combat.neutral()])
			game.view.consume(model.events)
			await process_frame
			await RenderingServer.frame_post_draw
			capture.save(root.get_texture().get_image(), "frame-%04d.png" % tick)
			saved += 1
		if not capture.finish():
			return
	game.queue_free()
	await process_frame
	print("IDLE LOOP CAPTURE: %d frames" % saved)
	quit()
