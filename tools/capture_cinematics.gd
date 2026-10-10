extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Settings = preload("res://scripts/game_settings.gd")
const OUT := "res://artifacts/cinematics"
var game: Node
var passed := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label); printerr("FAIL: ", label)
func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
func trigger(cid: String, kind: String, slot: int = 0, facing: int = 1) -> void:
	game.characters.assign([cid, "akaza" if cid != "akaza" else "tanjiro"] if slot == 0 else ["tanjiro", cid])
	game.start_match()
	game.combat.phase = "fight"
	var a = game.combat.fighters[slot]
	var d = game.combat.fighters[1 - slot]
	a.x = 480; d.x = a.x + facing * 35
	a.facing = facing; d.facing = -facing
	for f in game.combat.fighters:
		f.previous_x = f.x; f.input.last_facing = f.facing; f.meter = 300
	game.combat._begin_move(a, game.combat.definition(a).motions[kind])
	for n in range(80):
		game._physics_process(1.0 / 60)
		if game.view.cinematic.active: break
	check(game.view.cinematic.active, cid + kind + " video triggered in main loop")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1280,720)
	var config := Settings.new(); config.path = OUT + "/settings.cfg"; config.muted = true; config.save_config()
	game = Main.instantiate(); game.settings.path = config.path
	root.add_child(game); game.set_physics_process(false)
	await process_frame
	game.show_settings(); await shot("settings")
	check(game.gui.actions.cinematic_enabled.button_pressed, "toggle defaults on in actual menu")
	game.gui.actions.cinematic_enabled.button_pressed = false
	var loaded := Settings.new(); loaded.path = config.path; loaded.load_config()
	check(not loaded.cinematic_enabled, "menu toggle persists")
	game.gui.actions.cinematic_enabled.button_pressed = true
	game.close_settings(); game.mode = "local"
	for cid in ["zenitsu", "tanjiro", "nezuko", "akaza"]:
		for kind in ["super", "max"]:
			var slot := 1 if kind == "max" else 0
			trigger(cid, kind, slot, -1 if slot == 1 else 1)
			var cinema = game.view.cinematic
			if not cinema.active: continue
			await create_timer(2.2).timeout
			check(cinema.movie.stream_position > 0.5 and cinema.movie.is_playing(), cid + kind + " decoder advances")
			check(cinema.soundtrack.playing and absf(cinema.soundtrack.get_playback_position() - cinema.movie.stream_position) < 0.15, cid + kind + " independent soundtrack synchronized")
			check(not game.view.stage.visible and not game.view.fighters[0].visible and not game.view.debug_layer.visible and not game.gui.visible, "only movie and HUD during " + cid + kind)
			check(game.view.hud.visible and game.view.hud.cinematic_mode and not game.view.hud.round_banner.visible, "top HUD retained " + cid + kind)
			await shot(cid + "_" + kind + "_video")
			if cid == "zenitsu" and kind == "super":
				game.set_paused(true)
				await process_frame
				var time: float = cinema.movie.stream_position
				var snapshot: Dictionary = game.combat.snapshot()
				await create_timer(0.35).timeout
				check(absf(cinema.movie.stream_position - time) < 0.04 and game.combat.snapshot() == snapshot, "pause freezes decoder and model")
				check(game.gui.visible, "pause menu remains accessible")
				check(cinema.soundtrack.stream_paused, "independent soundtrack pauses")
				game.show_settings(); game.gui.actions.audio_mute.button_pressed = false; game.gui.actions.audio_volume.value = 25
				await process_frame
				check(is_equal_approx(cinema.movie.volume, 0.25) and is_equal_approx(db_to_linear(cinema.soundtrack.volume_db), 0.25), "video follows volume while paused")
				game.gui.actions.audio_mute.button_pressed = true
				await process_frame
				check(cinema.movie.volume == 0 and cinema.soundtrack.volume_db <= -99, "video follows mute")
				game.close_settings(); game.set_paused(false)
				var deadline := Time.get_ticks_msec() + 18000
				while cinema.phase == "video" and Time.get_ticks_msec() < deadline:
					await process_frame
				check(cinema.phase == "tail", "actual Theora finished signal enters landing")
			else:
				cinema._video_finished()
			await create_timer(0.48).timeout
			check(not cinema.soundtrack.playing, "soundtrack stops before local landing")
			check(cinema.phase == "tail" and game.view.stage.visible and game.view.fighters[0].visible, "returns to actual stage " + cid + kind)
			check(game.combat.fighters[1-slot].state == "knockdown" and game.combat.fighters[1-slot].grounded, "actual opponent lands " + cid + kind)
			if cid == "zenitsu":
				check(game.combat.fighters[slot].facing == (1 if slot == 1 else -1), "Zenitsu faces away from victim")
			await shot(cid + "_" + kind + "_tail")
			await create_timer(0.8).timeout
			check(not cinema.active and game.combat.cinematic.is_empty() and game.gui.visible, "playback unlocks " + cid + kind)
			game._physics_process(1.0/60)
			check(game.combat.fighters[slot].move == null, "old attack does not replay " + cid + kind)
	game.mode = "practice"
	trigger("tanjiro", "max")
	check(game.practice_controller.first_hit, "practice records the initial cinematic hit")
	var practice_time: int = game.combat.remaining
	await create_timer(0.15).timeout
	check(game.combat.remaining == practice_time, "practice remains frozen during video")
	game.reset_practice()
	check(not game.view.cinematic.active and game.combat.cinematic.is_empty() and game.combat.fighters[1].hp == 1000, "practice reset clears playback")
	game.mode = "local"
	trigger("zenitsu", "super")
	await create_timer(0.15).timeout
	game.show_title()
	check(not game.view.cinematic.active and not game.view.cinematic.movie.is_playing(), "leaving battle cancels decoder")
	game.sound.reset_audio(); game.queue_free(); await process_frame
	print("CINEMATIC CAPTURE: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
