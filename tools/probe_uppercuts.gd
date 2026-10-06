extends SceneTree
const Support = preload("res://tests/combat_test_support.gd")
var helper := Support.new()
func _initialize() -> void:
	var result: Array = []
	for cid: String in ["tanjiro","zenitsu","nezuko","akaza"]:
		for button: String in ["A","C"]:
			var model = helper.duel(cid)
			model.fighters[1].x = 660
			helper.input(model,"623"+button)
			var a = model.fighters[0]
			var peak: float = model.FLOOR_Y-a.y
			var airborne: int = a.air_ticks
			var ground_at := -1
			var saw_air: bool = not a.grounded
			while a.move != null:
				helper.tick(model)
				peak = maxf(peak,model.FLOOR_Y-a.y)
				if not a.grounded:
					airborne += 1
					saw_air = true
				elif saw_air and ground_at < 0: ground_at = a.move_frame
			result.append({"character":cid,"button":button,"peak_world":peak,"air_ticks":airborne,"ground_at":ground_at})
			for finisher: String in ["236236A","236236AC"]:
				model = helper.duel(cid); model.fighters[0].meter = 300
				var route: Array = ["5A","5C","623"+button,finisher]
				var confirmed: Array = []
				for notation: String in route:
					helper.input(model,notation)
					confirmed.append(helper.wait_contact(model,90))
				helper.advance(model,150)
				var hits: Array = []
				for event in helper.events:
					if event.type == "hit": hits.append({"move":event.move,"damage":event.damage})
				result.append({"character":cid,"route":route,"confirmed":confirmed,"damage":1000-model.fighters[1].hp,"hits":hits})
	var name: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "baseline"
	var file := FileAccess.open("res://artifacts/uppercut-polish/"+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	for row in result: print(JSON.stringify(row))
	quit()
