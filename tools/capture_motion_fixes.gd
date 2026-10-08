extends "res://tools/capture_roster_expansion.gd"
const DEST := "res://artifacts/motion-fixes"
var report: Array[Dictionary] = []
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DEST)
	root.size=Vector2i(1280,720)
	game=Main.instantiate(); root.add_child(game)
	game.set_physics_process(false); game.sound.muted=true
	for node in [game.view,game.view.effects,game.view.hud,game.view.stage,game.view.super_view]: node.set_process(false)
	await process_frame
	for cid in ["nezuko","akaza","zenitsu"]:
		for awakened in [false,true]:
			for facing in [-1,1]:
				for back in [false,true]:
					_setup(cid,awakened,facing)
					_step({"x":(-facing if back else facing),"buttons":8})
					for tick in range(52):
						_step()
						var f = game.combat.fighters[0]
						if f.throw_frame in [3,8,13,18,20,23,29] and game.combat.hitstop == 0:
							await _capture("%s-%s-%d-%s-%02d" % [cid,"awake" if awakened else "normal",facing,"back" if back else "forward",f.throw_frame])
					await _capture("%s-%s-%d-%s-end" % [cid,"awake" if awakened else "normal",facing,"back" if back else "forward"])
	for awakened in [false,true]:
		for notation in ["236A","236C","214B","214D","236236A","236236AC"]:
			_setup("nezuko",awakened,1)
			game.combat.fighters[1].x=800
			helper.input(game.combat,notation)
			for tick in range(95):
				_step()
				if tick in [0,7,14,21,28,40,60,94]:await _capture("nezuko-%s-%s-%02d" % ["awake" if awakened else "normal",notation,tick])
	var file=FileAccess.open(DEST+"/captures.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	game.queue_free();await process_frame
	print("MOTION CAPTURE COMPLETE: ",report.size());quit()
func _setup(cid: String, awakened: bool, facing: int) -> void:
	game.mode="practice";game.characters.assign([cid,"tanjiro"]);game.stage_id="infinity_castle";game.start_match()
	game.combat.phase="fight"
	var a=game.combat.fighters[0];var b=game.combat.fighters[1]
	a.x=480;b.x=480+facing*34;a.facing=facing;b.facing=-facing
	a.input.last_facing=facing;b.input.last_facing=-facing
	a.awakening_ticks=600 if awakened else 0
	for f in game.combat.fighters:f.previous_x=f.x
	game.view.camera.reset(game.combat.fighters);_step()
func _capture(label: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(DEST+"/"+label+".png")
	var actor=game.view.fighters[0]
	report.append({"file":label+".png","clip":actor.clip,"frame":actor.frame_index,"state":actor.fighter.state})
