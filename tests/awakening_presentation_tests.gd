extends SceneTree
const Art = preload("res://scripts/presentation/visual_catalog.gd")
const Combat = preload("res://scripts/combat.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const HUD = preload("res://scripts/presentation/hud_view.gd")
var passed: int = 0
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label); printerr("FAIL: ",label)
func _run() -> void:
	var art := Art.new()
	for cid in ["tanjiro","zenitsu","nezuko","akaza"]:
		var combat := Combat.new()
		combat.new_match(cid,cid)
		combat.phase = "fight"
		var actor := Actor.new()
		actor.combat = combat
		actor.fighter = combat.fighters[0]
		actor.visual = art.characters[cid]
		root.add_child(actor)
		actor.sync(0,false)
		var fx = actor.awakening_effects
		check(not fx.visible,cid+" ordinary state has no alternate VFX")
		actor.fighter.awakening_ticks = 600
		actor.fighter.awakening_duration = 600
		actor.sync(0.1,false)
		check(fx.visible == (cid != "akaza"),cid+" new VFX only on redesigned fighters")
		if cid != "akaza":
			check(fx.textures.size()==4 and fx.textures.all(func(t): return t != null),cid+" four VFX textures imported")
			check(art.characters[cid].awakened_portrait.resource_path.ends_with("awakening/portrait.png"),cid+" new portrait selected")
			var phase: float = fx.phase
			var snapshot := combat.snapshot()
			actor.sync(2.0,true)
			check(is_equal_approx(fx.phase,phase) and snapshot==combat.snapshot(),cid+" freeze holds VFX without changing combat")
			actor.fighter.state = "hit"
			actor.fighter.stun = 12
			actor.sync(0.1,false)
			check(is_equal_approx(fx.phase,phase+0.1),cid+" reaction does not restart VFX")
			actor.fighter.awakening_ticks = 0
			actor.sync(0,false)
			check(not fx.visible,cid+" expiration removes VFX")
			actor.fighter.awakening_ticks = 200
			actor.fighter.hp = 0
			actor.sync(0,false)
			check(not fx.visible,cid+" KO removes VFX")
		actor.reset_pose()
		check(is_zero_approx(fx.phase),cid+" reset clears VFX clock")
		actor.queue_free()
		await process_frame
	print("AWAKENING PRESENTATION V2: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
