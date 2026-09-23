extends SceneTree
const Support = preload("res://tests/combat_test_support.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Arena = preload("res://scripts/arena_rules.gd")
const Commands = preload("res://scripts/command_recognizer.gd")
var helper := Support.new()
var catalog := Catalog.new()
var passed := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for cid in ["tanjiro","zenitsu"]:
		for facing in [-1,1]:
			_jump(cid,facing)
			for notation in ["236236A","236236AC"]:
				for distance in [34,240]:
					_trails(cid,facing,notation,distance)
	for failure in failures: printerr("FAIL: ",failure)
	print("COMBAT POLISH TESTS: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _flight(cid: String, facing: int, mode: String, air_attack: bool = false) -> Dictionary:
	var model = helper.duel(cid,facing)
	var f = model.fighters[0]
	model.fighters[1].x = f.x + facing * 200
	if mode.begins_with("dash") or mode == "backdash":
		var direction: int = -facing if mode == "backdash" else facing
		helper.tick(model,{"x":direction})
		helper.tick(model)
		helper.tick(model,{"x":direction})
		check(f.dash_ticks>0,"real double tap starts dash")
	var start: float = f.x
	var axis := facing
	if mode in ["neutral","dash-neutral","backdash"]: axis = 0
	if mode == "back" or mode == "dash-reverse": axis = -facing
	helper.tick(model,{"x":axis,"y":-1})
	check(f.dash_ticks==0 and not f.grounded,"jump ends dash state")
	var positions: Array[Vector2] = [Vector2(f.x-start,f.y)]
	var attack_seen := false
	for tick in range(60):
		var held := {"buttons":Commands.C} if air_attack and tick==8 else {}
		helper.tick(model,held)
		attack_seen = attack_seen or (f.move!=null and f.move.stance=="air")
		positions.append(Vector2(f.x-start,f.y))
		if f.grounded: break
	if air_attack: check(attack_seen,"dash jump allows the existing air attack")
	return {"positions":positions,"distance":f.x-start,"grounded":f.grounded,"vx":f.vx}

func _jump(cid: String, facing: int) -> void:
	var normal := _flight(cid,facing,"normal")
	for mode in ["dash","dash-neutral"]:
		var running := _flight(cid,facing,mode)
		check(running.positions.size()==normal.positions.size(),"dash jump keeps exact flight duration")
		for index in range(mini(normal.positions.size(),running.positions.size())):
			check(is_equal_approx(normal.positions[index].y,running.positions[index].y),"dash jump keeps per-tick height")
			check(is_equal_approx(normal.positions[index].x*1.5,running.positions[index].x),"dash jump covers 1.5x distance per tick")
		check(running.grounded and running.vx==0,"landing clears inherited speed")
	var backward := _flight(cid,facing,"back")
	var reverse := _flight(cid,facing,"dash-reverse")
	check(is_equal_approx(backward.distance,reverse.distance),"reverse cancels forward dash before ordinary back jump")
	check(is_zero_approx(_flight(cid,facing,"neutral").distance),"neutral jump remains vertical")
	check(is_zero_approx(_flight(cid,facing,"backdash").distance),"backdash neutral jump keeps existing behavior")
	var air_normal := _flight(cid,facing,"normal",true)
	var air_dash := _flight(cid,facing,"dash-neutral",true)
	check(is_equal_approx(air_dash.distance,air_normal.distance*1.5),"air attack retains dash momentum without changing normal movement")
	var model = helper.duel(cid,facing)
	var f = model.fighters[0]
	f.x = Arena.RIGHT-8 if facing>0 else Arena.LEFT+8
	model.fighters[1].x = f.x-facing*100
	f.dash_ticks = 10
	f.dash_direction = facing
	f.dash_back = false
	f.state = "dash"
	helper.tick(model,{"y":-1})
	helper.advance(model,40)
	check(f.x>=Arena.LEFT and f.x<=Arena.RIGHT and f.vx==0,"dash jump respects stage wall and stops there")

	# Outward takeoff still obeys the shared screen-distance clamp.
	model = helper.duel(cid,facing)
	f = model.fighters[0]
	f.x = 480
	model.fighters[1].x = f.x-facing*Arena.MAX_SEPARATION
	f.previous_x = f.x
	model.fighters[1].previous_x = model.fighters[1].x
	f.dash_ticks=10
	f.dash_direction=facing
	f.dash_back=false
	f.state="dash"
	var opponent_x: float = model.fighters[1].x
	helper.tick(model,{"y":-1})
	helper.advance(model,40)
	check(absf(f.x-model.fighters[1].x)<=Arena.MAX_SEPARATION+0.001,"dash jump respects maximum fighter separation")
	check(is_equal_approx(model.fighters[1].x,opponent_x),"screen clamp never drags opponent")
	# A dash cancelled by body contact must not grant later momentum.
	model=helper.duel(cid,facing)
	f=model.fighters[0]
	f.dash_ticks=10
	f.dash_direction=facing
	f.dash_back=false
	f.state="dash"
	helper.advance(model,4)
	check(f.dash_ticks==0,"body contact cancels dash")
	helper.tick(model,{"y":-1})
	check(is_zero_approx(f.vx),"jump after body collision cannot inherit a stopped dash")

func _trails(cid: String, facing: int, notation: String, distance: float) -> void:
	var model = helper.duel(cid,facing)
	model.fighters[1].x = model.fighters[0].x+facing*distance
	model.fighters[0].meter = 300
	var actor := Actor.new()
	actor.combat = model
	actor.fighter = model.fighters[0]
	actor.visual = catalog.characters[cid]
	helper.input(model,notation)
	var move: Resource = model.fighters[0].move
	check(move!=null and move.is_super(),"actual input activates intended super")
	if move==null:
		actor.free()
		return
	var profile = move.presentation
	check(profile.trail_lifetime >= (0.29 if profile.super_tier == 2 else 0.23), "extended lifetime survives the former fade window")
	check(profile.trail_interval * profile.trail_count + 0.001 >= profile.trail_lifetime, "sample capacity preserves the configured lifetime")
	var oldest_age := 0.0
	var maximum := 0
	var started_without_hitbox := false
	var recovery_cleared := false
	for tick in range(150):
		actor.consume(model.events,0)
		var before: Dictionary = model.snapshot()
		actor.sync(1.0/60,model.hitstop>0 or model.super_freeze>0)
		check(model.snapshot()==before,"trail drawing cannot mutate simulation")
		maximum = maxi(maximum,actor.afterimages.size())
		check(actor.afterimages.size()<=profile.trail_count,"bounded afterimage count")
		if not actor.afterimages.is_empty():
			for ghost in actor.afterimages:
				oldest_age = maxf(oldest_age, ghost.duration - ghost.life)
				var ink := actor.trail_modulate(ghost)
				check(ink.b > ink.r and ink.b > ink.g, "all four supers retain a distinct cool silhouette")
				check(ghost.facing==facing and ghost.texture!=null and ghost.duration>0,"ghost retains sampled facing, texture and lifetime")
			var frozen: Array = actor.afterimages.duplicate(true)
			actor.sync(0.5,true)
			check(actor.afterimages==frozen,"pause/hitstop freezes ghost positions and lifetimes")
			if model.fighters[0].move==move and model.fighters[0].move_frame<move.startup:
				started_without_hitbox = true
		if model.fighters[0].move==move and model.fighters[0].move_frame>=move.startup+move.active+15:
			recovery_cleared = recovery_cleared or actor.afterimages.is_empty()
		helper.tick(model)
	check(oldest_age > (0.20 if profile.super_tier == 2 else 0.16), "samples actually persist beyond the old lifetime while emitting")
	check(maximum>0,"super and MAX both create visible ghosts on hit or whiff")
	check(started_without_hitbox,"startup animation can emit before attack hitbox")
	check(recovery_cleared and actor.afterimages.is_empty(),"recovery expires old ghosts")
	model.fighters[0].meter=300
	model._begin_move(model.fighters[0],move)
	actor.sync(0.1,false)
	model.fighters[0].move=null
	model.fighters[0].state="hit"
	model.fighters[0].stun=12
	actor.sync(0,true)
	check(actor.afterimages.is_empty(),"interruption clears all ghosts immediately")
	actor.reset_pose()
	check(actor.last_trail_pose.is_empty() and actor.afterimages.is_empty(),"reset clears sampling history")
	actor.free()

