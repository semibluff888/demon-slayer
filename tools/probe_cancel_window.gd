extends SceneTree
const Support=preload("res://tests/combat_test_support.gd")
var helper=Support.new()
func _initialize() -> void:
	var rows: Array=[]
	for window: int in [0,12]:
		for cid: String in ["tanjiro","zenitsu","nezuko","akaza"]:
			for button: String in ["A","C"]:
				for delay: int in [0,3,6]:
					for hold: int in [1,2,3,4]:
						for max_version: bool in [false,true]:
							var model=helper.duel(cid)
							model.fighters[0].meter=300
							var move=model.definition(model.fighters[0]).motions["623"+button]
							move.cancel_window=window
							helper.input(model,"5A");helper.wait_contact(model)
							helper.input(model,"5C",{"x":1});helper.wait_contact(model,90,{"x":1})
							helper.input(model,"623"+button,{"x":1});helper.wait_contact(model,90,{"x":1})
							helper.advance(model,delay,{},{"x":1})
							for digit in "236236":
								helper.advance(model,hold,helper.relative(int(digit),1),{"x":1})
							helper.tick(model,helper.relative(6,1,5 if max_version else 1),{"x":1})
							helper.advance(model,150,{},{"x":1})
							var damage:=0;var blocked:=false;var started:=false
							for event: Dictionary in helper.events:
								if event.type=="block":blocked=true
								if event.type=="super":started=true
								if event.type=="hit" and (event.move.ends_with("_max") or event.move.ends_with("_super")):damage+=event.damage
							rows.append({"window":window,"character":cid,"button":button,"reaction":delay,"hold":hold,"max":max_version,"started":started,"blocked":blocked,"damage":damage,"full":damage==(445 if max_version else 280) and not blocked})
							move.cancel_window=12
	var file=FileAccess.open("res://artifacts/cancel-window-probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  "))
	for window: int in [0,12]:
		for hold: int in [1,2,3,4]:
			var group=rows.filter(func(row: Dictionary):return row.window==window and row.hold==hold)
			print("window=",window," ticks/direction=",hold," full=",group.filter(func(row: Dictionary):return row.full).size(),"/",group.size()," started=",group.filter(func(row: Dictionary):return row.started).size())
	quit()
