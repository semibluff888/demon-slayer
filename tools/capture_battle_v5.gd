extends SceneTree
## Actual OpenGL captures driven by held directions/buttons, no forced attack poses.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Support = preload("res://tests/combat_test_support.gd")
const AI = preload("res://scripts/ai_controller.gd")
var game: Node2D
var helper := Support.new()
var captures: Array[Dictionary] = []
var video_frame: int = 0
var audio_events: Array[Dictionary] = []
var video_cues: Array[Dictionary] = []
var quick: bool = false
var video: bool = false
var performance: bool = false
var letterbox_only: bool = false
var folder: String = "res://artifacts/battle-v5"
var global_tick: int = 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	quick = "--quick" in args
	video = "--video" in args
	performance = "--performance" in args
	letterbox_only = "--letterbox" in args
	_run.call_deferred()

func _run() -> void:
	if quick: folder += "/quick"
	elif video: folder += "/video"
	elif not performance: folder += "/matrix"
	DirAccess.make_dir_recursive_absolute(folder)
	game = Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:
		node.set_process(false)
	if letterbox_only:
		root.size = Vector2i(1600,1000)
		await _case(1600,"tanjiro","idle",1,false,0)
		var index_path := folder+"/captures.json"
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(index_path)) if FileAccess.file_exists(index_path) else {"captures":[]}
		var kept: Array = previous.captures.filter(func(c: Dictionary) -> bool: return c.path != captures[0].path)
		kept.append(captures[0])
		previous.captures = kept
		_json(index_path,previous)
	elif performance:
		await _performance()
	elif video:
		root.size = Vector2i(1920,1080)
		DirAccess.make_dir_recursive_absolute(folder+"/audio")
		for kind: String in game.sound.streams:
			game.sound.streams[kind].save_to_wav(folder+"/audio/"+kind+".wav")
		for cid in ["tanjiro","zenitsu"]:
			for notation in ["236236A","236236AC"]:
				await _case(1920,cid,notation,1,false,0)
		_json(folder+"/cues.json",{"fps":30,"frames":video_frame,"resolution":[1920,1080],"cues":video_cues,"audio_events":audio_events,"audio_pauses":[],"audio_method":"Actual Godot PCM mixed at the recorded 60Hz event ticks.","method":"Actual OpenGL with real held combat inputs"})
	else:
		for width in ([1280] if quick else [960,1280,1920,2560,3840]):
			root.size = Vector2i(width,width*9/16)
			await _case(width,"tanjiro","idle",1,false,0)
			for cid in ["tanjiro","zenitsu"]:
				for notation in ["236236A","236236AC"]:
					await _case(width,cid,notation,1,false,0)
					if not quick:
						await _case(width,cid,notation,-1,true,-1)
						await _case(width,cid,notation,1,true,1)
			if not quick:
				await _case(width,"tanjiro","both",1,false,0)
				await _case(width,"zenitsu","details",1,false,0)
				await _case(width,"tanjiro","meters",1,false,0)
				await _case(width,"tanjiro","236A",1,false,0)
				await _case(width,"tanjiro","623A",1,false,0)
				await _case(width,"tanjiro","214D",1,false,0)
		if not quick:
			root.size = Vector2i(1600,1000)
			await _case(1600,"tanjiro","idle",1,false,0)
		_json(folder+"/captures.json",{"captures":captures,"method":"Actual OpenGL; 60Hz input-driven attacks; central and exact arena edges; same-character matches"})
	game.queue_free()
	await process_frame
	print("BATTLE CAPTURE COMPLETE ",captures.size()," images / ",video_frame," video frames")
	quit()

