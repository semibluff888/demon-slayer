extends RefCounted
## Runs identical command streams in editor and exported release templates.
const Combat = preload("res://scripts/combat.gd")
var failures: Array[String] = []
var cases: int = 0

static func resource_snapshot() -> String:
	var result := {}
	var catalog = Combat.new().catalog
	for id in catalog.moves:
		var move = catalog.moves[id]
		var fields := {}
		for property in move.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
				continue
			var value = move.get(property.name)
			if value is Resource: continue
			if value is Dictionary:
				# Follow-up stages are recorded by id, never as embedded objects.
				var ids := {}
				for key in value:
					ids[key] = value[key].id if value[key] is Resource else value[key]
				value = ids
			fields[str(property.name)] = var_to_str(value)
		result[id] = fields
	return JSON.stringify(result, "", true)

func run(require_manifest: bool = false) -> Array[String]:
	failures.clear()
	cases = 0
	var manifest := "res://resources/combat-manifest.json"
	if FileAccess.file_exists(manifest):
		if FileAccess.get_file_as_string(manifest) != resource_snapshot():
			failures.append("Packaged move properties differ from source combat manifest")
		else:
			print("RELEASE RESOURCES: %d moves match source" % Combat.new().moves.size())
	elif require_manifest:
		failures.append("Packaged combat manifest is missing")
	for character in Combat.new().catalog.characters:
		for facing in [-1, 1]:
			for corner in [false, true]:
				for route in [["5C", "214D", "236236AC"], ["5A", "5C", "236A", "236236A"], ["2B", "2A", "5C", "236A"], ["5C", "623C", "236236AC"]]:
					_route(character, facing, corner, route)
	print("RELEASE COMBAT: %d cases, %d failed" % [cases, failures.size()])
	# Data-driven expansion routes: every target-combo string and command normal.
	var before := failures.size()
	var expansion := 0
	var catalog = Combat.new().catalog
	for character in catalog.characters:
		for steps in _expansion_routes(catalog.characters[character]):
			for facing in [-1, 1]:
				for corner in [false, true]:
					expansion += 1
					_expansion_route(character, facing, corner, steps)
	print("RELEASE EXPANSION: %d cases, %d failed" % [expansion, failures.size() - before])
	return failures

## Follow-up strings from their base normal, and command normals, each finished
## with 236A when the last move can cancel into a special.
static func _expansion_routes(definition: Resource) -> Array:
	var routes: Array = []
	var special: Resource = definition.motions.get("236A")
	for key: String in definition.normals:
		var stage: Resource = definition.normals[key]
		if stage.follow_ups.is_empty():
			continue
		var steps: Array = [{"notation": key, "id": stage.id}]
		while not stage.follow_ups.is_empty() and steps.size() < 6:
			var button: String = stage.follow_ups.keys()[0]
			stage = stage.follow_ups[button]
			steps.append({"notation": button, "id": stage.id})
		if special != null and "skill" in stage.cancel_targets:
			steps.append({"notation": "236A", "id": special.id, "delay": 8})
		routes.append(steps)
	for key: String in definition.command_normals:
		var move: Resource = definition.command_normals[key]
		var steps: Array = [{"notation": key, "id": move.id}]
		if special != null and "skill" in move.cancel_targets:
			# An immediate 236 after a forward command normal reads as 623.
			steps.append({"notation": "236A", "id": special.id, "delay": 8})
		routes.append(steps)
	return routes

