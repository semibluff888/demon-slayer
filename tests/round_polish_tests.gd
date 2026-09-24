extends SceneTree
## Regression for the reported KO interruptions, thrown orientation and whole-scene stop.
const Main = preload("res://scenes/main.tscn")
const Combat = preload("res://scripts/combat.gd")
const Flow = preload("res://scripts/round_flow.gd")
const Arena = preload("res://scripts/arena_rules.gd")
var game: Node2D
var failures: Array[String] = []
var passed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func _initialize() -> void: _run.call_deferred()
func refresh(delta: float = 1.0/60) -> void:
	for node in [game.view,game.view.effects,game.view.super_view,game.view.hud,game.view.stage]:node._process(delta)
func step() -> void:
	game.combat.step([Combat.neutral(),Combat.neutral()]);game.view.consume(game.combat.events);refresh()
func duel(cid: String) -> void:
	game.characters.assign([cid,"zenitsu" if cid=="tanjiro" else "tanjiro"]);game.start_match()
	var c=game.combat;c.phase="fight";c.fighters[0].x=480;c.fighters[1].x=514;c.fighters[0].meter=300
	game.view.reset_effects();refresh(0)
func visual_state() -> Array:
	return [game.view.time,game.view.stage.time,game.view.effects.time,game.view.hud.time,
		game.view.camera.center_x,game.view.camera.shake,game.view.fighters[0].frame_index,
		game.view.fighters[1].frame_index,game.view.effects.sparks.duplicate(true),game.view.super_view.active.duplicate(true)]
func _run() -> void:
	game=Main.instantiate();root.add_child(game);game.set_physics_process(false);game.mode="local";game.sound.muted=true
	for node in [game.view,game.view.effects,game.view.super_view,game.view.hud,game.view.stage]:node.set_process(false)
	_skills()
	_throws()
	_projectiles()
	for failure in failures:printerr("FAIL: ",failure)
	print("ROUND POLISH TESTS: %d passed, %d failed" % [passed,failures.size()])
	game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
func _skills() -> void:
	for id in ["tanjiro_236A","tanjiro_623C","tanjiro_214D","tanjiro_super","tanjiro_max","zenitsu_236C","zenitsu_623C","zenitsu_214D","zenitsu_super","zenitsu_max"]:
		duel("tanjiro" if id.begins_with("tanjiro") else "zenitsu")
		var c=game.combat;var a=c.fighters[0];var d=c.fighters[1];d.hp=1
		var move: Resource=c.moves[id]
		c._begin_move(a,move);game.view.consume(c.events)
		for tick in range(130):
			step()
			if c.phase=="round_end":break
		check(c.phase=="round_end",id+" fixture lands a lethal hit")
		if c.phase!="round_end":continue
		check(a.move==move and c.presents_attack(0),id+" keeps finishing skill and effect drawing enabled")
		var frame: int=a.move_frame;var at:=Vector2(a.x,a.y);var frozen:=visual_state();var meters:=[a.meter,d.meter]
		var cue_age: float=c.presentation_time_ticks()
		for tick in range(Flow.FREEZE-1):
			step()
			check(visual_state()==frozen and Vector2(a.x,a.y)==at and a.move_frame==frame,id+" freezes actors, background, camera, HUD, sparks and cut-in")
		check(c.presentation_time_ticks()==cue_age,id+" super cue clock also freezes")
		while c.outro_ticks<Flow.FREEZE+Flow.SLOW:step()
		check(a.move_frame==frame+7,id+" 30 slow ticks advance 7 whole skill ticks")
		check(c.presentation_time_ticks()==cue_age+7.5,id+" effects share the quarter-speed clock")
		var seen_last := false;var delayed := false;var future_strikes := 0
		for tick in range(240):
			if c.outro_ticks>=c.victory_at:break
			if a.move!=null:
				var actor=game.view.fighters[0]
				check(actor.clip==move.clip_id(),id+" never replaces an unfinished move with victory")
				seen_last=seen_last or actor.frame_index==actor.visual.frames.get_frame_count(move.clip_id())-1
				if c.outro_ticks>=Flow.RESULT_AT:delayed=true
			step()
			for event: Dictionary in c.events:
				if event.type=="strike":future_strikes+=1
				check(event.type not in ["hit","throw","block","meter"],id+" finishing skill has no further gameplay contacts")
			check(d.hp==0 and a.hp==1000 and c.wins==[1,0] and meters==[a.meter,d.meter],id+" settlement and meter stay fixed")
		check(a.move==null and a.grounded and c.outro_ticks>=c.victory_at,id+" victory waits for the complete skill and landing")
		check(seen_last,id+" recovery reaches the final authored drawing")
		check(game.view.fighters[0].clip=="round_victory" and game.view.fighters[0].frame_index==0,id+" victory begins at frame zero after recovery")
		if id=="zenitsu_super":check(delayed and c.victory_at>Flow.RESULT_AT,"sixfold extends result boundary to finish all six cuts")
		var start: int=c.outro_ticks
		for tick in range(Flow.RESULT-1):step()
		check(c.phase=="round_end" and c.outro_ticks==start+Flow.RESULT-1,id+" retains the full two-second winner display")
		step();check(c.phase=="intro",id+" advances next round only after complete winner display")
