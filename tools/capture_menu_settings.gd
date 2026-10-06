extends SceneTree
const Main=preload("res://scenes/main.tscn")
const Settings=preload("res://scripts/game_settings.gd")
const OUT="res://artifacts/menu-settings"
var game: Node
var count:=0
var capture_records: Array[Dictionary]=[]
func _initialize() -> void:_run.call_deferred()
func shot(name: String) -> void:
	await create_timer(0.32).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var captured:=root.get_texture().get_image()
	captured.save_png(OUT+"/"+name+".png")
	capture_records.append({"file":name+".png","window_size":[root.size.x,root.size.y],"viewport_size":[captured.get_width(),captured.get_height()]})
	count+=1
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var config=Settings.new();config.path=OUT+"/capture-settings.cfg";config.save_config()
	root.size=Vector2i(1280,720)
	game=Main.instantiate();game.settings.path=config.path
	root.add_child(game);game.set_physics_process(false);game.sound.muted=true
	await process_frame
	for size: Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160),Vector2i(1600,1000)]:
		root.size=size
		game.show_title();await shot("title-%dx%d" % [size.x,size.y])
		game.show_settings();await shot("settings-%dx%d" % [size.x,size.y])
	root.size=Vector2i(1280,720)
	game.gui.actions.key_0_4.pressed.emit();await shot("key-capture")
	var event:=InputEventKey.new();event.physical_keycode=KEY_KP_5;event.keycode=KEY_KP_5;event.pressed=true
	game._input(event);await shot("key-conflict")
	game.close_settings()
	game.choose_mode("local");await shot("selection")
	game.start_match();game.set_paused(true);await shot("pause")
	game.show_settings();await shot("pause-settings")
	game.close_settings();game.show_help();await shot("help")
	var report=FileAccess.open(OUT+"/menu-capture.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"method":"Actual Godot viewport capture; non-16:9 window letterbox margins excluded.","captures":capture_records},"  "))
	report.close();report=null
	game.sound.reset_audio()
	game.queue_free();await process_frame
	print("MENU SETTINGS CAPTURE: ",count," screenshots")
	quit()
