extends "res://tools/capture_menu_settings.gd"
## Capture only the current poster with its native menu, using isolated settings.
func _run() -> void:
	var folder:="res://artifacts/title-ensemble-v3"
	DirAccess.make_dir_recursive_absolute(folder)
	var config=Settings.new();config.path=folder+"/capture-settings.cfg";config.save_config()
	game=Main.instantiate();game.settings.path=config.path
	root.add_child(game);game.set_physics_process(false);game.sound.muted=true
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=size;game.show_title()
		await create_timer(0.35).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/title-%dx%d.png" % [size.x,size.y])
	game.sound.reset_audio();game.queue_free();await process_frame
	print("TITLE ENSEMBLE CAPTURE COMPLETE")
	quit()
