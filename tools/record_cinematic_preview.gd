extends SceneTree
const Main = preload("res://scenes/main.tscn")
const Settings = preload("res://scripts/game_settings.gd")
var game: Node
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	var config := Settings.new()
	config.path = "res://artifacts/cinematics/record-settings.cfg"
	config.muted = false; config.volume = 0.7; config.save_config()
	game = Main.instantiate(); game.settings.path = config.path
	root.add_child(game); game.set_physics_process(false)
	game.mode = "local"; game.characters.assign(["zenitsu", "akaza"]); game.start_match()
	game.combat.phase = "fight"
	var a = game.combat.fighters[0]; var d = game.combat.fighters[1]
	a.x = 460; d.x = 495; a.previous_x = a.x; d.previous_x = d.x; a.meter = 300
	game.combat._begin_move(a, game.combat.definition(a).motions.super)
	for n in range(80):
		game._physics_process(1.0/60)
		if game.view.cinematic.active: break
	await create_timer(16).timeout
	if game.view.cinematic.active:
		printerr("FAIL: cinematic did not finish while recording")
		quit(1); return
	print("CINEMATIC RECORDING OK")
	game.sound.reset_audio(); game.queue_free(); await process_frame
	quit()
