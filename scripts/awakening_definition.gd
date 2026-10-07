class_name AwakeningDefinition
extends Resource
## Immutable tuning; timers and budgets belong to DuelFighter.
@export var display_name: String = "觉醒"
@export var damage_percent: int = 100
@export var received_percent: int = 100
@export var chip_percent: int = 100
@export var walk_percent: int = 100
@export var dash_percent: int = 100
@export var healing_percent: int = 0
@export var healing_limit: int = 0
@export var color: Color = Color.WHITE
@export var sound: String = "flame"
@export var form_atlas: String = ""
@export var form_scale: float = 1.0
@export var start_clip: String = "awakening_start"

func effect_summary() -> String:
	var parts: Array[String] = ["普攻/必杀伤害 +%d%%" % (damage_percent-100)]
	if received_percent < 100: parts.append("受到伤害 −%d%%" % (100-received_percent))
	if walk_percent == dash_percent:
		parts.append("移动 +%d%%" % (walk_percent-100))
	else:
		parts.append("行走 +%d%% / 冲刺 +%d%%" % [walk_percent-100,dash_percent-100])
	if healing_percent > 0: parts.append("命中恢复 %d%%，上限%d生命" % [healing_percent,healing_limit])
	if chip_percent < 100: parts.append("防御削血减半")
	return " · ".join(parts)
