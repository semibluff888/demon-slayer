class_name DuelFighter
extends RefCounted
const Move = preload("res://scripts/move_data.gd")
const Commands = preload("res://scripts/command_recognizer.gd")
var character: String = ""
var slot: int = 0
var x: float = 200.0
var y: float = 286.0
var previous_x: float = 200.0
var vx: float = 0.0
var vy: float = 0.0
var facing: int = 1
var hp: int = 1000
var meter: int = 0
var state: String = "idle"
var grounded: bool = true
var knockdown_pending: bool = false
var crouching: bool = false
var axis: int = 0
var down: bool = false
var stun: int = 0
var move: Move = null
var move_frame: int = 0
var connected: bool = false
var confirmed: bool = false
var attack_instance: int = 0
var hit_registry: Array[int] = []
var projectile_spawned: bool = false
var buffer: String = ""
var buffer_action: Dictionary = {}
var buffer_left: int = 0
var jump_buffer: int = 0
var input := Commands.new()
var dash_direction: int = 0
var dash_request: int = 0
var dash_frame: int = 0
var dash_ticks: int = 0
var dash_back: bool = false
var roll_frame: int = -1
var roll_direction: int = 0
var air_ticks: int = 0
var air_used_move: bool = false
var jump_facing: int = 1
var jump_back: bool = false
var flip_jump: bool = false
var throw_role: String = ""
var throw_frame: int = 0
var throw_facing: int = 1
var throw_back: bool = true
var throw_invulnerable: int = 0
var combo: int = 0
var combo_damage: int = 0
var combo_display: int = 0
var combo_active: bool = false
var combo_instances: Dictionary = {}
var chain_instances: Array[int] = []
var chain_normals: Array[String] = []
var chain_counts: Dictionary = {}
var juggle_instances: Array[int] = []
var last_move: String = ""

func hurtbox() -> Rect2:
	if state == "knockdown" or hp <= 0 or not throw_role.is_empty():
		return Rect2()
	var height := 34.0 if crouching and grounded else 57.0
	return Rect2(x - 12, y - height, 24, height)

func pushbox() -> Rect2:
	if not throw_role.is_empty() or (roll_frame >= 0 and roll_frame < 20):
		return Rect2()
	return Rect2(x - 13, y - 44, 26, 44)

func hitbox() -> Rect2:
	if not throw_role.is_empty() or move == null or move.segment(move_frame) < 0 or move.projectile_speed != 0:
		return Rect2()
	var rect: Rect2 = move.box
	if facing < 0:
		rect.position.x = -rect.end.x
	rect.position += Vector2(x, y)
	return rect

func strike_invulnerable() -> bool:
	return roll_frame >= 2 and roll_frame <= 17

func clear_buffer() -> void:
	buffer = ""
	buffer_action.clear()
	buffer_left = 0
	jump_buffer = 0
	dash_request = 0

func observable() -> Dictionary:
	return {"character": character, "x": x, "y": y, "facing": facing, "state": state,
		"grounded": grounded, "crouching": crouching, "meter": meter, "hp": hp,
		"move": move.id if move != null else "", "connected": connected, "confirmed": confirmed}

func snapshot() -> Dictionary:
	var data: Dictionary = {}
	for property in get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var key: String = property.name
		if key == "input":
			data[key] = input.snapshot()
		elif key == "move":
			data[key] = move.id if move != null else ""
		else:
			var v: Variant = get(key)
			data[key] = v.duplicate(true) if v is Dictionary or v is Array else v
	return data
