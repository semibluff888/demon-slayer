class_name DuelFighter
extends RefCounted

const Move = preload("res://scripts/move_data.gd")
var character: String = "tanjiro"
var slot: int = 0
var x: float = 200.0
var y: float = 286.0
var previous_x: float = 200.0
var vx: float = 0.0
var vy: float = 0.0
var facing: int = 1
var hp: int = 1000
var state: String = "idle"
var grounded: bool = true
var crouching: bool = false
var axis: int = 0
var down: bool = false
var stun: int = 0
var move: Move = null
var move_frame: int = 0
var connected: bool = false
var buffer: String = ""
var buffer_forward: bool = false
var buffer_left: int = 0
var jump_buffer: int = 0
var combo: int = 0
var combo_display: int = 0

func hurtbox() -> Rect2:
	if state == "knockdown" or hp <= 0:
		return Rect2()
	var height := 34.0 if crouching and grounded else 57.0
	return Rect2(x - 12, y - height, 24, height)

func pushbox() -> Rect2:
	return Rect2(x - 13, y - 44, 26, 44)

func hitbox() -> Rect2:
	if move == null or move_frame < move.startup or move_frame >= move.startup + move.active:
		return Rect2()
	var rect: Rect2 = move.box
	if facing < 0:
		rect.position.x = -rect.end.x
	rect.position += Vector2(x, y)
	return rect

func observable() -> Dictionary:
	return {"x": x, "y": y, "facing": facing, "state": state,
		"grounded": grounded, "crouching": crouching}
