class_name DuelPractice
extends RefCounted
const Combat = preload("res://scripts/combat.gd")
var guard_mode: int = 0
var meter_mode: int = 2
var first_hit: bool = false
var recovery_ticks: int = 0
var last_combo: int = 0
var last_damage: int = 0

func reset(model: Combat, positions: bool = true) -> void:
	model.practice = true
	if positions:
		var first: String = model.fighters[0].character
		var second: String = model.fighters[1].character
		model.new_match(first, second)
		model.fighters[0].x = 430
		model.fighters[1].x = 490
		for f in model.fighters:
			f.previous_x = f.x
	first_hit = false
	recovery_ticks = 0
	last_combo = 0
	last_damage = 0
	apply_meter(model)

func apply_meter(model: Combat) -> void:
	model.fighters[0].meter = [0, 100, 300, 300][meter_mode]
	model.fighters[1].meter = 0

func command(model: Combat) -> Dictionary:
	var dummy = model.fighters[1]
	var attacker = model.fighters[0]
	var result := Combat.neutral()
	var guarding := guard_mode in [1, 2] or (guard_mode == 3 and first_hit)
	if guarding:
		result.x = (-1 if attacker.x > dummy.x else 1) if not is_equal_approx(attacker.x, dummy.x) else -dummy.facing
		result.y = 1 if guard_mode == 2 else 0
		if guard_mode == 3 and attacker.move != null:
			result.y = 1 if attacker.move.level == "low" else 0
	return result

func after_step(model: Combat) -> void:
	if meter_mode == 3:
		model.fighters[0].meter = 300
	for event in model.events:
		if event.type in ["hit", "throw"] and event.attacker == 0:
			first_hit = true
			last_combo = model.fighters[0].combo
			last_damage = model.fighters[0].combo_damage
	var dummy = model.fighters[1]
	if model.hitstop > 0 or model.super_freeze > 0:
		return
	if dummy.stun == 0 and model.fighters[0].move == null and model.throw_link.is_empty() and model.projectiles.is_empty():
		recovery_ticks += 1
		if recovery_ticks >= 45:
			for f in model.fighters:
				f.hp = 1000
			first_hit = false
	else:
		recovery_ticks = 0


func snapshot() -> Dictionary:
	return {"guard_mode": guard_mode, "meter_mode": meter_mode, "first_hit": first_hit,
		"recovery_ticks": recovery_ticks, "last_combo": last_combo, "last_damage": last_damage}
