extends SceneTree
## GPU acceptance for complete finishing skills and both lethal throw directions.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Flow = preload("res://scripts/round_flow.gd")
const Arena = preload("res://scripts/arena_rules.gd")
var game: Node2D
var output := "res://artifacts/round-polish/"
var movies: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func save_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  ")); file.close()
func refresh(delta: float = 1.0 / 60) -> void:
	for node in [game.view,game.view.effects,game.view.super_view,game.view.hud,game.view.stage]: node._process(delta)
func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()
func _run() -> void:
	root.size = Vector2i(1280,720); root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for directory in ["frames","matrix","audio"]: DirAccess.make_dir_recursive_absolute(output+directory)
	game = Main.instantiate(); root.add_child(game); game.set_physics_process(false); game.mode = "local"
	for node in [game.view,game.view.effects,game.view.super_view,game.view.hud,game.view.stage]: node.set_process(false)
	game.sound.muted = true
	for cid in ["tanjiro","zenitsu"]:
		for back in [false,true]:
			for facing in [1,-1]:
				await ending("%s-throw-%s-%s" % [cid,"back" if back else "forward","right" if facing > 0 else "left"],cid,"",back,facing,facing > 0)
	for id in ["tanjiro_623C","tanjiro_max","zenitsu_super","zenitsu_max"]:
		await ending(id,"tanjiro" if id.begins_with("tanjiro") else "zenitsu",id,false,1,true)
	save_json(output+"capture.json",{"method":"Production main.tscn GPU rendering; low-HP fixtures, actual move and linked throw resolution; raw full-viewport pixel hashes through every KO freeze tick", "movies":movies,"captures":captures,"failures":failures})
	game.queue_free(); await process_frame
	for failure in failures: printerr("FAIL: ",failure)
	print("ROUND POLISH CAPTURE: %d movies, %d scenarios, %d failed" % [movies.size(),captures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
func ending(name: String,cid: String,move_id: String,back: bool,facing: int,film: bool) -> void:
	game.characters.assign([cid,"zenitsu" if cid=="tanjiro" else "tanjiro"]); game.start_match(); game.sound.muted=true
	var c=game.combat; c.phase="fight"
	var a=c.fighters[0]; var d=c.fighters[1]
	a.x=480; d.x=480+facing*34; a.facing=facing; d.facing=-facing; a.meter=300; d.hp=1
	game.view.reset_effects()
	var directory := output+"frames/"+name
	if film: DirAccess.make_dir_recursive_absolute(directory)
	var audio: Array[Dictionary] = []; var trace: Array[Dictionary] = []; var moments: Dictionary = {}
	var freezes: Array[String] = []; var freeze_reference: PackedByteArray; var frames := 0
	var elapsed := -1; var landing_images: Array[int] = []; var strikes: Array[int] = []
	for frame in range(700):
		if frame == 18:
			c.events.clear()
			if move_id.is_empty():
				a.throw_back=back; c._start_throw(c._contact(a,d,c.definition(a).throw_move,1,0,false))
			else: c._begin_move(a,c.moves[move_id])
			consume_audio(c,frame,audio)
		refresh(0 if frame==0 else 1.0/60)
		elapsed = c.lethal_throw_ticks if c.lethal_throw_ticks>=0 else (c.outro_ticks if c.phase=="round_end" else -1)
		if elapsed==0 and not moments.has("ko"): moments.ko=frame
		if c.phase=="round_end" and c.outro_ticks==c.victory_at and not moments.has("victory"): moments.victory=frame
		if c.phase=="round_end" and a.move==null and not moments.has("recovered"): moments.recovered=frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		if film:
			if picture.save_jpg(directory+"/frame-%05d.jpg" % frames,0.94)!=OK: failures.append(name+" cannot save frame")
		frames+=1
		if elapsed>=0 and elapsed<Flow.FREEZE:
			var bytes := picture.get_data()
			if freezes.is_empty(): freeze_reference=bytes
			elif bytes!=freeze_reference: failures.append(name+" rendered freeze changed at tick "+str(elapsed))
			freezes.append(digest(bytes))
		if elapsed in [0,Flow.FREEZE-1,Flow.FREEZE,Flow.FREEZE+Flow.SLOW] or (c.phase=="round_end" and c.outro_ticks in [c.victory_at,c.victory_at+100]):
			picture.save_jpg(output+"matrix/"+name+"-ko-%03d.jpg" % elapsed,0.94)
		if move_id.is_empty() and d.throw_frame in [19,20,29,30] and d.throw_frame not in landing_images:
			landing_images.append(d.throw_frame)
			picture.save_jpg(output+"matrix/"+name+"-throw-%02d.jpg" % d.throw_frame,0.94)
		var actors: Array[Dictionary] = []
		for slot in range(2):
			var actor=game.view.fighters[slot]; var f=c.fighters[slot]
			actors.append({"character":f.character,"clip":actor.clip,"drawing":actor.frame_index,"pose_facing":actor.pose_facing(),"root_screen":[actor.position.x,actor.position.y],"world":[f.x,f.y],"move_frame":f.move_frame,"throw_frame":f.throw_frame,"scale":actor.scale.x})
		trace.append({"frame":frame,"elapsed":elapsed,"speed":c.presentation_speed(),"victory_at":c.victory_at,"actors":actors})
		var previous: String=c.phase
		c.step([Combat.neutral(),Combat.neutral()])
		if previous=="round_end" and c.phase!="round_end": break
		for event: Dictionary in c.events:
			if event.type=="strike": strikes.append(event.segment)
		consume_audio(c,frame+1,audio)
	if c.wins!=[1,0]: failures.append(name+" did not finish exactly one round")
	if freezes.size()!=Flow.FREEZE: failures.append(name+" did not capture exactly nine frozen pictures")
	if not moments.has("victory"): failures.append(name+" did not reach victory")
	if move_id=="zenitsu_super" and strikes!=[0,1,2,3,4,5]: failures.append(name+" did not finish all six cuts: "+str(strikes))
	var info := {"name":name,"frames":frames,"fps":60,"events":audio,"moments":moments,"freeze_hashes":freezes,"strikes":strikes,"winner":a.character,"loser":d.character,"throw":move_id.is_empty(),"back":back,"facing":facing,"film":film}
	captures.append(info)
	if film: movies.append(info)
	save_json(output+name+".json",info); save_json(output+name+"-trace.json",trace)
	print("CAPTURE ",name," ",frames," frames, ",freezes.size()," frozen pictures, cuts ",strikes)
func consume_audio(c: RefCounted,tick: int,audio: Array[Dictionary]) -> void:
	game.view.consume(c.events)
	for cue: Dictionary in game.sound.cues(c.events,c):
		audio.append({"tick":tick,"kind":cue.kind,"gain":cue.gain})
		game.sound.streams[cue.kind].save_to_wav(output+"audio/"+cue.kind+".wav")