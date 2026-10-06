extends SceneTree
const Support = preload("res://tests/combat_test_support.gd")
const Catalog = preload("res://scripts/presentation/visual_catalog.gd")
const Actor = preload("res://scripts/presentation/fighter_view.gd")
const Effects = preload("res://scripts/presentation/effects_view.gd")
var helper := Support.new()
var passed := 0
var failures: Array[String] = []
var measurements: Array = []
const IDS = ["tanjiro","zenitsu","nezuko","akaza"]

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)

func _run() -> void:
	var catalog = Catalog.new()
	_mirror()
	_trajectories(catalog)
	_routes()
	_recovery()
	_interruptions()
	DirAccess.make_dir_recursive_absolute("res://artifacts/uppercut-polish")
	var output := FileAccess.open("res://artifacts/uppercut-polish/verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":passed,"failures":failures,"trajectories":measurements},"  "))
	for failure in failures: printerr("FAIL: ",failure)
	print("UPPERCUT POLISH: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _mirror() -> void:
	var effects = Effects.new()
	var model = helper.duel("nezuko")
	var move = model.definition(model.fighters[0]).motions["623A"]
	for progress: float in [0.0,0.25,0.5,0.75,1.0]:
		for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,Vector2(0.2,0.7)]:
			# Expected = previous rendered output sampled at horizontal reflection.
			var reflected := Vector2(1-corner.x,corner.y)
			var expected: Vector2 = effects.effect_uv(reflected,lerpf(0.65,1.35,progress),true)
			var actual: Vector2 = effects.effect_uv(corner,effects.element_angle(move,progress),move.presentation.texture_flip_h)
			check(expected.is_equal_approx(actual),"rising arc is an exact output-space horizontal mirror")
	effects.free()

func _trajectories(catalog: RefCounted) -> void:
	for cid: String in IDS:
		for button: String in ["A","C"]:
			for facing: int in [-1,1]:
				var model = helper.duel(cid,facing)
				model.fighters[1].x = 480 + facing*190
				helper.input(model,"623"+button)
				var fighter = model.fighters[0]
				var move = model.definition(fighter).motions["623"+button]
				var actor = Actor.new()
				actor.combat=model;actor.fighter=fighter;actor.visual=catalog.characters[cid]
				var peak := 0.0
				var air_count := 0
				var land_frame := -1
				var ready_frame := -1
				var was_air := false
				var invalid_startup := false
				var premature_rest := false
				for tick in range(110):
					if fighter.move != null and fighter.move_frame <= move.lift_frame and not fighter.grounded: invalid_startup=true
					helper.tick(model)
					actor.sync(0,true)
					peak=maxf(peak,model.FLOOR_Y-fighter.y)
					if not fighter.grounded:
						air_count+=1;was_air=true
						if fighter.move != null and fighter.move_frame >= move.startup+move.active:
							if actor.frame_index >= actor.visual.frames.get_frame_count(actor.clip)-1: premature_rest=true
					elif was_air and land_frame<0: land_frame=tick
					if was_air and fighter.move==null:
						ready_frame=tick
						break
				var label := "%s 623%s facing %d" % [cid,button,facing]
				check(not invalid_startup,"startup stays grounded: "+label)
				check(absf(peak-(37.18 if button=="A" else 58.14))<0.01,"measured light/heavy apex: "+label)
				check(air_count==(26 if button=="A" else 33),"measured 60Hz airtime: "+label)
				check(land_frame>=0 and ready_frame-land_frame>=(10 if button=="A" else 13),"punishable landing recovery: "+label)
				check(not premature_rest,"airborne recovery never uses planted final pose: "+label)
				check(fighter.grounded and is_zero_approx(fighter.y-model.FLOOR_Y),"clean landing: "+label)
				measurements.append({"character":cid,"button":button,"facing":facing,"height_world":peak,"air_frames":air_count,"landing_recovery":ready_frame-land_frame})
				actor.free()

