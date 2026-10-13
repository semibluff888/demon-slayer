extends SceneTree
## Writes artifacts/frame-data.md and .json: authored frame data plus advantage by
## formula and by simulation (tests/frame_probe.gd). Diagnostic only.
## Usage: godot --headless --path . --script res://tools/frame_data_report.gd [-- --out=name]
const Combat = preload("res://scripts/combat.gd")
const Probe = preload("res://tests/frame_probe.gd")
const AIR_TICKS := [12, 20, 26, 30]

func _initialize() -> void:
	var name := "frame-data"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			name = argument.trim_prefix("--out=")
	var model := Combat.new()
	var rows: Array[Dictionary] = []
	for id: String in model.catalog.characters:
		var definition: Resource = model.catalog.characters[id]
		var inputs := _inputs(definition)
		for move: Resource in definition.all_moves():
			if move.kind == "throw":
				continue
			rows.append(_row(id, inputs.get(move.id, ""), move))
	var lines: PackedStringArray = ["# Frame data", "",
		"Advantage = defender free tick − attacker free tick (positive favours the attacker). 公式 assumes contact on the first active frame; 实测 steps the real model at 34 px (air moves: forward jump sampled at %s air ticks, stand guard)." % [AIR_TICKS], "",
		"| 角色 | 指令 | 招式 | 类别·段位 | 发生 | 持续 | 收招 | 伤害(段) | 硬直 | 防御硬直 | 停顿 | 被防(公式/实测) | 命中(公式/实测) | 取消 | 派生 | 落地硬直 |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	for row in rows:
		lines.append("| %s | %s | %s | %s·%s | %d | %d | %d | %d(%d) | %d | %d | %d | %s / %s | %s / %s | %s | %s | %s |" % [
			row.character, row.input, row.name, row.kind, row.level, row.startup, row.active, row.recovery,
			row.damage, row.hits, row.hitstun, row.blockstun, row.hitstop, _fmt(row.block_formula), _fmt(row.block_measured),
			_fmt(row.hit_formula), _fmt(row.hit_measured), ",".join(row.cancels), ",".join(row.follow_ups), row.landing])
	var md := FileAccess.open("res://artifacts/%s.md" % name, FileAccess.WRITE)
	md.store_string("\n".join(lines) + "\n")
	var json := FileAccess.open("res://artifacts/%s.json" % name, FileAccess.WRITE)
	json.store_string(JSON.stringify(rows, "  ", false))
	print("FRAME DATA REPORT: %d moves -> artifacts/%s.md" % [rows.size(), name])
	quit(0)

func _inputs(definition: Resource) -> Dictionary:
	var result := {}
	for table in ["normals", "motions", "command_normals", "air_motions"]:
		if not table in definition:
			continue
		var entries: Dictionary = definition.get(table)
		for key: String in entries:
			var move: Resource = entries[key]
			if move != null and not result.has(move.id):
				result[move.id] = "236236A/C" if key == "super" else ("236236AC" if key == "max" else key)
	# Follow-up stages inherit their parent's notation.
	var changed := true
	while changed:
		changed = false
		for move: Resource in definition.all_moves():
			if not "follow_ups" in move or not result.has(move.id):
				continue
			for button: String in move.follow_ups:
				var next: Resource = move.follow_ups[button]
				if not result.has(next.id):
					result[next.id] = str(result[move.id]) + ">" + button
					changed = true
	return result

func _row(character: String, notation: String, move: Resource) -> Dictionary:
	var block_measured: Variant = null
	var hit_measured: Variant = null
	var air: bool = move.stance == "air"
	var guard := "crouch" if move.level == "low" else "stand"
	if air:
		for tick: int in AIR_TICKS:
			var sample: Dictionary = Probe.air(character, move, tick, "stand")
			if sample.contact == "block" and sample.advantage != null:
				block_measured = "%s@%d" % [sample.advantage, tick] if block_measured == null else "%s,%s@%d" % [block_measured, sample.advantage, tick]
			var struck: Dictionary = Probe.air(character, move, tick, "")
			if struck.contact == "hit" and struck.advantage != null and hit_measured == null:
				hit_measured = "%s@%d" % [struck.advantage, tick]
	else:
		var blocked: Dictionary = Probe.ground(character, move, guard)
		block_measured = blocked.advantage if blocked.contact == "block" else null
		var struck: Dictionary = Probe.ground(character, move, "")
		hit_measured = ("KD" if move.knockdown else struck.advantage) if struck.contact == "hit" else null
	var follow: Array[String] = []
	if "follow_ups" in move:
		for button: String in move.follow_ups:
			follow.append(button + "→" + str(move.follow_ups[button].id))
	return {"character": character, "input": notation, "id": move.id, "name": move.display_name, "kind": move.kind,
		"level": move.level, "startup": move.startup, "active": move.active, "recovery": move.recovery,
		"damage": move.damage, "hits": move.hit_count(), "hitstun": move.hitstun, "blockstun": move.blockstun,
		"hitstop": move.hitstop, "block_formula": null if air or move.projectile_speed != 0 else Probe.formula(move, true),
		"block_measured": block_measured, "hit_formula": null if air or move.projectile_speed != 0 or move.knockdown else Probe.formula(move, false),
		"hit_measured": hit_measured, "cancels": Array(move.cancel_targets), "follow_ups": follow,
		"landing": str(move.landing_recovery) if air and "landing_recovery" in move else ("5" if air else "")}

func _fmt(value: Variant) -> String:
	return "—" if value == null else str(value)
