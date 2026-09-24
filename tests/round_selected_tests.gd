extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const Flow = preload("res://scripts/round_flow.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Main = preload("res://scenes/main.tscn")
var failures: Array[String] = []
var passed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func step(c: RefCounted, n: int) -> void:
	for tick in range(n): c.step([Combat.neutral(),Combat.neutral()])
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var visuals := Catalog.new()
	for cid in ["tanjiro","zenitsu"]:
		var v = visuals.characters[cid]
		check(v.art_ready,"selected production assets load: "+cid)
		for clip in ["round_intro","round_victory","round_defeat"]:
			check(v.state_animations[clip] == clip,"explicit selected state mapping")
			check(v.frames.get_frame_count(clip) == (12 if clip=="round_defeat" else 18),"complete selected drawing sequence")
			check(not v.frames.get_animation_loop(clip),"selected action holds its ending")
			for i in range(v.frames.get_frame_count(clip)):
				var texture: AtlasTexture = v.frames.get_frame_texture(clip,i)
				check(texture.get_size()==Vector2(1024,640) and "res://art/characters/" in texture.atlas.resource_path,"production path and shared registration")
		check(v.source_height==340 and v.canonical_height==70,"same ruler as normal combat")
		var c := Combat.new()
		c.new_match(cid,cid)
		var actor := Actor.new();actor.combat=c;actor.fighter=c.fighters[0];actor.visual=v
		actor.sync(0,true)
		check(actor.clip=="round_intro" and actor.frame_index==0,"opening starts at first drawing")
		step(c,119);actor.sync(0,false)
		check(actor.frame_index==17 and c.remaining==3600 and c.round_cue().is_empty(),"full two-second opening precedes timer and text")
		step(c,1);actor.sync(0,false)
		check(actor.clip=="idle" and c.round_cue().text=="ROUND 1","opening returns to combat idle before text")
		actor.free()
	for cid in ["tanjiro","zenitsu"]:
		for facing in [-1,1]:
			for airborne in [false,true]:
				var c := Combat.new();c.new_match(cid,cid);c.phase="fight"
				var f = c.fighters[1];f.hp=0;f.facing=facing;f.x=480-facing*17
				c.fighters[0].x=480+facing*17
				f.grounded=not airborne;f.y=Arena.FLOOR_Y-(70 if airborne else 0)
				c._finish_round();var start:=Vector2(f.x,f.y)
				step(c,Flow.FREEZE)
				check(Vector2(f.x,f.y)==start,"finishing pose root freezes before recoil")
				for tick in range(Flow.RESULT_AT-Flow.FREEZE):
					c.step([Combat.neutral(),Combat.neutral()])
					check(c.defeat_frame(1)<6 if not f.grounded else c.defeat_frame(1)>=6,"air drawings never release sword or touch floor")
				check(f.grounded and is_equal_approx(f.y,Arena.FLOOR_Y),"air and grounded KO finish on floor")
				check((f.x-start.x)*-facing>100,"KO travels more than 100 world units backward")
				check(c.defeat_frame(1)==11,"defeat finishes before victory display")
				var landed_x: float=f.x;step(c,60)
				check(f.x==landed_x and c.defeat_frame(1)==11,"final prone drawing and detached sword stay still")
	# Both losers stay within the fixed camera's playable span, including ranged double KOs.
	for distance in [34,200,300,360]:
		var c:=Combat.new();c.phase="fight"
		for slot in range(2): c.fighters[slot].x=480+(distance/2.0)*(1 if slot else -1);c.fighters[slot].hp=0
		c._finish_round();step(c,Flow.RESULT_AT)
		check(absf(c.fighters[0].x-c.fighters[1].x)<=Arena.MAX_SEPARATION+0.001,"double KO stays within camera span")
		check(c.wins==[0,0] and c.defeat_frame(0)==11 and c.defeat_frame(1)==11,"double KO settles both without score")
	# Real lethal throw: impact happens before KO and the grounded victim must not relaunch.
	for cid in ["tanjiro","zenitsu"]:
		var c:=Combat.new();c.new_match(cid,cid);c.phase="fight"
		c.fighters[0].x=463;c.fighters[1].x=497;c.fighters[1].hp=1
		c._start_throw(c._contact(c.fighters[0],c.fighters[1],c.definition(c.fighters[0]).throw_move,1,0,false))
		for tick in range(90):
			if c.phase=="round_end":break
			c.step([Combat.neutral(),Combat.neutral()])
		check(c.phase=="round_end" and c.throw_link.is_empty() and c.outro_paths[1].thrown,"lethal throw settles only after linked landing")
		var landed:=Vector2(c.fighters[1].x,c.fighters[1].y)
		for tick in range(Flow.RESULT_AT):
			c.step([Combat.neutral(),Combat.neutral()])
			check(Vector2(c.fighters[1].x,c.fighters[1].y)==landed,"lethal throw never launches the landed body again")
		check(c.defeat_frame(1)==11,"lethal throw joins final defeat and sword release")
	# A timed-out loser still has HP and must never snap into a KO drawing.
	var timed := Combat.new();timed.phase="fight";timed.wins=[1,0];timed.fighters[1].hp=500;timed.remaining=0;timed._finish_round()
	step(timed,Flow.OUTRO)
	var survivor := Actor.new();survivor.combat=timed;survivor.fighter=timed.fighters[1];survivor.visual=visuals.characters.zenitsu;survivor.sync(0,false)
	check(timed.phase=="match_end" and survivor.clip=="idle","timeout final result retains the living loser pose")
	survivor.free()
	await _pause_and_corners()
	for failure in failures:printerr("FAIL: ",failure)
	print("ROUND SELECTED TESTS: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
func _pause_and_corners() -> void:
	var game:=Main.instantiate();root.add_child(game);game.set_physics_process(false);game.mode="local";game.sound.muted=true
	game.start_match();game.view._process(0);game.set_paused(true)
	var snap: Dictionary=game.combat.snapshot()
	for tick in range(20):game._physics_process(1.0/60);game.view._process(1.0/60)
	check(game.combat.snapshot()==snap and game.view.fighters[0].frame_index==0,"pause freezes both selected openings")
	game.set_paused(false)
	for cid in ["tanjiro","zenitsu"]:
		for facing in [-1,1]:
			game.characters.assign([cid,cid]);game.start_match()
			var c=game.combat;c.phase="fight"
			var victim=c.fighters[1];victim.x=Arena.LEFT if facing>0 else Arena.RIGHT;victim.hp=0;victim.facing=facing
			c.fighters[0].x=victim.x+facing*34
			c._finish_round();step(c,Flow.RESULT_AT);game.view._process(1.0/60)
			var actor=game.view.fighters[1]
			var bounds: Rect2=actor.visual_bounds();var a: Vector2=game.view.camera.point(Vector2(victim.x+bounds.position.x,victim.y));var b: Vector2=game.view.camera.point(Vector2(victim.x+bounds.end.x,victim.y))
			check(a.x>=0 and b.x<=1280,"corner defeated body and sword fit by panning")
			check(game.view.camera.zoom==3 and actor.scale==Vector2(3,3) and actor._pose_scale()==Vector2.ONE,"corner presentation keeps normal character scale")
	game.start_match();check(game.combat.outro_paths==[{},{}],"restart clears all recoil roots")
	game.queue_free();await process_frame