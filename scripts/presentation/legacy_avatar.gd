extends Node2D
# Retained v1 stand-in for development only, until the approved generated art is available.
const Fighter = preload("res://scripts/fighter_state.gd")
const PAPER = Color("e4e9df")
var combat: RefCounted
var fighter: RefCounted
var font: Font
var time: float = 0.0
var screen: String = "battle"
var debug_boxes: bool = false
func _draw() -> void:
	if fighter != null:
		_fighter(fighter, Vector2.ZERO)
func _text(_value: String, _at: Vector2, _size: int, _color: Color) -> void:
	pass
func _fighter(f: Fighter, origin: Vector2, scale_factor: float = 1.0) -> void:
	var tick: float = combat.ticks if screen in ["battle", "result"] and combat != null else time * 60
	var duck := 24.0 if f.crouching and f.grounded else 0.0
	var bob := float(int(tick / 25) % 2) if f.state == "idle" else 0.0
	draw_set_transform(origin.round() + Vector2(0, duck + bob), 0, Vector2(f.facing * scale_factor, scale_factor))
	var tanjiro := f.character == "tanjiro"
	var coat := Color("2b9b79") if tanjiro else Color("e5ae46")
	var dark_coat := Color("122d2d") if tanjiro else Color("bc712e")
	var skin := Color("e7b68c")
	var hair := Color("42252e") if tanjiro else Color("efc857")
	var outline := Color("07121b")
	if f.state == "knockdown":
		draw_rect(Rect2(-22, -13, 39, 12), outline)
		draw_rect(Rect2(-10, -12, 25, 9), coat)
		draw_rect(Rect2(-27, -17, 16, 14), hair)
		draw_rect(Rect2(-25, -11, 11, 7), skin)
		draw_rect(Rect2(12, -9, 16, 7), Color("152633"))
		draw_set_transform(Vector2.ZERO)
		return
	var stride := sin(tick * 0.33) * 7 if f.state == "walk" else 0.0
	var back_foot := Vector2(-10 - stride, -duck - bob)
	var front_foot := Vector2(10 + stride, -duck - bob)
	if not f.grounded:
		back_foot = Vector2(-16, -10)
		front_foot = Vector2(14, -3)
	_segment(Vector2(-5, -23), back_foot, 9, outline)
	_segment(Vector2(5, -23), front_foot, 9, outline)
	_segment(Vector2(-5, -23), back_foot + Vector2(0, -3), 6, Color("20303b"))
	_segment(Vector2(5, -23), front_foot + Vector2(0, -3), 6, Color("2a3841"))
	draw_rect(Rect2(back_foot + Vector2(-4, -5), Vector2(9, 5)), Color("d4d4ba"))
	draw_rect(Rect2(front_foot + Vector2(-3, -5), Vector2(11, 5)), Color("d4d4ba"))
	# Haori silhouette, checkerboard / triangle motifs, uniform and white belt.
	draw_rect(Rect2(-15, -47, 30, 26), outline)
	draw_rect(Rect2(-13, -45, 26, 22), coat)
	if tanjiro:
		for row in range(4):
			for col in range(4):
				if (row + col) % 2 == 0:
					draw_rect(Rect2(-12 + col * 6, -45 + row * 5, 6, 5), dark_coat)
	else:
		for row in range(3):
			for col in range(3):
				var p := Vector2(-11 + col * 9 + (row % 2) * 2, -43 + row * 7)
				draw_colored_polygon(PackedVector2Array([p, p + Vector2(-2, 4), p + Vector2(2, 4)]), Color("f3e2ac"))
	draw_rect(Rect2(-3, -46, 7, 23), Color("20303a"))
	draw_rect(Rect2(-10, -25, 21, 3), Color("e4e2c8"))
	draw_rect(Rect2(0, -24, 3, 2), Color("929b94"))
	_segment(Vector2(-11, -43), Vector2(-15, -29), 8, dark_coat)
	draw_rect(Rect2(-17, -30, 5, 6), skin.darkened(0.12))
	var wrist := Vector2(16, -30)
	var sword_tip := Vector2(33, -11)
	var active := f.move != null and f.move_frame >= f.move.startup
	if f.move != null:
		if not active:
			wrist = Vector2(1, -48)
			sword_tip = Vector2(-17, -76)
		else:
			wrist = Vector2(25, -38)
			sword_tip = Vector2(67, -42)
			if f.move.id == "iai" or f.move.id == "water_wheel":
				wrist = Vector2(20, -47)
				sword_tip = Vector2(34, -82)
			if f.move.kind == "throw":
				wrist = Vector2(30, -33)
				sword_tip = Vector2(12, -10)
	elif f.state == "block":
		wrist = Vector2(20, -46)
		sword_tip = Vector2(19, -73)
	elif f.state == "hit":
		wrist = Vector2(-2, -30)
		sword_tip = Vector2(21, -11)
	_segment(Vector2(9, -42), wrist, 9, outline)
	_segment(Vector2(9, -42), wrist, 6, coat)
	draw_rect(Rect2(wrist - Vector2(2, 2), Vector2(5, 5)), skin)
	_segment(wrist, sword_tip, 3, outline)
	_segment(wrist + Vector2(5, -1), sword_tip, 2, Color("c6dad2"))
	_segment(wrist + Vector2(5, -2), sword_tip - Vector2(0, 1), 1, Color("f0f4de"))
	draw_rect(Rect2(wrist + Vector2(3, -5), Vector2(3, 9)), Color("b4a880"))
	# Head is a separate silhouette so both fighters remain legible at 1x.
	draw_rect(Rect2(-11, -65, 23, 21), outline)
	draw_rect(Rect2(-7, -61, 17, 16), skin)
	draw_rect(Rect2(8, -55, 4, 5), skin)
	draw_rect(Rect2(-10, -65, 23, 8), hair)
	draw_rect(Rect2(-12, -63, 6, 14), hair)
	draw_rect(Rect2(-7, -69, 6, 6), hair)
	draw_rect(Rect2(2, -67, 7, 7), hair)
	if tanjiro:
		draw_rect(Rect2(4, -59, 5, 3), Color("a45249"))
		draw_rect(Rect2(-7, -48, 2, 8), Color("e8ddc3"))
		draw_rect(Rect2(-7, -44, 2, 2), Color("be5650"))
	else:
		for n in range(4):
			draw_rect(Rect2(-7 + n * 5, -59, 3, 4 + n % 2 * 2), Color("cf8735"))
	draw_rect(Rect2(4, -53, 4, 2), Color("37252b"))
	draw_rect(Rect2(6, -49, 3, 1), Color("b67562"))
	draw_set_transform(Vector2.ZERO)
	if debug_boxes and screen == "battle":
		draw_rect(f.pushbox(), Color(1, 0.8, 0.25, 0.55), false)
		draw_rect(f.hurtbox(), Color(0.2, 1, 0.4, 0.8), false)
		if f.hitbox().has_area():
			draw_rect(f.hitbox(), Color(1, 0.25, 0.25, 0.75), true)
		_text("%s  %d" % [f.state, f.move_frame], Vector2(f.x - 28, f.y - 82), 9, PAPER)