func _throws() -> void:
	for cid in ["tanjiro","zenitsu"]:
		for facing in [-1,1]:
			for back in [false,true]:
				duel(cid)
				var c=game.combat;var a=c.fighters[0];var d=c.fighters[1]
				a.facing=facing;d.facing=-facing;a.x=480;d.x=480+facing*34;a.throw_back=back;d.hp=1
				c._start_throw(c._contact(a,d,c.definition(a).throw_move,1,0,false));game.view.consume(c.events)
				for tick in range(Arena.THROW_IMPACT_TICK):step()
				check(d.hp==0 and c.phase=="fight" and c.wins==[0,0],"lethal throw keeps original impact-before-settlement order")
				check(c.lethal_throw_ticks==0 and c.presentation_speed()==0,"lethal throw freezes at the actual impact")
				var at:=Vector2(d.x,d.y);var actor=game.view.fighters[1];var frozen:=visual_state();var announces:=0;var previous_drawing: int=actor.frame_index
				for tick in range(Flow.FREEZE-1):
					step();check(visual_state()==frozen and d.throw_frame==Arena.THROW_IMPACT_TICK,"throw impact is one full-scene freeze")
				for tick in range(140):
					if c.phase=="round_end" and c.outro_ticks>=Flow.RESULT_AT:break
					step()
					for event: Dictionary in c.events:
						if event.type=="ko_announce":announces+=1
					check(Vector2(d.x,d.y)==at and d.grounded,"throw victim never repeats the landing or lifts from floor")
					check(actor.pose_facing()==facing,"forward/back thrown facing survives opponent-facing update")
					check(actor.clip==("thrown" if back else "thrown_forward"),"lethal throw retains its own landing artwork")
					check(actor.frame_index>=previous_drawing,"thrown landing never rewinds to impact")
					previous_drawing=actor.frame_index
				check(announces==1 and c.wins==[1,0],"one KO announcement and one throw score")
				check(actor.frame_index==11 and c.defeat_frame(1)==11,"fully landed throw holds its final drawing")
func _projectiles() -> void:
	duel("tanjiro")
	var c=game.combat;var a=c.fighters[0];var d=c.fighters[1]
	c._begin_move(a,c.moves.tanjiro_236A);c._spawn_projectile(a);c.super_freeze=0;d.hp=0;c._finish_round();game.view.consume(c.events);refresh(0)
	check(c.projectiles.size()==1,"KO does not delete a launched effect")
	var x: float=c.projectiles[0].x;var vx: float=c.projectiles[0].vx
	for tick in range(Flow.FREEZE):step()
	check(c.projectiles[0].x==x,"launched effect holds during KO freeze")
	for tick in range(Flow.SLOW):step()
	check(is_equal_approx(c.projectiles[0].x-x,vx*7.5),"launched effect moves at quarter speed")
	for tick in range(160):
		if c.phase!="round_end":break
		step();check(d.hp==0 and c.wins==[1,0],"post-KO projectile can never hit or score again")