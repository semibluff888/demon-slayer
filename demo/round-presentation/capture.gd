extends SceneTree
const Demo = preload("res://demo/round-presentation/demo.gd")
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
var demo: Node2D
var target := "res://demo/round-presentation/previews/"
var quick: bool = false

func _initialize() -> void:
	quick = "--quick" in OS.get_cmdline_user_args()
	_run.call_deferred()

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_jpg(path,0.94)

func _run() -> void:
	root.size=Vector2i(1280,720)
	if "--battle-only" in OS.get_cmdline_user_args():
		await _battle()
		print("ROUND CAPTURE OK")
		quit()
		return
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(target+"frames")
	DirAccess.make_dir_recursive_absolute(target+"matrix")
	DirAccess.make_dir_recursive_absolute(target+"audio")
	demo=Demo.new()
	demo.capture_mode=true
	root.add_child(demo)
	demo.set_process(false)
	demo.stage.set_process(false)
	demo.sound.muted=true
	for key: String in ["select","fight","round_end","hit"]:
		demo.sound.streams[key].save_to_wav(target+"audio/"+key+".wav")
	for cid in ["tanjiro","zenitsu"]:
		for variant in range(4):
			demo.character=cid
			demo.variant=variant
			demo.mode="full"
			demo.mirrored=false
			var name := "%s-%s" % [cid,char(97+variant)]
			if not quick:
				var directory := target+"frames/"+name
				DirAccess.make_dir_recursive_absolute(directory)
				for frame in range(381):
					demo.elapsed=frame*2
					demo.stage.time=frame/30.0
					demo.refresh()
					demo.stage.sync_camera()
					demo.stage.atmosphere.queue_redraw()
					await shot(directory+"/frame-%05d.jpg" % frame)
			demo.capture_mode=true
			demo.elapsed=72
			demo.refresh()
			await shot(target+name+".jpg")
			demo.capture_mode=true
			for width in ([1280] if quick else [960,1280,1920]):
				root.size=Vector2i(width,width*9/16)
				for mirror in [false,true]:
					demo.mirrored=mirror
					for clip in ["intro","victory","defeat"]:
						demo.mode=clip
						demo.elapsed=200 if clip=="defeat" else 72
						demo.refresh()
						await shot(target+"matrix/%s-%s-%d-%s.jpg" % [name,clip,width,"left" if mirror else "right"])
			root.size=Vector2i(1280,720)
	demo.queue_free()
	await process_frame
	if not quick:
		await _battle()
	print("ROUND CAPTURE OK")
	quit()

func _battle() -> void:
	var game := Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.mode="local"
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:
		node.set_process(false)
	var directory := target+"frames/battle"
	DirAccess.make_dir_recursive_absolute(directory)
	var frame := 0
	var global_tick := 0
	var audio: Array = []
	for scenario in ["opening-ko","timeout","double-ko"]:
		game.characters.assign(["tanjiro","zenitsu"])
		game.start_match()
		game.sound.muted=true
		var c = game.combat
		if scenario=="opening-ko":
			c.fighters[1].hp=45
		else:
			c.phase="fight"
			if scenario=="timeout":
				c.fighters[0].hp=700
				c.fighters[1].hp=450
				c.remaining=1
			else:
				c.fighters[0].hp=45
				c.fighters[1].hp=45
				c.fighters[0].x=463
				c.fighters[1].x=497
		game.view.reset_effects()
		for tick in range(750):
			var a := Combat.neutral()
			var b := Combat.neutral()
			if c.phase=="fight":
				if scenario=="opening-ko":
					if absf(c.fighters[0].x-c.fighters[1].x)>33:
						a.x=1
						b.x=-1
					elif c.fighters[0].move==null:
						a.buttons=1 if tick%8<4 else 0
				elif scenario=="double-ko":
					a.buttons=1
					b.buttons=1
			var previous: String=c.phase
			c.step([a,b])
			if previous=="round_end" and c.phase!="round_end": break
			game.view.consume(c.events)
			for cue: Dictionary in game.sound.cues(c.events,c):
				audio.append({"tick":global_tick,"kind":cue.kind,"gain":cue.gain})
				if not FileAccess.file_exists(target+"audio/"+cue.kind+".wav"):
					game.sound.streams[cue.kind].save_to_wav(target+"audio/"+cue.kind+".wav")
			game.view._process(1.0/60)
			game.view.effects._process(1.0/60)
			game.view.super_view._process(1.0/60)
			game.view.hud._process(1.0/60)
			game.view.stage._process(1.0/60)
			if global_tick%2==0:
				await shot(directory+"/frame-%05d.jpg" % frame)
				frame+=1
			global_tick+=1
	var file := FileAccess.open(target+"battle-audio.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":frame,"events":audio}))
	file.close()
	game.queue_free()
	await process_frame
