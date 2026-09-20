extends Node2D
const Arena = preload("res://scripts/arena_rules.gd")
const IDLE_BREATH_SECONDS: float = 3.2
const IDLE_BREATH_AMOUNT: float = 0.003
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
		# Releasing back keeps an already crouched fighter low instead of standing
		# through the start of the crouch animation again.
		if desired == "crouch" and clip == "guard_low" and visual.frames != null and visual.frames.has_animation(desired):
			clock_ticks = maxi(0, visual.frames.get_frame_count(desired) - 1) * 3
		afterimages.clear()
		trail_clock = 0
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
	var profile: Resource = fighter.move.presentation if fighter.move != null else null
	if combat.phase != "fight":
		afterimages.clear()
	if not freeze_pose and combat.phase == "fight" and texture != null and profile != null and profile.trail_count > 0 and fighter.hitbox().has_area() and trail_clock >= 0.05:
		afterimages.append({"texture": texture, "x": fighter.x, "y": fighter.y, "facing": fighter.facing, "life": 0.10, "color":profile.color, "alpha":profile.trail_alpha})
		if afterimages.size() > profile.trail_count:
			afterimages.pop_front()
		trail_clock = 0
	queue_redraw()

func _clip() -> String:
	if combat.phase == "match_end" and combat.match_winner == fighter.slot:
		return "victory"
	if fighter.reaction == "throw_tech" and fighter.stun > 0:
		return _state_clip("throw_tech", "guard")
	if fighter.throw_role == "thrower":
		return _state_clip("throw_back" if fighter.throw_back else "throw_forward", "throw_success")
	if fighter.throw_role == "victim" or (fighter.state == "knockdown" and fighter.throw_frame >= Arena.THROW_IMPACT_TICK):
		return _state_clip("thrown_back" if fighter.throw_back else "thrown_forward", "thrown")
	if fighter.move != null:
		return fighter.move.clip_id()
	if fighter.roll_frame >= 0:
		return _state_clip("roll_back" if fighter.roll_direction * fighter.facing < 0 else "roll_forward", "jump_back" if fighter.roll_direction * fighter.facing < 0 else "jump_forward")
	if fighter.state == "dash":
		return "dash_back" if fighter.dash_back else "dash_forward"
	if fighter.state == "air" and fighter.flip_jump and not fighter.air_used_move:
		return "jump_back" if fighter.jump_back else "jump_forward"
	# Blockstun ends in idle for one tick; retain the held crouch on that tick.
	if fighter.grounded and fighter.crouching and fighter.stun == 0 and fighter.state in ["idle", "crouch"]:
		return "guard_low" if fighter.down and fighter.axis == -fighter.facing else "crouch"
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

func _state_clip(key: String, fallback: String) -> String:
	return visual.state_animations.get(key, fallback)

func _timeline_frame(tick: int, count: int) -> int:
	var timeline: Array = visual.clip_metadata.get(clip, {}).get("timeline", [])
	for n in range(mini(count, timeline.size()) - 1, -1, -1):
		if tick >= int(timeline[n]):
			return n
	return 0

