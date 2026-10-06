extends "res://tools/capture_fate_revisions.gd"
const POLISH := "res://artifacts/uppercut-polish"

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(POLISH)
	root.size=Vector2i(1280,720)
	game=Main.instantiate();root.add_child(game)
	game.set_physics_process(false);game.sound.muted=true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:node.set_process(false)
	await process_frame
	if "--actor-only" in OS.get_cmdline_user_args():
		await _uppercut_video()
		game.queue_free();await process_frame
		print("UPPERCUT ACTOR CAPTURE COMPLETE");quit();return
	if "--stage-only" not in OS.get_cmdline_user_args():
		await _scale_comparisons()
		await _uppercut_video()
		await _combo_video()
	await _hd_stage()
	if "--stage-only" in OS.get_cmdline_user_args():
		game.queue_free();await process_frame
		print("UPPERCUT STAGE CAPTURE COMPLETE");quit();return
	var file:=FileAccess.open(POLISH+"/capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"screenshots":captures,"chapters":chapters,"method":"Production Godot rendering. Real held inputs for combat. Scale comparison P1 uses preserved pre-fix drawings at identical physical scale; P2 uses current atlas."},"  "))
	game.queue_free();await process_frame
	print("UPPERCUT CAPTURE COMPLETE: ",captures.size()," screenshots")
	quit()

func _save(name: String) -> void:
	await create_timer(0.25).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(POLISH+"/"+name+".png")
	captures.append(name+".png")

func _scale_comparisons() -> void:
	for action: String in ["idle","B","D","guard"]:
		_reset_demo("nezuko","nezuko",1,false)
		for tick in range(10):
			var command: Dictionary={"y":1,"x":-1} if action=="guard" else {}
			var other: Dictionary={"y":1,"x":1} if action=="guard" else {}
			if action in ["B","D"] and tick==1:
				command={"buttons":2 if action=="B" else 8};other=command.duplicate()
			_step(command,other)
			var actor=game.view.fighters[0]
			if action in ["B","D"] and actor.fighter.move!=null and actor.fighter.move_frame>=actor.fighter.move.startup+1:break
		var actor=game.view.fighters[0]
		var before=Image.load_from_file("res://output/imagegen/uppercut-v1/baseline/nezuko/"+actor.clip+"/"+str(actor.frame_index)+".png")
		actor.texture=ImageTexture.create_from_image(before);actor.queue_redraw()
		await _save("nezuko-"+action+"-before-after")

func _uppercut_video() -> void:
	video_folder=POLISH+"/uppercut-video";frames=0
	DirAccess.make_dir_recursive_absolute(video_folder)
	for cid: String in ["tanjiro","zenitsu","nezuko","akaza"]:
		for button: String in ["A","C"]:
			_reset_demo(cid,"akaza" if cid!="akaza" else "nezuko",1,false)
			chapters.append({"video":"uppercuts.mp4","frame":frames,"label":cid+" 623"+button})
			var saved_arc:=false
			var saved_apex:=false
			for tick in range(100):
				var command:=Combat.neutral()
				if tick>=8 and tick<11:command=helper.relative(int("623"[tick-8]),1,(1 if button=="A" else 4) if tick==10 else 0)
				_step(command)
				var fighter=game.combat.fighters[0]
				if not saved_arc and fighter.move!=null and fighter.move_frame==fighter.move.startup+4:
					await _save("arc-"+cid+"-"+button+"-right");saved_arc=true
				if button=="C" and not saved_apex and not fighter.grounded and fighter.vy>=0:
					await _save("apex-"+cid);saved_apex=true
				if tick%2==0:await _frame()
	_reset_demo("nezuko","akaza",-1,false)
	for tick in range(40):
		var command:=Combat.neutral()
		if tick>=8 and tick<11:command=helper.relative(int("623"[tick-8]),-1,4 if tick==10 else 0)
		_step(command)
		var fighter=game.combat.fighters[0]
		if fighter.move!=null and fighter.move_frame==fighter.move.startup+4:
			await _save("arc-nezuko-C-left");break
	print("UPPERCUT VIDEO ",frames," frames")

func _video_step(command: Dictionary = {}, defend: Dictionary = {}) -> void:
	_step(command,defend)
	if video_tick%2==0:await _frame()

func _combo_video() -> void:
	video_folder=POLISH+"/combo-video";frames=0;video_tick=0
	DirAccess.make_dir_recursive_absolute(video_folder)
	for spec: Array in [["nezuko","623C","236236A"],["zenitsu","623A","236236AC"],["akaza","623C","236236A"]]:
		_reset_demo(spec[0],"tanjiro")
		chapters.append({"video":"uppercut-combos.mp4","frame":frames,"label":str(spec)})
		for tick in range(16):await _video_step()
		var route: Array=["5A","5C",spec[1],spec[2]]
		for index in range(route.size()):
			var fighter=game.combat.fighters[0]
			var prior: int=fighter.attack_instance
			var digits:="";var mask:=0
			for token in str(route[index]):
				if token in "123456789":digits+=token
				elif token in "ABCD":mask|=1<<"ABCD".find(token)
			var defend: Dictionary={} if index==0 else {"x":1}
			await _video_step({},defend)
			for n in range(digits.length()):
				await _video_step(helper.relative(int(digits[n]),1,mask if n==digits.length()-1 else 0),defend)
			for n in range(2):await _video_step(helper.relative(int(digits[-1]),1),defend)
			for n in range(90):
				if fighter.move!=null and fighter.confirmed and fighter.attack_instance!=prior:break
				await _video_step({},defend)
			if fighter.move==null or not fighter.confirmed:push_error("Combo capture failed: "+str(spec))
		for tick in range(90):await _video_step({},{"x":1})
		await _save("combo-"+spec[0])
	print("COMBO VIDEO ",frames," frames")

func _hd_stage() -> void:
	_reset_demo("nezuko","akaza",1,false)
	var current = game.view.stage.visual
	var baseline = current.duplicate()
	var image = Image.load_from_file("res://output/imagegen/fate-v1/raw/corps-courtyard.png")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://output/imagegen/fate-v1/imports/corps-courtyard.json"))
	var crop: Array = metadata.source.crop
	image = image.get_region(Rect2i(crop[0],crop[1],crop[2]-crop[0],crop[3]-crop[1]))
	image.generate_mipmaps()
	var baseline_layers: Array[Texture2D] = [ImageTexture.create_from_image(image)]
	var baseline_origins: Array[Vector2] = [Vector2.ZERO]
	baseline.layers=baseline_layers
	baseline.tile_origins=baseline_origins
	baseline.canvas_size=Vector2(image.get_size())
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160)]:
		root.size=size
		game.view.stage.set_visual(baseline)
		await _save("before-courtyard-%dx%d" % [size.x,size.y])
		game.view.stage.set_visual(current)
		await _save("courtyard-%dx%d" % [size.x,size.y])
	root.size=Vector2i(1280,720)
	video_folder=POLISH+"/courtyard-video";frames=0
	DirAccess.make_dir_recursive_absolute(video_folder)
	for tick in range(360):
		var center: float=lerpf(205.0,755.0,float(tick)/359)
		game.view.camera.center_x=center
		game.view.stage.sync_camera()
		for fighter in game.combat.fighters:
			fighter.x=center+(-40 if fighter.slot==0 else 40);fighter.previous_x=fighter.x
		for actor in game.view.fighters:
			actor.position=Vector2(actor.fighter.x,actor.fighter.y);actor.sync(1.0/60,true)
		game.view._process(0)
		if tick in [0,180,359]:await _save("courtyard-scroll-"+str(tick))
		if tick%2==0:await _frame()
	print("COURTYARD VIDEO ",frames," frames")