func _expansion_route(character: String, facing: int, corner: bool, steps: Array) -> void:
	var model := Combat.new()
	model.new_match(character, "zenitsu" if character == "tanjiro" else "tanjiro")
	model.phase = "fight"
	var a = model.fighters[0]
	var d = model.fighters[1]
	d.x = (Combat.RIGHT if facing > 0 else Combat.LEFT) if corner else 600.0
	a.x = d.x - facing * 34
	a.facing = facing
	d.facing = -facing
	a.input.last_facing = facing
	d.input.last_facing = -facing
	var expected: Array[String] = []
	var hits: Array[String] = []
	var blocked := false
	var damage := 0
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		expected.append(str(step.id))
		var guard := {"x": facing, "y": 0} if index > 0 else Combat.neutral()
		var commands: Array[Dictionary] = []
		for n in range(int(step.get("delay", 0))):
			commands.append(Combat.neutral())
		commands.append(Combat.neutral())
		var digits := ""
		var mask := 0
		for token in str(step.notation):
			if token in "123456789": digits += token
			elif token in "ABCD": mask |= 1 << "ABCD".find(token)
		if digits.is_empty(): digits = "5"
		for n in range(digits.length()):
			var direction := int(digits[n])
			commands.append({"x": ((direction - 1) % 3 - 1) * facing, "y": 1 - int((direction - 1) / 3), "buttons": mask if n == digits.length() - 1 else 0})
		var instance: int = a.attack_instance
		for frame in range(160):
			model.step([commands[frame] if frame < commands.size() else Combat.neutral(), guard])
			for event in model.events:
				if event.type == "hit" and event.attacker == 0:
					damage += int(event.damage)
					if hits.is_empty() or hits.back() != str(event.move): hits.append(str(event.move))
				elif event.type == "block": blocked = true
			if index < steps.size() - 1 and a.attack_instance != instance and a.confirmed: break
	if blocked or hits != expected or a.combo < steps.size() or a.combo_damage != damage or 1000 - d.hp != damage:
		failures.append("expansion %s/%s/facing%d/corner%s: hits=%s damage=%d combo=%d blocked=%s" % [character, expected, facing, corner, hits, damage, a.combo, blocked])

func _route(character: String, facing: int, corner: bool, route: Array) -> void:
	cases += 1
	var model := Combat.new()
	model.new_match(character, "zenitsu" if character == "tanjiro" else "tanjiro")
	model.phase = "fight"
	var a = model.fighters[0]
	var d = model.fighters[1]
	d.x = (Combat.RIGHT if facing > 0 else Combat.LEFT) if corner else 600.0
	a.x = d.x - facing * 34
	a.facing = facing
	d.facing = -facing
	a.input.last_facing = facing
	d.input.last_facing = -facing
	a.meter = 300
	var expected: Array[String] = []
	var hits: Array[String] = []
	var blocked := false
	var damage := 0
	var spent := 0
	for index in range(route.size()):
		var notation: String = route[index]
		var key := "max" if notation == "236236AC" else ("super" if notation == "236236A" else notation)
		var definition = model.definition(a)
		var move = definition.normals.get(key, definition.motions.get(key))
		expected.append(move.id)
		var guard := {"x": facing, "y": 1 if notation.begins_with("2") else 0} if index > 0 else Combat.neutral()
		var commands: Array[Dictionary] = [Combat.neutral()]
		var digits := ""
		var mask := 0
		for token in notation:
			if token in "123456789": digits += token
			elif token in "ABCD": mask |= 1 << "ABCD".find(token)
		for n in range(digits.length()):
			var direction := int(digits[n])
			commands.append({"x": ((direction - 1) % 3 - 1) * facing, "y": 1 - int((direction - 1) / 3), "buttons": mask if n == digits.length() - 1 else 0})
		var instance: int = a.attack_instance
		for frame in range(160):
			model.step([commands[frame] if frame < commands.size() else Combat.neutral(), guard])
			for event in model.events:
				if event.type == "hit" and event.attacker == 0:
					damage += int(event.damage)
					if hits.is_empty() or hits.back() != str(event.move): hits.append(str(event.move))
				elif event.type == "block": blocked = true
				elif event.type == "meter" and event.attacker == 0 and event.amount < 0: spent -= int(event.amount)
			if index < route.size() - 1 and a.attack_instance != instance and a.confirmed: break
	var cost := 300 if route[-1] == "236236AC" else (100 if route[-1] == "236236A" else 0)
	if blocked or hits != expected or a.combo < route.size() or a.combo_damage != damage or 1000 - d.hp != damage or spent != cost:
		failures.append("%s/%s/facing%d/corner%s: hits=%s damage=%d combo=%d spent=%d blocked=%s" % [character, route, facing, corner, hits, damage, a.combo, spent, blocked])
