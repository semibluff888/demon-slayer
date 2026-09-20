extends SceneTree
const Combat = preload("res://scripts/combat.gd")
const AI = preload("res://scripts/ai_controller.gd")

func _initialize() -> void:
	var report: Array[Dictionary] = []
	var totals := {"tanjiro": 0, "zenitsu": 0, "unfinished": 0}
	for seed_index in range(24):
		for swapped in [false, true]:
			var model := Combat.new()
			var pair := ["zenitsu","tanjiro"] if swapped else ["tanjiro","zenitsu"]
			model.new_match(pair[0], pair[1])
			# The same character keeps the same seed when its player slot changes.
			var seeds := [101 + seed_index * 19, 503 + seed_index * 31]
			var agents := [AI.new(seeds[1] if swapped else seeds[0]), AI.new(seeds[0] if swapped else seeds[1])]
			var damage: Array[int] = [0,0]
			var spent: Array[int] = [0,0]
			var move_uses: Array[Dictionary] = [{},{}]
			var ticks := 0
			while model.phase != "match_end" and ticks < 40000:
				model.step([agents[0].command(model.fighters[0].observable(), model.fighters[1].observable()),
					agents[1].command(model.fighters[1].observable(), model.fighters[0].observable())])
				for event in model.events:
					if event.type in ["hit","throw"]:
						damage[event.attacker] += int(event.damage)
					elif event.type == "meter" and int(event.amount) < 0:
						spent[event.attacker] -= int(event.amount)
					elif event.type == "swing":
						var uses: Dictionary = move_uses[event.attacker]
						uses[event.move] = int(uses.get(event.move, 0)) + 1
				ticks += 1
			var winner: String = pair[model.match_winner] if model.match_winner >= 0 else "unfinished"
			totals[winner] += 1
			report.append({"seed": seed_index, "players": pair, "winner": winner, "rounds": model.wins,
				"ticks": ticks, "damage": damage, "meter_spent": spent, "move_uses": move_uses})
	var file := FileAccess.open("res://artifacts/balance-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"totals": totals, "matches": report}, "  "))
	print("BALANCE AUDIT: ", totals, " (48 seeded matches with swapped slots; diagnostic, not player win-rate proof)")
	quit(0 if totals.unfinished == 0 else 1)
