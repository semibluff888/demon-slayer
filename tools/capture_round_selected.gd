extends SceneTree
## Real production scene captures. The two complete rounds use ordinary combat inputs.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Flow = preload("res://scripts/round_flow.gd")
const Arena = preload("res://scripts/arena_rules.gd")
var game: Node2D
var output := "res://artifacts/round-selected/"
var captures: Array[Dictionary] = []
var movies: Array[Dictionary] = []
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func save_json(path: String, data: Variant) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	if picture.save_jpg(path,0.94)!=OK:failures.append("Cannot save "+path)
func update_view(delta: float) -> void:
	for node in [game.view,game.view.effects,game.view.super_view,game.view.hud,game.view.stage]:node._process(delta)
func _run() -> void:
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for directory in ["frames","matrix","audio"]:DirAccess.make_dir_recursive_absolute(output+directory)
	game=Main.instantiate();root.add_child(game);game.set_physics_process(false);game.mode="local"
	for node in [game.view,game.view.effects,game.view.super_view,game.view.hud,game.view.stage]:node.set_process(false)
	game.sound.muted=true
	if not "--matrix-only" in OS.get_cmdline_user_args():
		await full_round("tanjiro","zenitsu")
		await full_round("zenitsu","tanjiro")
	await matrix()
	save_json(output+"capture.json",{"method":"Godot production main scene, OpenGL, fixed 60 Hz, real inputs for full rounds; controlled KO state setup for edge matrix", "movies":movies,"captures":captures,"failures":failures})
	game.queue_free();await process_frame
	for failure in failures:printerr("FAIL: ",failure)
	print("ROUND SELECTED CAPTURE: %d movies, %d screenshots, %d failed" % [movies.size(),captures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
func full_round(winner: String, loser: String) -> void:
	game.characters.assign([winner,loser]);game.start_match();game.sound.muted=true
	var c=game.combat;c.fighters[1].hp=40
	var directory:=output+"frames/"+winner+"-wins";DirAccess.make_dir_recursive_absolute(directory)
	var audio: Array[Dictionary]=[];var moments: Dictionary={};var frames:=0
	for tick in range(800):
		update_view(0 if tick==0 else 1.0/60)
		if c.phase=="intro" and c.actor_intro_ticks()==60: await shot(output+winner+"-opening.jpg")
		if c.phase=="round_end":
			if not moments.has("ko"):moments.ko=tick
			if c.outro_ticks==c.victory_at+100:await shot(output+winner+"-wins.jpg")
		await shot(directory+"/frame-%05d.jpg"%frames);frames+=1
		var a:=Combat.neutral();var b:=Combat.neutral()
		if c.phase=="fight":
			if absf(c.fighters[0].x-c.fighters[1].x)>33:
				a.x=1;b.x=-1
			else:a.buttons=1 if tick%8<4 else 0
		var previous: String=c.phase;c.step([a,b])
		if previous=="round_end" and c.phase!="round_end":break
		game.view.consume(c.events)
		for cue: Dictionary in game.sound.cues(c.events,c):
			audio.append({"tick":tick+1,"kind":cue.kind,"gain":cue.gain})
			game.sound.streams[cue.kind].save_to_wav(output+"audio/"+cue.kind+".wav")
	if c.wins!=[1,0]:failures.append(winner+" real input round failed to end")
	var info:={"name":winner+"-wins","frames":frames,"fps":60,"events":audio,"moments":moments}
	movies.append(info);save_json(output+winner+"-wins.json",info)
	print("MOVIE ",winner," ",frames," frames")
func record_pose(name: String,slot: int) -> void:
	update_view(1.0/60)
	var actor=game.view.fighters[slot];var f=game.combat.fighters[slot]
	await shot(output+"matrix/"+name+".jpg")
	captures.append({"name":name,"width":root.size.x,"character":f.character,"clip":actor.clip,"drawing":actor.frame_index,"x":f.x,"y":f.y,"zoom":game.view.camera.zoom,"root_screen":[actor.position.x,actor.position.y],"scale":[actor.scale.x,actor.scale.y]})
func matrix() -> void:
	for width in [960,1280,1920]:
		root.size=Vector2i(width,width*9/16)
		for cid in ["tanjiro","zenitsu"]:
			for facing in [-1,1]:
				var other: String="zenitsu" if cid=="tanjiro" else "tanjiro"
				game.characters.assign([other,cid]);game.start_match()
				var c=game.combat;var f=c.fighters[1]
				f.x=480-facing*100;f.facing=facing;c.fighters[0].x=480+facing*100;c.fighters[0].facing=-facing
				var prefix:="%d-%s-%s"%[width,cid,"left" if facing<0 else "right"]
				for age in [0,60,119,120]:
					c.phase_frames=Flow.OPENING-age
					await record_pose(prefix+"-opening-%03d"%age,1)
				for scenario in ["ground","air","corner","throw"]:
					game.start_match();c=game.combat;f=c.fighters[1];c.phase="fight"
					f.facing=facing;f.x=480-facing*17;c.fighters[0].x=480+facing*17
					c.fighters[0].facing=-facing
					if scenario=="corner":f.x=Arena.LEFT if facing>0 else Arena.RIGHT;c.fighters[0].x=f.x+facing*34
					if scenario=="air":f.y-=70;f.grounded=false
					f.hp=0;f.state="hit"
					if scenario=="throw":f.throw_frame=Arena.THROW_TICKS;f.throw_facing=facing;f.state="knockdown"
					c._finish_round();game.view.reset_effects()
					var saved: Array[int]=[]
					for tick in range(Flow.RESULT_AT+1):
						update_view(1.0/60)
						var drawing: int=game.view.fighters[1].frame_index
						if game.view.fighters[1].clip in ["round_defeat", "thrown", "thrown_forward"] and not drawing in saved:
							saved.append(drawing)
							if width==1280 and scenario=="ground" or drawing in [4,7,11]:await record_pose(prefix+"-"+scenario+"-%02d"%drawing,1)
						c.step([Combat.neutral(),Combat.neutral()])
					if not 11 in saved:failures.append(prefix+scenario+" missing final hold")
				# Winner uses selected victory after an actual settlement.
				game.start_match();c=game.combat;c.phase="fight";c.fighters[0].hp=0;c.fighters[1].facing=facing;c._finish_round()
				for age in [0,52,104,119]:
					while c.outro_ticks<c.victory_at+age:c.step([Combat.neutral(),Combat.neutral()])
					await record_pose(prefix+"-victory-%03d"%age,1)
	root.size=Vector2i(1280,720)