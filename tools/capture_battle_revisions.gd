extends "res://tools/capture_battle_ui.gd"
## Focused review of the follow-up fixes; actual held-input MAX activations.
func _initialize() -> void:
	folder = "res://artifacts/battle-revisions/rendered"
	var args := OS.get_cmdline_user_args()
	video = "--video" in args
	_run.call_deferred()

func _run() -> void:
	if video:
		# Inherited battle capture records all four real moves and event audio.
		await super._run()
		return
	DirAccess.make_dir_recursive_absolute(folder)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view, game.view.effects, game.view.hud, game.view.stage, game.view.super_view]:
		node.set_process(false)
	for width in [960, 1280, 1920, 3840]:
		root.size = Vector2i(width, width * 9 / 16)
		for cid in ["tanjiro", "zenitsu"]:
			await _case(width, cid, "236236AC", 1, false, 1)
			await _case(width, cid, "236236AC", -1, true, -1)
		await _case(width, "tanjiro", "both", 1, false, 0)
		game.start_match()
		game.set_paused(true)
		await _hud_save("%d-pause" % width)
		game.show_practice_options()
		await _hud_save("%d-settings" % width)
		game.set_paused(false)
	root.size = Vector2i(1600, 1000)
	await _case(1600, "zenitsu", "236236AC", -1, true, -1)
	_json(folder + "/captures.json", {"captures":captures, "method":"Godot OpenGL with real held inputs; swapped sides, mirror match, dual MAX, restored menus and letterbox."})
	game.queue_free()
	await process_frame
	print("BATTLE REVISION CAPTURE: ", captures.size(), " images")
	quit()