func _routes() -> void:
	for cid: String in IDS:
		for victim: String in IDS:
			for facing: int in [-1,1]:
				for corner: bool in [false,true]:
					for button: String in ["A","C"]:
						for ending: String in ["236236A","236236AC"]:
							var model = helper.duel(cid,facing,corner)
							model.fighters[1].character=victim
							model.fighters[0].meter=300
							var route: Array = ["5A","5C","623"+button,ending]
							var label := "%s -> %s %s facing %d corner %s" % [cid,victim,str(route),facing,str(corner)]
							var connected := true
							for index in range(route.size()):
								var guard := {} if index==0 else {"x":facing}
								helper.input(model,route[index],guard)
								connected=helper.wait_contact(model,90,guard) and connected
							helper.advance(model,150,{},{"x":facing})
							var super_damage := 0
							var blocks := 0
							var spend := 0
							var super_hits := 0
							for event: Dictionary in helper.events:
								if event.type=="block": blocks+=1
								if event.type=="meter" and event.attacker==0 and event.amount<0: spend-=event.amount
								if event.type=="hit" and event.move.ends_with("_max" if ending=="236236AC" else "_super"):
									super_damage+=event.damage;super_hits+=1
							var super_move = model.definition(model.fighters[0]).motions["max" if ending=="236236AC" else "super"]
							check(connected and blocks==0,"guard-tested real-input continuous combo: "+label)
							check(super_damage==(289 if ending=="236236AC" else 182) and super_hits==super_move.hit_count(),"all finisher hits and damage: "+label)
							check(spend==(300 if ending=="236236AC" else 100),"single correct meter spend: "+label)
							check(model.fighters[0].grounded and model.fighters[1].grounded,"both actors land after uppercut cancel: "+label)

func _recovery() -> void:
	for cid: String in IDS:
		for button: String in ["A","C"]:
			for situation: String in ["whiff","blocked","late"]:
				var model = helper.duel(cid)
				model.fighters[0].meter=300
				var defender := {"x":1} if situation=="blocked" else {}
				if situation=="whiff":model.fighters[1].x=680
				helper.input(model,"623"+button,defender)
				var fighter=model.fighters[0]
				var move=model.definition(fighter).motions["623"+button]
				var target: int = move.startup+move.active+move.cancel_window+2 if situation=="late" else move.startup+2
				while fighter.move!=null and fighter.move_frame<target:helper.tick(model,{},defender)
				var before_y: float = model.fighters[1].y
				helper.input(model,"236236AC",defender)
				check(fighter.meter==300 and fighter.move==move,"no MAX cancel on "+situation+": "+cid+button)
				if situation=="blocked":
					check(model.fighters[1].grounded and is_equal_approx(before_y,model.FLOOR_Y),"block never launches defender: "+cid+button)
				helper.advance(model,100,{},defender)
				check(fighter.grounded and fighter.move==null,"recovery finishes normally: "+cid+button)

func _interruptions() -> void:
	for cid: String in IDS:
		var model=helper.duel(cid)
		# A grounded poke interrupts heavy startup before its scheduled takeoff.
		helper.input(model,"623C",{"buttons":1})
		helper.advance(model,30)
		check(model.fighters[0].hp<1000 and model.fighters[0].grounded,"interrupted startup has no delayed ghost launch: "+cid)
		model=helper.duel(cid)
		model.fighters[1].y=model.FLOOR_Y-42
		model.fighters[1].grounded=false
		model.fighters[1].vy=-1
		helper.input(model,"623A")
		check(helper.wait_contact(model,40),"uppercut connects against airborne opponent: "+cid)
		helper.advance(model,100)
		check(model.fighters[1].grounded,"anti-air victim returns to floor: "+cid)
		model=helper.duel(cid)
		model.fighters[1].hp=1
		helper.input(model,"623C")
		helper.advance(model,280)
		check(model.phase=="intro" or model.phase=="fight","uppercut KO resolves after airborne winner lands: "+cid)
		# A prior projectile can end the round during a new uppercut's windup.
		# The victorious attack must still perform its scheduled visual takeoff.
		model=helper.duel(cid)
		helper.input(model,"623C")
		model.fighters[1].hp=0
		model._finish_round()
		var rose_during_outro:=false
		for tick in range(170):
			helper.tick(model)
			rose_during_outro=rose_during_outro or not model.fighters[0].grounded
		check(rose_during_outro,"scheduled takeoff survives a KO during windup: "+cid)

