extends SceneTree
## Seeded AI-vs-AI matches with swapped slots. Diagnostic, not player win-rate proof.
## Usage: godot --headless --path . --script res://tools/balance_audit.gd
##   [-- --pairs=tanjiro:zenitsu,tanjiro:akaza] [--out=balance-audit]
const Combat = preload("res://scripts/combat.gd")
const AI = preload("res://scripts/ai_controller.gd")

func _initialize() -> void:
	var pairs: Array = [["tanjiro", "zenitsu"]]
	var name := "balance-audit"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pairs="):
			pairs.clear()
			for entry in argument.trim_prefix("--pairs=").split(","):
				pairs.append(entry.split(":"))
		elif argument.begins_with("--out="):
			name = argument.trim_prefix("--out=")
	var report: Array[Dictionary] = []
	var summary := {}
	var unfinished := 0
	for pair_index in range(pairs.size()):
		var base: Array = pairs[pair_index]
		var totals := {base[0]: 0, base[1]: 0, "unfinished": 0, "ticks": 0}
		for seed_index in range(24):
			for swapped in [false, true]:
				var model := Combat.new()
				var pair: Array = [base[1], base[0]] if swapped else [base[0], base[1]]
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
				totals.ticks += ticks
				if winner == "unfinished":
					unfinished += 1
				report.append({"seed": seed_index, "players": pair, "winner": winner, "rounds": model.wins,
					"ticks": ticks, "damage": damage, "meter_spent": spent, "move_uses": move_uses})
		totals.average_ticks = float(totals.ticks) / 48.0
		summary["%s:%s" % [base[0], base[1]]] = totals
		print("BALANCE AUDIT %s vs %s: " % [base[0], base[1]], totals)
	var file := FileAccess.open("res://artifacts/%s.json" % name, FileAccess.WRITE)
	file.store_string(JSON.stringify({"pairs": summary, "matches": report}, "  "))
	print("BALANCE AUDIT: %d pairs x 48 seeded matches with swapped slots -> artifacts/%s.json (diagnostic, not player win-rate proof)" % [pairs.size(), name])
	quit(0 if unfinished == 0 else 1)
