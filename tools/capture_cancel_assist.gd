extends "res://tools/capture_fate_revisions.gd"
## Fixed-tick direction/button playback through the real command recognizer.
const ASSIST_OUT="res://artifacts/menu-settings"
var finishing_damage:=0
var finishing_hits:=0
var blocks:=0
var capture_failures: Array[String]=[]
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ASSIST_OUT)
	var settings=preload("res://scripts/game_settings.gd").new()
	settings.path=ASSIST_OUT+"/combo-capture-settings.cfg";settings.save_config()
	root.size=Vector2i(1280,720)
	game=Main.instantiate();game.settings.path=settings.path;root.add_child(game)
	game.set_physics_process(false);game.sound.muted=true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]:node.set_process(false)
	await process_frame
	video_folder=ASSIST_OUT+"/combo-video";frames=0;video_tick=0
	DirAccess.make_dir_recursive_absolute(video_folder)
	for spec: Array in [["nezuko","C",false],["zenitsu","A",true],["akaza","C",false],["tanjiro","A",true]]:
		_reset_demo(spec[0],"tanjiro" if spec[0]!="tanjiro" else "akaza")
		finishing_damage=0;finishing_hits=0;blocks=0
		chapters.append({"frame":frames,"character":spec[0],"uppercut":spec[1],"max":spec[2]})
		for n in range(24):await _video_step()
		for notation: String in ["5A","5C","623"+spec[1]]:
			var fighter=game.combat.fighters[0]
			var previous: int=fighter.attack_instance
			var digits:="";var mask:=0
			for token in notation:
				if token in "123456789":digits+=token
				elif token in "ABCD":mask|=1<<"ABCD".find(token)
			var guard: Dictionary={} if notation=="5A" else {"x":1}
			await _video_step({},guard)
			for n in range(digits.length()):await _video_step(helper.relative(int(digits[n]),1,mask if n==digits.length()-1 else 0),guard)
			for n in range(2):await _video_step(helper.relative(int(digits[-1]),1),guard)
			for n in range(90):
				if fighter.move!=null and fighter.confirmed and fighter.attack_instance!=previous:break
				await _video_step({},guard)
			if fighter.move==null or not fighter.confirmed:capture_failures.append("Unconfirmed route: "+str(spec)+notation)
		# Six ticks to react after contact, then three ticks for each direction.
		for n in range(6):await _video_step({},{"x":1})
		for digit in "236236":
			for n in range(3):await _video_step(helper.relative(int(digit),1),{"x":1})
		await _video_step(helper.relative(6,1,5 if spec[2] else 1),{"x":1})
		for n in range(160):
			await _video_step({},{"x":1})
			if n==7:await _save("combo-"+spec[0])
		if finishing_damage!=(445 if spec[2] else 280) or blocks!=0:capture_failures.append("Incomplete ending: "+str(spec))
		evidence.append({"character":spec[0],"uppercut":spec[1],"max":spec[2],"reaction_ticks":6,"direction_hold_ticks":3,"finisher_damage":finishing_damage,"finisher_hits":finishing_hits,"blocks":blocks})
	var file=FileAccess.open(ASSIST_OUT+"/combo-capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"chapters":chapters,"frames":frames,"routes":evidence,"failures":capture_failures,"method":"Godot production rendering, real held direction/button inputs, 60 Hz logic, 30 FPS silent capture."},"  "))
	game.queue_free();await process_frame
	for failure in capture_failures:printerr("FAIL: ",failure)
	print("CANCEL CAPTURE: ",frames," frames, ",capture_failures.size()," failed")
	quit(0 if capture_failures.is_empty() else 1)
func _video_step(command: Dictionary={},defender: Dictionary={}) -> void:
	_step(command,defender)
	for event: Dictionary in game.combat.events:
		if event.type=="block":blocks+=1
		if event.type=="hit" and (event.move.ends_with("_super") or event.move.ends_with("_max")):
			finishing_damage+=event.damage;finishing_hits+=1
	if video_tick%2==0:await _frame()
func _save(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ASSIST_OUT+"/"+name+".png")