func _attack_effect(f: Fighter, duck: float) -> void:
	match f.move.id:
		"water_slash":
			draw_colored_polygon(PackedVector2Array([Vector2(13, -44), Vector2(38, -61), Vector2(76, -57),
				Vector2(92, -44), Vector2(75, -31), Vector2(30, -33), Vector2(69, -40), Vector2(74, -47), Vector2(40, -50)]), Color("369eaa"))
			draw_polyline(PackedVector2Array([Vector2(20, -45), Vector2(44, -55), Vector2(75, -50), Vector2(86, -42)]), Color("b0f0da"), 2)
		"water_wheel":
			var points := PackedVector2Array()
			for n in range(18):
				var angle := -PI * 0.85 + n * TAU / 20 + f.move_frame * 0.14
				points.append((Vector2(17, -43) + Vector2(cos(angle), sin(angle)) * 42).round())
			draw_polyline(points, Color("328fa2"), 6)
			draw_polyline(points, Color("a5edda"), 2)
		"thunder":
			for n in range(3):
				var y := -27 - n * 10
				draw_polyline(PackedVector2Array([Vector2(-73, y + 5), Vector2(-31, y + 5), Vector2(-20, y - 2),
					Vector2(3, y + 3), Vector2(20, y - 3), Vector2(74, y - 3)]), Color("edc15b"), 3)
			draw_line(Vector2(-40, -39), Vector2(77, -39), Color("fff0b0"), 2)
		"iai":
			draw_colored_polygon(PackedVector2Array([Vector2(27, -15), Vector2(37, -77), Vector2(48, -66), Vector2(37, -25)]), Color("e9c56c"))
			draw_line(Vector2(33, -22), Vector2(40, -72), Color("fff0c1"), 2)
		_:
			if f.move.kind != "throw":
				var box: Rect2 = f.move.box
				draw_line(Vector2(box.position.x + 8, box.position.y + 8 - duck), Vector2(box.end.x, box.position.y + 12 - duck), Color("d6e9d6"), 2)

func _segment(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(a.round(), b.round(), color, width, false)

