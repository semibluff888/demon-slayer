extends SceneTree
## Actual model + local atlases: phase, interruption, landing and linked throw checks.
const Support = preload("res://tests/combat_test_support.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Camera = preload("res://scripts/presentation/duel_camera.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
var passed := 0
var failures: Array[String] = []
var catalog := Catalog.new()
var helper := Support.new()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(message)

func matrix_duel(cid: String, facing: int, corner: bool) -> RefCounted:
	var model = helper.duel(cid,facing,corner)
	if corner:
		model.fighters[1].x = model.RIGHT if facing > 0 else model.LEFT
		model.fighters[0].x = model.fighters[1].x-facing*34
		for f in model.fighters: f.previous_x = f.x
	return model

func actor_for(model: RefCounted, slot: int = 0) -> Node2D:
	var actor := Actor.new()
	actor.combat = model
	actor.fighter = model.fighters[slot]
	actor.visual = catalog.characters[actor.fighter.character]
	return actor

func _run() -> void:
	for cid: String in catalog.characters:
		check(catalog.characters[cid].art_ready, cid + " complete phase-two assets")
		for facing in [-1, 1]:
			for corner in [false, true]:
				_test_normals(cid, facing, corner)
				_test_cancel(cid, facing, corner)
				_test_rolls(cid, facing, corner)
				_test_throws(cid, facing, corner, false)
				_test_throws(cid, facing, corner, true)
		for facing in [-1, 1]:
			_test_tech(cid, facing)
			_test_corner_visibility(cid, facing)
	for failure in failures:
		printerr("FAIL: ", failure)
	print("PHASE TWO BASICS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_normals(cid: String, facing: int, corner: bool) -> void:
	for key in ["5B", "5D", "2B", "2D", "jB", "jD"]:
		var model = matrix_duel(cid, facing, corner)
		var f = model.fighters[0]
		var move = model.definition(f).normals[key]
		var actor := actor_for(model)
		check(move.clip_id().begins_with("body_"), cid + key + " dedicated body drawing")
		f.move = move
		f.state = "attack"
		f.grounded = move.stance != "air"
		f.crouching = move.stance == "crouch"
		var visual = actor.visual
		if not visual.frames.has_animation(move.clip_id()):
			check(false, "missing " + cid + "/" + move.clip_id())
			actor.free()
			continue
		var cuts: Array = visual.phases[move.clip_id()]
		for tick in range(move.total_frames()):
			f.move_frame = tick
			actor.sync(0, false)
			var index: int = actor.frame_index
			if tick < move.startup:
				check(index < int(cuts[0]), key + " startup pose never implies contact")
			elif tick < move.startup + move.active:
				check(index >= int(cuts[0]) and index < int(cuts[1]), key + " effective pose follows effective logic")
			else:
				check(index >= int(cuts[1]), key + " recovery clearly retracts contact limb")
			check(actor.pose_facing() == facing, key + " mirrors around common root")
			var before: int = actor.frame_index
			actor.sync(0.5, true)
			check(actor.frame_index == before, key + " pause and stop hold pose")
		# A real airborne landing cancels the move; no lingering attack drawing.
		f.grounded = false
		f.y = model.FLOOR_Y - 0.1
		f.vy = 1
		f.move_frame = move.startup
		if move.stance == "air":
			helper.tick(model)
			actor.sync(0, false)
			check(f.move == null and actor.clip == "jump", key + " landing immediately removes aerial attack")
		# Contact from the opponent interrupts any existing body pose.
		f.move = move
		f.state = "attack"
		f.grounded = true
		f.hp = 1000
		f.y = model.FLOOR_Y
		var incoming = model.definition(model.fighters[1]).normals["5A"]
		model._resolve_contact({"attacker":1,"move":incoming,"instance":900,"segment":0,
			"facing":-facing,"blocked":false,"projectile":false,"airborne":false,"position":Vector2(f.x,f.y-36)})
		actor.consume(model.events, 0)
		actor.sync(0, true)
		check(f.move == null and actor.clip == "hit" and actor.frame_index == 0, key + " hit interrupts without old pose or trail")
		actor.free()

func _test_rolls(cid: String, facing: int, corner: bool) -> void:
	for backward in [false, true]:
		var model = matrix_duel(cid, facing, corner)
		var f = model.fighters[0]
		var actor := actor_for(model)
		helper.input(model, "4AB" if backward else "AB")
		var observed := {"safe":false,"vulnerable":false,"recovery":false}
		for n in range(35):
			if f.roll_frame >= 0:
				actor.sync(0, false)
				check(actor.clip == ("roll_back" if backward else "roll_forward"), "ground roll has dedicated sequence")
				if f.strike_invulnerable():
					observed.safe = true
					check(actor.frame_index >= 2 and actor.frame_index <= 7, "tucked drawings delimit invulnerability")
				if f.roll_frame >= 18 and f.roll_frame < 20:
					observed.vulnerable = true
					check(actor.frame_index == 8, "planting feet signals vulnerability before travel ends")
				if f.roll_frame >= 20:
					observed.recovery = true
					check(actor.frame_index >= 9, "last eight frames show dangerous recovery")
			helper.tick(model)
		check(observed.safe and observed.vulnerable and observed.recovery, "all roll phases observed through real input")
		actor.free()

func _test_throws(cid: String, facing: int, corner: bool, backward: bool) -> void:
	var model = matrix_duel(cid, facing, corner)
	# Same-character matches must choose victim role from the current throw.
	model.fighters[1].character = cid
	var a := actor_for(model)
	var b := actor_for(model, 1)
	helper.input(model, "4D" if backward else "6D")
	var grabbed := false
	var impact := false
	for tick in range(70):
		if not model.throw_link.is_empty():
			grabbed = true
			a.sync(0, false)
			b.sync(0, false)
			check(a.clip == ("throw_success" if backward else "throw_forward"), "throw direction chooses thrower drawings")
			check(b.clip == ("thrown" if backward else "thrown_forward"), "victim shares chosen throw direction")
			check(a.pose_facing() == facing and b.pose_facing() == facing, "linked throw orientation mirrors once")
			if model.fighters[1].throw_frame == 20:
				impact = true
				check(b.frame_index == 8, "victim ground contact drawing matches slam logic")
		helper.tick(model)
	check(grabbed and impact, "direction throw reached actual grab and impact")
	a.free()
	b.free()

func _test_tech(cid: String, facing: int) -> void:
	var model = helper.duel(cid, facing)
	var a := actor_for(model)
	var b := actor_for(model, 1)
	helper.input(model, "6D")
	for n in range(10):
		if not model.throw_link.is_empty():
			break
		helper.tick(model)
	helper.tick(model, {}, {"buttons":8})
	a.sync(0, true)
	b.sync(0, true)
	check(a.clip == "throw_tech" and b.clip == "throw_tech", "both fighters break grip with dedicated tech drawings")
	check(a.frame_index == 0 and b.frame_index == 0, "tech stop holds initial grip break")
	var hp: int = model.fighters[1].hp
	helper.advance(model, 24)
	a.sync(0, false)
	b.sync(0, false)
	check(model.fighters[0].reaction.is_empty() and a.clip != "throw_tech", "tech animation ends with existing recovery")
	check(model.fighters[1].hp == hp, "tech presentation adds no damage")
	a.reset_pose()
	check(a.afterimages.is_empty() and a.texture == null, "reset clears all presentation state")
	a.free()
	b.free()

func _test_cancel(cid: String, facing: int, corner: bool) -> void:
	var model = matrix_duel(cid, facing, corner)
	var actor := actor_for(model)
	helper.input(model, "5B")
	check(helper.wait_contact(model), "body strike confirms with actual input")
	actor.sync(0, true)
	check(actor.clip == "body_stand_light", "body contact presents body pose")
	helper.input(model, "5C")
	for n in range(20):
		if model.fighters[0].move == model.definition(model.fighters[0]).normals["5C"]:
			break
		helper.tick(model)
	actor.consume(model.events, 0)
	actor.sync(0, false)
	check(actor.clip == "stand_heavy" and actor.afterimages.is_empty(), "confirmed cancel switches to sword startup without old trails")
	actor.free()

func _test_corner_visibility(cid: String, facing: int) -> void:
	var model = matrix_duel(cid,facing,true)
	model.fighters[1].character = cid
	var victim := actor_for(model,1)
	var camera := Camera.new()
	camera.reset(model.fighters)
	for backwards in [false,true]:
		var f = victim.fighter
		f.throw_role = "victim"
		f.throw_facing = facing
		f.throw_back = backwards
		for tick in range(20,30):
			f.throw_frame = tick
			victim.sync(0,false)
			var bounds: Rect2 = victim.visual_bounds()
			var left: float = camera.point(Vector2(f.x+bounds.position.x,f.y)).x
			var right: float = camera.point(Vector2(f.x+bounds.end.x,f.y)).x
			check(left>=2 and right<=1278,"corner throw victim silhouette fits with hit shake reserve")
	victim.free()
