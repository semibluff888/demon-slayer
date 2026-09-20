extends SceneTree
const Support = preload("res://tests/combat_test_support.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Effects = preload("res://scripts/presentation/effects_view.gd")
const Sound = preload("res://scripts/audio.gd")
const Main = preload("res://scenes/main.tscn")
var helper := Support.new()
var catalog := Catalog.new()
var sound: Node
var passed := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else: failures.append(message)

func matrix_duel(cid: String, facing: int, corner: bool) -> RefCounted:
	var model = helper.duel(cid,facing,corner)
	if corner:
		model.fighters[1].x = model.RIGHT if facing > 0 else model.LEFT
		model.fighters[0].x = model.fighters[1].x-facing*34
		for f in model.fighters: f.previous_x = f.x
	return model

func actor_for(model: RefCounted) -> Node2D:
	var actor := Actor.new()
	actor.combat = model
	actor.fighter = model.fighters[0]
	actor.visual = catalog.characters[actor.fighter.character]
	return actor

func _run() -> void:
	sound = Sound.new()
	root.add_child(sound)
	sound.muted = true
	for cid: String in catalog.characters:
		for facing in [-1,1]:
			for corner in [false,true]:
				for notation in ["214B","214D","236236A","236236AC"]:
					_test_segments(cid,facing,corner,notation)
			_test_cancel_and_interrupt(cid,facing)
		_test_whiff_and_resources(cid)
	_test_feedback()
	await _test_lifecycle()
	var file := FileAccess.open("res://artifacts/phase2/segment-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	for failure in failures: printerr("FAIL: ",failure)
	print("PHASE TWO FEEDBACK: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_segments(cid: String, facing: int, corner: bool, notation: String) -> void:
	var model = matrix_duel(cid,facing,corner)
	model.fighters[1].character = cid
	model.fighters[0].meter = 300
	var actor := actor_for(model)
	helper.input(model,notation)
	var move: Resource = model.fighters[0].move
	check(move != null, "special entered through actual direction/button input")
	if move == null:
		actor.free()
		return
	check(move.presentation != null, move.id+" has independent presentation resource")
	var actual_shapes := {"tanjiro_214B":"water_vortex","tanjiro_214D":"water_vortex","tanjiro_super":"water_dragon","tanjiro_max":"sun_arc","zenitsu_214B":"iai_return","zenitsu_214D":"iai_return","zenitsu_super":"sixfold","zenitsu_max":"godspeed"}
	check(move.clip_id() == actual_shapes[move.id], move.id+" uses dedicated motion")
	var frames_by_segment := {}
	var freeze_checked := false
	for tick in range(180):
		var f = model.fighters[0]
		actor.sync(1.0/60,model.hitstop>0 or model.super_freeze>0)
		if f.move == move:
			var segment: int = move.segment(f.move_frame)
			if segment >= 0:
				if not frames_by_segment.has(segment): frames_by_segment[segment] = []
				if not actor.frame_index in frames_by_segment[segment]: frames_by_segment[segment].append(actor.frame_index)
			if model.hitstop>0 or model.super_freeze>0:
				var before: int = actor.frame_index
				var ghost_before: Array = actor.afterimages.duplicate(true)
				actor.sync(0.7,true)
				check(actor.frame_index==before and actor.afterimages==ghost_before,"stops hold current contact drawing and trails")
				freeze_checked = true
		helper.tick(model)
	var hits: Array = helper.events.filter(func(e: Dictionary) -> bool: return e.type=="hit" and e.get("move","")==move.id)
	var strikes: Array = helper.events.filter(func(e: Dictionary) -> bool: return e.type=="strike" and e.move==move.id)
	check(hits.size()==move.hit_count(),move.id+" exact real hit count both directions/corners")
	check(strikes.size()==move.hit_count(),move.id+" exactly one audible strike per segment")
	check(freeze_checked,"real hitstop/super stop observed")
	check(frames_by_segment.size()==move.hit_count(),move.id+" every segment has a drawn phase")
	if move.hit_count()>1:
		var previous_max := -1
		for n in range(move.hit_count()):
			var observed: Array = frames_by_segment.get(n,[])
			check(not observed.is_empty(),"each segment presents its own contact drawings")
			if not observed.is_empty():
				check(observed.min()>previous_max,"consecutive strikes do not reuse earlier segment poses")
				previous_max = observed.max()
	for n in range(hits.size()):
		check(int(hits[n].segment)==n, "actual contact order matches drawn and audible sequence")
	evidence.append({"character":cid,"notation":notation,"facing":facing,"corner":corner,"mirror":true,"hits":hits.size(),"strike_cues":strikes.size(),"frames_by_segment":frames_by_segment})
	actor.free()

func _test_cancel_and_interrupt(cid: String, facing: int) -> void:
	var model = helper.duel(cid,facing)
	model.fighters[0].meter = 300
	var actor := actor_for(model)
	helper.input(model,"214B")
	check(helper.wait_contact(model),"special confirms before super cancel")
	helper.input(model,"236236A")
	for n in range(25):
		if model.fighters[0].move == model.definition(model.fighters[0]).motions["super"]: break
		helper.tick(model)
	actor.sync(0,false)
	check(actor.clip == model.definition(model.fighters[0]).motions["super"].clip_id(),"cancel shows exclusive super startup")
	var incoming = model.definition(model.fighters[1]).normals["5C"]
	model._resolve_contact({"attacker":1,"move":incoming,"instance":999,"segment":0,"facing":-facing,"blocked":false,"projectile":false,"airborne":false,"position":Vector2(model.fighters[0].x,250)})
	actor.consume(model.events,0)
	actor.sync(0,true)
	check(actor.clip=="hit" and actor.afterimages.is_empty(),"interruption clears exclusive super pose and all ghosts")
	actor.free()

func _test_whiff_and_resources(cid: String) -> void:
	var model = helper.duel(cid)
	model.fighters[1].x = model.fighters[0].x + 220
	helper.input(model,"5D")
	helper.advance(model,70)
	check(not helper.events.any(func(e: Dictionary) -> bool: return e.type in ["hit","block"]),"whiff has no false contact feedback")
	check(helper.events.filter(func(e: Dictionary) -> bool: return e.type=="strike").size()==1,"whiff retains one audible swing")
	check(model.fighters[0].meter==0,"whiff does not gain meter")
	model = helper.duel(cid)
	helper.input(model,"236236AC")
	check(helper.events.filter(func(e: Dictionary) -> bool: return e.type=="meter_empty").size()==1,"empty meter cues exactly once")
	check(model.fighters[0].move==null,"empty meter never falls back to another attack")
	var cues: Array = sound.cues(helper.events,model)
	check(cues.filter(func(c: Dictionary) -> bool: return c.kind=="meter_empty").size()==1,"resource rejection has dedicated tone")
	model = helper.duel(cid)
	model.fighters[0].meter = 300
	helper.input(model,"236236AC")
	var spend: Array = helper.events.filter(func(e: Dictionary) -> bool: return e.type=="meter" and e.amount<0)
	check(spend.size()==1 and spend[0].amount==-300,"MAX spends once before freeze")
	cues = sound.cues(helper.events,model)
	check(cues.any(func(c: Dictionary) -> bool: return c.kind=="max") and cues.any(func(c: Dictionary) -> bool: return c.kind=="meter_spend"),"MAX charge and meter spend have separate cues")

func _test_feedback() -> void:
	var model = helper.duel("zenitsu")
	var effects := Effects.new()
	effects.combat = model
	var move: Resource = model.definition(model.fighters[0]).motions["super"]
	var event := {"type":"hit","attacker":0,"move":move.id,"instance":123,"segment":0,"position":Vector2(520,250)}
	effects.consume([event])
	var first_trauma: float = effects.trauma
	var first_sparks: int = effects.sparks.size()
	effects.reset_effects()
	event.segment = 2
	effects.consume([event])
	check(effects.trauma<first_trauma*0.6 and effects.sparks.size()<first_sparks,"middle hits reduce shake and sparks")
	var rings: Array = effects.rings.duplicate(true)
	var sparks: Array = effects.sparks.duplicate(true)
	effects.freeze = true
	effects._process(0.5)
	check(effects.rings==rings and effects.sparks==sparks,"hitstop and pause freeze feedback particles")
	var before: Dictionary = model.snapshot()
	effects.freeze = false
	effects._process(0.5)
	check(model.snapshot()==before,"render effects never mutate combat")
	check(effects.sparks.is_empty() and effects.rings.is_empty(),"feedback expires without accumulation")
	effects.consume([{"type":"throw_tech","position":Vector2(500,250)},{"type":"clash","position":Vector2(500,250)}])
	check(effects.pulses.size()==1 and effects.rings.is_empty(),"tech suppresses duplicate clash flash")
	var cues: Array = sound.cues([{"type":"throw_tech"},{"type":"clash"}],model)
	check(cues.size()==1 and cues[0].kind=="throw_tech","tech suppresses duplicate clash audio")
	effects.consume([{"type":"round_end"}])
	check(effects.pulses.is_empty() and effects.sparks.is_empty() and effects.trauma==0,"round finish clears transient feedback")
	check(sound.streams.hit.data!=sound.streams.body_hit.data and sound.streams.block.data!=sound.streams.throw_tech.data,"hit/body/block/tech sound designs are distinct")
	effects.free()

func _test_lifecycle() -> void:
	var game := Main.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	game.choose_mode("practice")
	game.start_match()
	game.combat._tech_throw()
	game.view.consume(game.combat.events)
	await process_frame
	game.set_paused(true)
	await process_frame
	var pulse: Array = game.view.effects.pulses.duplicate(true)
	var frame: int = game.view.fighters[0].frame_index
	for n in range(3): await process_frame
	check(game.view.effects.pulses==pulse and game.view.fighters[0].frame_index==frame,"real app pause holds tech pose and pulses")
	check(game.sound.paused,"pause reaches audio lifecycle")
	game.set_paused(false)
	check(not game.sound.paused,"resume releases audio lifecycle")
	game.reset_practice()
	check(game.view.effects.pulses.is_empty() and game.view.fighters[0].afterimages.is_empty(),"practice reset clears all new feedback")
	game.queue_free()
	await process_frame
