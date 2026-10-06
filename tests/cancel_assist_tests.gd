extends SceneTree
const Support=preload("res://tests/combat_test_support.gd")
const Commands=preload("res://scripts/command_recognizer.gd")
var helper=Support.new()
var passed:=0
var failures: Array[String]=[]
var rows: Array=[]
func _initialize() -> void:_run.call_deferred()
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:failures.append(label)
func _run() -> void:
	for cid: String in ["tanjiro","zenitsu","nezuko","akaza"]:
		for victim: String in ["tanjiro","zenitsu","nezuko","akaza"]:
			for facing: int in [-1,1]:
				for corner: bool in [false,true]:
					for button: String in ["A","C"]:
						for max_version: bool in [false,true]:
							for delay: int in [0,6]:
								var model=helper.duel(cid,facing,corner)
								model.fighters[1].character=victim;model.fighters[0].meter=300
								var guard: Dictionary={"x":facing}
								helper.input(model,"5A");helper.wait_contact(model)
								for input: String in ["5C","623"+button]:
									helper.input(model,input,guard);helper.wait_contact(model,90,guard)
								helper.advance(model,delay,{},guard)
								for digit in "236236":helper.advance(model,3,helper.relative(int(digit),facing),guard)
								helper.tick(model,helper.relative(6,facing,5 if max_version else 1),guard)
								helper.advance(model,160,{},guard)
								var damage:=0;var block:=0;var spend:=0;var hits:=0
								for event: Dictionary in helper.events:
									if event.type=="block":block+=1
									if event.type=="meter" and event.attacker==0 and event.amount<0:spend-=event.amount
									if event.type=="hit" and event.move.ends_with("_max" if max_version else "_super"):damage+=event.damage;hits+=1
								var ending=model.definition(model.fighters[0]).motions["max" if max_version else "super"]
								var label:="%s / %s 623%s f%d corner=%s max=%s delay=%d" % [cid,victim,button,facing,corner,max_version,delay]
								check(damage==(289 if max_version else 182) and hits==ending.hit_count(),"slow input full finisher: "+label)
								check(block==0,"defender holding back finds no combo gap: "+label)
								check(spend==(300 if max_version else 100),"correct single meter spend: "+label)
								check(model.fighters[0].grounded and model.fighters[1].grounded,"both land after combo: "+label)
								rows.append({"character":cid,"victim":victim,"button":button,"facing":facing,"corner":corner,"max":max_version,"reaction_ticks":delay,"direction_hold_ticks":3,"damage":damage,"hits":hits,"blocks":block})
	_inputs()
	_blocked_and_whiff()
	DirAccess.make_dir_recursive_absolute("res://artifacts/menu-settings")
	var report=FileAccess.open("res://artifacts/menu-settings/cancel-verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":passed,"failures":failures,"routes":rows},"  "))
	for failure in failures:printerr("FAIL: ",failure)
	print("CANCEL ASSIST: %d passed, %d failed" % [passed,failures.size()])
	quit(0 if failures.is_empty() else 1)
func _inputs() -> void:
	for facing: int in [-1,1]:
		for delay: int in [12,13]:
			var reader=Commands.new()
			for digit in "236236":reader.sample(helper.relative(int(digit),facing),facing)
			for n in range(delay-1):reader.sample(helper.relative(6,facing),facing)
			reader.sample(helper.relative(6,facing,1),facing)
			reader.sample(helper.relative(6,facing),facing)
			var action=reader.sample(helper.relative(6,facing),facing).action
			check((action.get("motion","")=="236236")== (delay==12),"super final button 12/13 boundary")
		for hold: int in [8,9]:
			var reader=Commands.new()
			for index in range(6):
				var digit: int=int("236236"[index])
				for n in range(hold if index<5 else 1):
					reader.sample(helper.relative(digit,facing,1 if index==5 else 0),facing)
			reader.sample(helper.relative(6,facing),facing)
			var action=reader.sample(helper.relative(6,facing),facing).action
			check((action.get("motion","")=="236236")==(hold==8),"double quarter motion accepts 40 ticks but rejects 45")
func _blocked_and_whiff() -> void:
	for cid: String in ["tanjiro","zenitsu","nezuko","akaza"]:
		for button: String in ["A","C"]:
			for situation: String in ["block","whiff","expired","late_block","late_whiff"]:
				var model=helper.duel(cid);model.fighters[0].meter=300
				var guard: Dictionary={"x":1} if situation in ["block","late_block"] else {}
				if situation in ["whiff","late_whiff"]:model.fighters[1].x=690
				helper.input(model,"623"+button,guard)
				var fighter=model.fighters[0];var move=model.definition(fighter).motions["623"+button]
				if situation in ["expired","late_block","late_whiff"]:
					while fighter.move!=null and fighter.move_frame<=move.startup+move.active+move.cancel_window:helper.tick(model)
				else:helper.advance(model,8,{},guard)
				helper.input(model,"236236AC",guard)
				helper.advance(model,12,{},guard)
				check(fighter.meter==300,"no illegal cancel on "+situation+" "+cid+button)
				helper.advance(model,140,{},guard)
				check(fighter.meter==300,"invalid cancel never fires from stale buffer: "+situation+" "+cid+button)
				check(fighter.move==null and fighter.grounded,"blocked/whiff/expired cancel recovery finishes")