func _case(width: int, cid: String, notation: String, facing: int, mirror: bool, edge: int) -> void:
	game.mode = "practice"
	game.characters.assign([cid,cid if mirror else ("zenitsu" if cid=="tanjiro" else "tanjiro")])
	game.start_match()
	game.view.hud.practice_details = notation=="details"
	var model = game.combat
	var a = model.fighters[0]
	var b = model.fighters[1]
	if edge!=0:
		b.x = Combat.LEFT if edge<0 else Combat.RIGHT
		a.x = b.x-facing*48
	else:
		a.x = 435 if notation in ["idle","details","meters","both"] else 465
		b.x = 575 if notation in ["idle","details","meters","both"] else 520
	if notation=="meters":
		a.hp = 210
		b.hp = 560
		a.meter = 175
		b.meter = 300
	if notation=="both": b.meter = 300
	if notation=="236A": b.x = a.x+facing*110
	a.facing = facing
	b.facing = -facing
	for f in model.fighters:
		f.input.last_facing = f.facing
		f.previous_x = f.x
	game.view.reset_effects()
	var motion := ""
	var mask := 0
	for token in ("236236AC" if notation=="both" else notation):
		if token in "123456789": motion+=token
		if token in "ABCD": mask|=1<<"ABCD".find(token)
	var saved := {}
	var key := "%d-%s-%s-%s-%s" % [width,cid,notation,"left" if facing<0 else "right",str(edge)]
	var begin_frame := video_frame
	var count := 150 if video else (3 if notation in ["idle","details","meters"] else 105)
	for tick in range(count):
		var held := Combat.neutral()
		var other := Combat.neutral()
		var input_start := 25 if video else 6
		if tick>=input_start and tick<input_start+motion.length():
			held = helper.relative(int(motion[tick-input_start]),facing,mask if tick==input_start+motion.length()-1 else 0)
			if notation=="both":
				other = helper.relative(int(motion[tick-input_start]),-facing,mask if tick==input_start+motion.length()-1 else 0)
		model.step([held,other])
		game.practice_controller.after_step(model)
		game.view.consume(model.events)
		for cue: Dictionary in game.sound.cues(model.events,model):
			if video: audio_events.append({"tick":global_tick,"kind":cue.kind,"gain":cue.gain})
		_sync()
		await process_frame
		await RenderingServer.frame_post_draw
		var phase := ""
		if notation in ["idle","details","meters"] and tick==2:
			phase = notation
		elif not game.view.super_view.active.is_empty() and model.super_freeze>0 and game.view.super_view.active[0].age>=0.10:
			phase = "charge"
		elif a.move!=null and a.move.segment(a.move_frame)>=0 and a.move.segment_progress(a.move_frame)>=0.35:
			phase = "active"
		if saved.has("active") and a.combo>=3 and not saved.has("combo"): phase = "combo"
		if video and tick%2==0:
			root.get_texture().get_image().save_jpg(folder+"/frame-%05d.jpg" % video_frame,0.93)
			video_frame+=1
		if not phase.is_empty() and not saved.has(phase):
			var path := folder+"/"+key+"-"+phase+".png"
			_window_capture().save_png(path)
			captures.append({"path":path,"size":[root.size.x,root.size.y],"phase":phase,"tick":tick,"character":cid,"move":notation,"edge":edge,"mirror":mirror,"viewport_size":[root.get_texture().get_size().x,root.get_texture().get_size().y],"letterbox_composited":root.get_texture().get_size()!=Vector2(root.size)})
			saved[phase] = true
		global_tick+=1
	if video:
		video_cues.append({"character":cid,"move":notation,"start_frame":begin_frame,"end_frame":video_frame})
	print("CAPTURED ",key)

func _sync() -> void:
	game.view._process(1.0/60)
	game.view.effects._process(1.0/60)
	game.view.super_view._process(1.0/60)
	game.view.hud._process(1.0/60)
	game.view.stage._process(1.0/60)

func _performance() -> void:
	var reports: Array[Dictionary] = []
	for width in [1920,3840]:
		root.size = Vector2i(width,width*9/16)
		game.mode = "practice"
		game.characters.assign(["tanjiro","zenitsu"])
		game.start_match()
		var first_ai := AI.new(193)
		var second_ai := AI.new(311)
		for n in range(90):
			_sync()
			await process_frame
		var samples: Array[float] = []
		var previous := Time.get_ticks_usec()
		for n in range(1800):
			game.combat.step([first_ai.command(game.combat.fighters[0].observable(),game.combat.fighters[1].observable()),second_ai.command(game.combat.fighters[1].observable(),game.combat.fighters[0].observable())])
			game.practice_controller.after_step(game.combat)
			game.view.consume(game.combat.events)
			_sync()
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous=now
		samples.sort()
		var total: float = samples.reduce(func(a: float,b: float): return a+b,0.0)
		var report := {"resolution":[width,width*9/16],"frames":1800,"mean_frame_ms":total/1800,"p95_frame_ms":samples[1710],"p99_frame_ms":samples[1782],"gpu":RenderingServer.get_video_adapter_name(),"under_60fps_budget":samples[1710]<16.67}
		reports.append(report)
		print("PERFORMANCE ",report)
	_json(folder+"/performance.json",{"runs":reports,"method":"Actual OpenGL; 1800 AI combat frames; capture and encoding excluded; includes display pacing."})

func _json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  "))


func _window_capture() -> Image:
	var content := root.get_texture().get_image()
	if content.get_size()==root.size:
		return content
	# KEEP renders only the content viewport. Reproduce the engine's window bars
	# around those real pixels; the manifest explicitly identifies this composite.
	var window_image := Image.create(root.size.x,root.size.y,false,content.get_format())
	window_image.fill(Color.BLACK)
	window_image.blit_rect(content,Rect2i(Vector2i.ZERO,content.get_size()),(root.size-content.get_size())/2)
	return window_image
