extends SceneTree
## Renders Tanjiro's rebuilt effects tick by tick for review against the
## reference video. Run with a window and a fixed clock:
##   godot --path . --fixed-fps 60 --script res://tools/capture_tanjiro_vfx.gd -- [--moves=236A,236C] [--forms=normal,awakened] [--facings=1,-1] [--every=2] [--hd]
## Frames land in artifacts/tanjiro-vfx/<move>-<form>-<right|left>/t###.png;
## tools/build_tanjiro_vfx_review.py turns them into contact sheets and videos.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const OUT := "res://artifacts/tanjiro-vfx/"
var game: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback

func _run() -> void:
	var moves := _option("moves", "236A,236C").split(",")
	var forms := _option("forms", "normal,awakened").split(",")
	var facings := _option("facings", "1,-1").split(",")
	var every := int(_option("every", "2"))
	root.size = Vector2i(1920, 1080) if "--hd" in OS.get_cmdline_user_args() else Vector2i(1280, 720)
	game = Main.instantiate()
	game.settings.path = "res://artifacts/capture_tanjiro_vfx-settings.cfg"
	game.settings.cinematic_enabled = false
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	game.mode = "local"
	await process_frame
	for move_id in moves:
		for form in forms:
			for facing_text in facings:
				await _capture(move_id, form, int(facing_text), every)
	game.queue_free()
	await process_frame
	print("TANJIRO VFX CAPTURE COMPLETE")
	quit()

func _capture(move_id: String, form: String, facing: int, every: int) -> void:
	var folder := "%s%s-%s-%s/" % [OUT, move_id, form, "right" if facing > 0 else "left"]
	DirAccess.make_dir_recursive_absolute(folder)
	game.characters.assign(["tanjiro", "zenitsu"])
	game.start_match()
	var model = game.combat
	model.phase = "fight"
	model.remaining = 5400
	var attacker = model.fighters[0]
	var target = model.fighters[1]
	attacker.x = 380.0 if facing > 0 else 580.0
	target.x = attacker.x + 150.0 * facing
	attacker.facing = facing
	target.facing = -facing
	attacker.input.last_facing = facing
	if form == "awakened":
		attacker.awakening_ticks = 900
		attacker.awakening_duration = 900
	game.view.camera.reset(model.fighters)
	game.view.reset_effects()
	game.view.effects.tanjiro.interpolate = false
	for n in range(4):
		await process_frame
	var move: Resource = model.moves["tanjiro_" + move_id]
	model._begin_move(attacker, move)
	game.view.consume(model.events)
	var total: int = move.total_frames() + 30
	for tick in range(total):
		model.step([Combat.neutral(), Combat.neutral()])
		game.view.consume(model.events)
		await process_frame
		if tick % every == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + "t%03d.png" % tick)