func _frame_index() -> int:
	var count: int = visual.frames.get_frame_count(clip)
	# Hold the relaxed drawing; the other idle poses shift the cloth and weight sharply.
	# Smooth breathing below is anchored at the feet and freezes with the pose clock.
	if clip == "idle":
		return 0
	if fighter.reaction == "throw_tech" and fighter.stun > 0:
		return mini(count - 1, int((16 - fighter.stun) * float(count) / 16))
	if not fighter.throw_role.is_empty() or (fighter.state == "knockdown" and fighter.throw_frame >= Arena.THROW_IMPACT_TICK):
		if not visual.clip_metadata.get(clip, {}).get("timeline", []).is_empty():
			return _timeline_frame(fighter.throw_frame, count)
		if fighter.throw_frame >= Arena.THROW_IMPACT_TICK:
			return mini(count - 1, 8 + int((fighter.throw_frame - Arena.THROW_IMPACT_TICK) / 3))
		return mini(7, int(fighter.throw_frame / 20.0 * 8))
	if fighter.roll_frame >= 0:
		if visual.clip_metadata.get(clip, {}).get("timeline", []).is_empty():
			return mini(count - 1, int(fighter.roll_frame * float(count) / 28))
		return _timeline_frame(fighter.roll_frame, count)
	if clip in ["dash_forward", "dash_back"]:
		var duration: int = Arena.DASH_BACK_TICKS if fighter.dash_back else Arena.DASH_FORWARD_TICKS
		return mini(count - 1, int((fighter.dash_frame - 1) * float(count) / duration))
	if clip in ["jump_forward", "jump_back"]:
		return mini(count - 1, int(fighter.air_ticks * float(count) / 37))
	if fighter.move != null and clip == fighter.move.clip_id():
		var cuts: Array = visual.phases.get(clip, [maxi(1, count / 3), maxi(2, count * 2 / 3)])
		var first := clampi(int(cuts[0]), 1, count)
		var second := clampi(int(cuts[1]), first, count)
		var move: Resource = fighter.move
		if fighter.move_frame < move.startup:
			return mini(first - 1, int(float(fighter.move_frame) / move.startup * first))
		if fighter.move_frame < move.startup + move.active:
			if visual.clip_metadata.get(clip, {}).get("segment_sync", false):
				var segment: int = move.segment(fighter.move_frame)
				var group_start := first + int(segment * float(second - first) / move.hit_count())
				var group_end := first + int((segment + 1) * float(second - first) / move.hit_count())
				return mini(group_end - 1, group_start + int(move.segment_progress(fighter.move_frame) * (group_end - group_start)))
			return mini(count - 1, first + int(float(fighter.move_frame - move.startup) / move.active * maxi(1, second - first)))
		return mini(count - 1, second + int(float(fighter.move_frame - move.startup - move.active) / move.recovery * maxi(1, count - second)))
	if clip == "jump":
		if fighter.grounded:
			return mini(count - 1, 4 if fighter.state == "landing" or landing_ticks > 3 else 5)
		if fighter.air_used_move:
			return mini(count - 1, 3)
		if fighter.vy < -5:
			return mini(count - 1, 1)
		return mini(count - 1, 2 if fighter.vy < 2 else 3)
	if clip in ["guard", "guard_low"]:
		# The first drawing is preparation; impact drawings require a real block.
		if fighter.state != "block":
			return 0
		return mini(count - 1, 1 + int(clock_ticks / 5))
	if clip == "crouch":
		return mini(count - 1, int(clock_ticks / 3))
	var frame := int(clock_ticks / 60.0 * visual.frames.get_animation_speed(clip))
	return frame % count if visual.frames.get_animation_loop(clip) else mini(frame, count - 1)

func visual_bounds() -> Rect2:
	if texture == null or visual == null:
		return Rect2(-36, -84, 72, 84)
	var factor: Vector2 = _pose_scale() * visual.canonical_height / visual.source_height
	var bounds := Rect2(Vector2.ZERO, texture.get_size())
	if texture is AtlasTexture:
		bounds = Rect2(texture.margin.position, texture.region.size)
	bounds.position = (bounds.position - visual.feet_anchor) * factor
	bounds.size *= factor
	if pose_facing() < 0:
		bounds.position.x = -bounds.end.x
	return bounds

func _pose_scale() -> Vector2:
	if clip == "idle":
		return Vector2(1, 1 + sin(clock_ticks / 60.0 * TAU / IDLE_BREATH_SECONDS) * IDLE_BREATH_AMOUNT)
	return Vector2.ONE

func _draw() -> void:
	if fighter == null:
		return
	if texture != null:
		var factor: float = visual.canonical_height / visual.source_height
		for ghost: Dictionary in afterimages:
			draw_set_transform(Vector2(ghost.x - fighter.x, ghost.y - fighter.y), 0, Vector2(ghost.facing, 1))
			draw_texture_rect(ghost.texture, Rect2(-visual.feet_anchor * factor, ghost.texture.get_size() * factor), false, Color(ghost.color, ghost.alpha * ghost.life / 0.10))
		draw_set_transform(Vector2.ZERO, 0, Vector2(pose_facing(), 1))
		var pose_factor := _pose_scale() * factor
		var rect := Rect2(-visual.feet_anchor * pose_factor, texture.get_size() * pose_factor)
		# A restrained rim distinguishes mirrors without recoloring the costume.
		if combat.fighters[0].character == combat.fighters[1].character:
			for offset in [Vector2(-0.45, 0), Vector2(0.45, 0)]:
				draw_texture_rect(texture, Rect2(rect.position + offset, rect.size), false, player_accent * Color(1, 1, 1, 0.65))
		draw_texture_rect(texture, rect, false)
		draw_set_transform(Vector2.ZERO)
	if show_player_mark:
		draw_colored_polygon(PackedVector2Array([Vector2(-2, 3), Vector2(2, 3), Vector2(0, 5)]), player_accent)

func pose_facing() -> int:
	if not fighter.throw_role.is_empty() or (fighter.state == "knockdown" and fighter.throw_frame >= Arena.THROW_IMPACT_TICK):
		return fighter.throw_facing
	if clip in ["jump_forward", "jump_back"]:
		return fighter.facing if fighter.roll_frame >= 0 else fighter.jump_facing
	return fighter.facing
