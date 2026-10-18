extends SceneTree
## Renders Tanjiro's rebuilt effects tick by tick for review against the
## reference video. Run with a window and a fixed clock:
##   godot --path . --fixed-fps 60 --script res://tools/capture_tanjiro_vfx.gd -- [--moves=236A,236C] [--forms=normal,awakened] [--facings=1,-1] [--every=2] [--hd]
## Videos land in artifacts/tanjiro-vfx/<move>-<form>-<right|left>/capture.mp4.
## --character=nezuko (or zenitsu, akaza) records another rebuilt fighter the same way,
## into artifacts/<character>-vfx/.
## Add --keep-frames for t###.png and build_tanjiro_vfx_review.py contact sheets.
const Main = preload("res://scenes/main.tscn")
const CaptureOutput = preload("res://tools/capture_output.gd")
const Combat = preload("res://scripts/combat.gd")
var game: Node2D
var character := "tanjiro"

func _initialize() -> void:
	_run.call_deferred()

func _option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.get_slice("=", 1)
	return fallback

func _run() -> void:
	character = _option("character", "tanjiro")
	var moves := _option("moves", "236A,236C").split(",")
	var forms := _option("forms", "normal,awakened").split(",")
	var facings := _option("facings", "1,-1").split(",")
	var every := int(_option("every", "2"))
	if every < 1 or every > 60:
		printerr("CAPTURE ERROR: --every must be 1..60")
		quit(1)
		return
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
				if not await _capture(move_id, form, int(facing_text), every):
					game.queue_free()
					quit(1)
					return
	game.queue_free()
	await process_frame
	print("TANJIRO VFX CAPTURE COMPLETE")
	quit()

func _capture(move_id: String, form: String, facing: int, every: int) -> bool:
	var folder := "res://artifacts/%s-vfx/%s-%s-%s/" % [character, move_id, form, "right" if facing > 0 else "left"]
	var capture := CaptureOutput.new()
	if not capture.begin(folder, 60.0 / every):
		return false
	game.characters.assign([character, "zenitsu" if character != "zenitsu" else "tanjiro"])
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
	game.view.effects.get(character).interpolate = false
	for n in range(4):
		await process_frame
	var move: Resource = model.moves[character + "_" + move_id]
	model._begin_move(attacker, move)
	game.view.consume(model.events)
	var total: int = move.total_frames() + 30
	for tick in range(total):
		model.step([Combat.neutral(), Combat.neutral()])
		game.view.consume(model.events)
		await process_frame
		if tick % every == 0:
			await RenderingServer.frame_post_draw
			if not capture.save(root.get_texture().get_image(), "t%03d.png" % tick):
				return false
	return capture.finish()
