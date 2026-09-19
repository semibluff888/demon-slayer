extends Node2D
var fighter: RefCounted
var visual: Resource
var combat: RefCounted
var clock_ticks: float = 0.0
var texture: Texture2D
var clip: String = "idle"
var frame_index: int = 0
var last_state: String = ""
var player_accent := Color("77dce0")
var show_player_mark: bool = true
var afterimages: Array[Dictionary] = []
var trail_clock: float = 0.0
var previous_move_frame: int = -1
var previous_stun: int = 0
var was_grounded: bool = true
var landing_ticks: float = 0.0
var restart_requested: bool = false

func reset_pose() -> void:
	clock_ticks = 0
	trail_clock = 0
	afterimages.clear()
	texture = null
	clip = "idle"
	last_state = ""
	previous_move_frame = -1
	previous_stun = 0
	was_grounded = true
	landing_ticks = 0
	restart_requested = false

func consume(events: Array, slot: int) -> void:
	for event: Dictionary in events:
		if event.type == "swing" and event.get("attacker", -1) == slot:
			restart_requested = true
		elif event.type in ["hit", "throw", "block"] and event.get("attacker", slot) != slot:
			restart_requested = true

func sync(delta: float, freeze_pose: bool) -> void:
	if fighter == null or visual == null:
		return
	if not freeze_pose:
		if not was_grounded and fighter.grounded and fighter.move == null and fighter.state == "idle":
			landing_ticks = 6
		else:
			landing_ticks = maxf(0, landing_ticks - delta * 60)
	was_grounded = fighter.grounded
	var desired := _clip()
	var repeat_move: bool = fighter.move != null and fighter.move_frame < previous_move_frame
	var renewed_stun: bool = fighter.state in ["hit", "block", "knockdown"] and fighter.stun > previous_stun
	if desired != clip or restart_requested or repeat_move or renewed_stun:
		clock_ticks = 0
		clip = desired
		restart_requested = false
	previous_move_frame = fighter.move_frame if fighter.move != null else -1
	previous_stun = fighter.stun
	if not freeze_pose:
		clock_ticks += delta * 60
		trail_clock += delta
		for ghost: Dictionary in afterimages:
			ghost.life -= delta
		afterimages = afterimages.filter(func(ghost: Dictionary) -> bool: return ghost.life > 0)
	texture = null
	if visual.frames != null and visual.frames.has_animation(clip) and visual.frames.get_frame_count(clip) > 0:
		frame_index = _frame_index()
		texture = visual.frames.get_frame_texture(clip, frame_index)
	if not freeze_pose and texture != null and clip == "thunder" and fighter.hitbox().has_area() and trail_clock >= 0.035:
		afterimages.append({"texture": texture, "x": fighter.x, "y": fighter.y, "facing": fighter.facing, "life": 0.16})
		if afterimages.size() > 6:
			afterimages.pop_front()
		trail_clock = 0
	queue_redraw()

func _clip() -> String:
	if combat.phase == "match_end" and combat.match_winner == fighter.slot:
		return "victory"
	if fighter.move != null:
		return fighter.move.id
	if landing_ticks > 0 and fighter.state == "idle":
		return "jump"
	match fighter.state:
		"walk": return "walk_back" if fighter.axis * fighter.facing < 0 else "walk"
		"crouch": return "crouch"
		"air", "landing": return "jump"
		"block": return "guard_low" if fighter.crouching else "guard"
		"hit": return "hit"
		"knockdown": return "knockdown"
	return "idle"

func _frame_index() -> int:
	var count: int = visual.frames.get_frame_count(clip)
	if fighter.move != null and clip == fighter.move.id:
		var cuts: Array = visual.phases.get(clip, [maxi(1, count / 3), maxi(2, count * 2 / 3)])
		var first := clampi(int(cuts[0]), 1, count)
		var second := clampi(int(cuts[1]), first, count)
		var move: Resource = fighter.move
		if fighter.move_frame < move.startup:
			return mini(first - 1, int(float(fighter.move_frame) / move.startup * first))
		if fighter.move_frame < move.startup + move.active:
			return mini(count - 1, first + int(float(fighter.move_frame - move.startup) / move.active * maxi(1, second - first)))
		return mini(count - 1, second + int(float(fighter.move_frame - move.startup - move.active) / move.recovery * maxi(1, count - second)))
	if clip == "jump":
		if fighter.grounded:
			return mini(count - 1, 4 if fighter.state == "landing" or landing_ticks > 3 else 5)
		if fighter.vy < -5:
			return mini(count - 1, 1)
		return mini(count - 1, 2 if fighter.vy < 2 else 3)
	if clip in ["guard", "guard_low"]:
		return mini(count - 1, 1 + int(clock_ticks / 5))
	if clip == "crouch":
		return mini(count - 1, int(clock_ticks / 3))
	var frame := int(clock_ticks / 60.0 * visual.frames.get_animation_speed(clip))
	return frame % count if visual.frames.get_animation_loop(clip) else mini(frame, count - 1)

func visual_bounds() -> Rect2:
	if texture == null or visual == null:
		return Rect2(-36, -84, 72, 84)
	var factor: float = visual.canonical_height / visual.source_height
	var bounds := Rect2(Vector2.ZERO, texture.get_size())
	if texture is AtlasTexture:
		bounds = Rect2(texture.margin.position, texture.region.size)
	bounds.position = (bounds.position - visual.feet_anchor) * factor
	bounds.size *= factor
	if fighter.facing < 0:
		bounds.position.x = -bounds.end.x
	return bounds

func _draw() -> void:
	if fighter == null:
		return
	if texture != null:
		var factor: float = visual.canonical_height / visual.source_height
		for ghost: Dictionary in afterimages:
			draw_set_transform(Vector2(ghost.x - fighter.x, ghost.y - fighter.y), 0, Vector2(ghost.facing, 1))
			draw_texture_rect(ghost.texture, Rect2(-visual.feet_anchor * factor, ghost.texture.get_size() * factor), false, Color(1, 0.8, 0.35, ghost.life * 2.0))
		draw_set_transform(Vector2.ZERO, 0, Vector2(fighter.facing, 1))
		var rect := Rect2(-visual.feet_anchor * factor, texture.get_size() * factor)
		# A restrained rim distinguishes mirrors without recoloring the costume.
		if combat.fighters[0].character == combat.fighters[1].character:
			for offset in [Vector2(-0.45, 0), Vector2(0.45, 0)]:
				draw_texture_rect(texture, Rect2(rect.position + offset, rect.size), false, player_accent * Color(1, 1, 1, 0.65))
		draw_texture_rect(texture, rect, false)
		draw_set_transform(Vector2.ZERO)
	if show_player_mark:
		draw_colored_polygon(PackedVector2Array([Vector2(-2, 3), Vector2(2, 3), Vector2(0, 5)]), player_accent)
