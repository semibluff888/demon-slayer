extends SceneTree
const Support = preload("res://tests/combat_test_support.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
var helper := Support.new()
var catalog := Catalog.new()
var passed := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for cid in catalog.characters:
		for facing in [-1, 1]:
			for awakened in [false, true]:
				var model = helper.duel(cid, facing)
				var f = model.fighters[0]
				for move in model.definition(f).all_moves():
					if move.stance == "air" or move.kind == "throw": continue
					for held in [false, true]:
						model = helper.duel(cid, facing)
						f = model.fighters[0]
						model.practice = true
						model.fighters[1].x = f.x + facing * 350
						f.awakening_ticks = 600 if awakened else 0
						var actor = Actor.new()
						actor.fighter = f
						actor.combat = model
						actor.visual = catalog.characters[cid]
						helper.advance(model, 20, {"y":1})
						actor.sync(1.0/60, false)
						model._begin_move(f, move)
						actor.sync(1.0/60, false)
						var done := false
						for tick in range(240):
							helper.tick(model, {"y":1 if held else 0})
							actor.sync(1.0/60, model.hitstop > 0 or model.super_freeze > 0)
							if f.move == null and f.grounded and f.stun == 0:
								done = true
								check(f.state == ("crouch" if held else "idle"), move.id+" completion state")
								check(f.crouching == held, move.id+" completion hurtbox")
								check(actor.clip == ("crouch" if held else "idle") or (not held and actor.clip == "jump"), move.id+" completion clip")
								if held: check(actor.frame_index == actor._frames().get_frame_count("crouch")-1, move.id+" no standing crouch lead-in")
								break
						check(done, move.id+" finished")
						actor.free()
				for back in [false, true]:
					model = helper.duel(cid, facing)
					f = model.fighters[0]
					f.awakening_ticks = 600 if awakened else 0
					var throw_actor = Actor.new()
					throw_actor.fighter=f; throw_actor.combat=model; throw_actor.visual=catalog.characters[cid]
					helper.input(model,"4D" if back else "6D")
					var grabbed := false
					var recovered := false
					for tick in range(70):
						helper.tick(model,{"y":1})
						throw_actor.sync(1.0/60,false)
						grabbed = grabbed or f.throw_role == "thrower"
						if grabbed and f.throw_role.is_empty():
							recovered = true
							check(f.state == "crouch" and f.crouching, cid+" throw restores held crouch")
							check(throw_actor.clip == "crouch" and throw_actor.frame_index == throw_actor._frames().get_frame_count("crouch")-1, cid+" throw skips standing lead-in")
							break
					check(grabbed and recovered,cid+" throw played through actual input")
					throw_actor.free()
				# Fresh down still animates normally, even after earlier attacks.
				model = helper.duel(cid, facing)
				f = model.fighters[0]
				var fresh = Actor.new()
				fresh.fighter=f; fresh.combat=model; fresh.visual=catalog.characters[cid]
				fresh.sync(1.0/60,false)
				helper.tick(model,{"y":1}); fresh.sync(1.0/60,false)
				check(fresh.frame_index == 0, cid+" fresh crouch keeps transition")
				fresh.free()
	for failure in failures: printerr("FAIL: ", failure)
	print("MOTION FIXES: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)
