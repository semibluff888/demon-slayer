extends Node2D
const AwakeningEffects = preload("res://scripts/presentation/awakening_effects.gd")
const TRAIL_SHADER = preload("res://scripts/presentation/afterimage.gdshader")
const Arena = preload("res://scripts/arena_rules.gd")
const Flow = preload("res://scripts/round_flow.gd")
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
var trail_layer: Node2D
var trail_clock: float = 0.0
var last_trail_pose: Dictionary = {}
var previous_attack_instance: int = -1
var previous_move_frame: int = -1
var previous_stun: int = 0
var was_grounded: bool = true
var landing_ticks: float = 0.0
var restart_requested: bool = false
var previous_form: bool = false
var awakening_effects: Node2D

func _ready() -> void:
	awakening_effects = AwakeningEffects.new()
	awakening_effects.actor = self
	add_child(awakening_effects)
	trail_layer = Node2D.new()
	trail_layer.name = "SuperAfterimages"
	trail_layer.show_behind_parent = true
	var ink := ShaderMaterial.new()
	ink.shader = TRAIL_SHADER
	trail_layer.material = ink
	add_child(trail_layer)
	trail_layer.draw.connect(_draw_super_trails)

func reset_pose() -> void:
	clock_ticks = 0
	previous_form = false
	if awakening_effects != null:
		awakening_effects.reset()
	trail_clock = 0
	afterimages.clear()
	last_trail_pose.clear()
	previous_attack_instance = -1
	texture = null
	clip = "idle"
	last_state = ""
	previous_move_frame = -1
	previous_stun = 0
	was_grounded = true
	landing_ticks = 0
	restart_requested = false
	if trail_layer != null:
		trail_layer.queue_redraw()

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
	var awakened := form_active()
	if awakened != previous_form:
		afterimages.clear()
		last_trail_pose.clear()
		previous_form = awakened
	var desired := _clip()
	var repeat_move: bool = fighter.move != null and fighter.move_frame < previous_move_frame
	var renewed_stun: bool = fighter.state in ["hit", "block", "knockdown"] and fighter.stun > previous_stun
	var new_attack: bool = fighter.move != null and fighter.attack_instance != previous_attack_instance
	if desired != clip or restart_requested or repeat_move or renewed_stun or new_attack:
		clock_ticks = 0
		# Releasing back keeps an already crouched fighter low instead of standing
		# through the start of the crouch animation again.
		if desired == "crouch" and clip == "guard_low" and visual.frames != null and visual.frames.has_animation(desired):
			clock_ticks = maxi(0, visual.frames.get_frame_count(desired) - 1) * 3
		if combat.phase != "round_end" or fighter.hp <= 0:
			afterimages.clear()
			last_trail_pose.clear()
			trail_clock = 0
		clip = desired
		restart_requested = false
	previous_move_frame = fighter.move_frame if fighter.move != null else -1
	previous_stun = fighter.stun
	previous_attack_instance = fighter.attack_instance
	if not freeze_pose:
		clock_ticks += delta * 60
		trail_clock += delta
		for ghost: Dictionary in afterimages:
			ghost.life -= delta
		afterimages = afterimages.filter(func(ghost: Dictionary) -> bool: return ghost.life > 0)
	if combat.phase == "round_end":
		clock_ticks = combat.outro_pose_ticks(fighter.slot)
	elif combat.phase == "intro":
		clock_ticks = combat.actor_intro_ticks()
	texture = null
	if _frames() != null and _frames().has_animation(clip) and _frames().get_frame_count(clip) > 0:
		frame_index = _frame_index()
		texture = _frames().get_frame_texture(clip, frame_index)
	var profile: Resource = fighter.move.presentation if fighter.move != null else null
	if combat.phase not in ["fight", "round_end"] or (combat.phase == "round_end" and fighter.hp <= 0):
		afterimages.clear()
		last_trail_pose.clear()
	if not freeze_pose and combat.presents_attack(fighter.slot) and texture != null and profile != null and profile.trail_count > 0:
		var move: Resource = fighter.move
		var emitting: bool = move.is_super() and fighter.move_frame < move.startup + move.active
		if not move.is_super():
			emitting = fighter.hitbox().has_area()
		var pose := {"at":Vector2(fighter.x, fighter.y), "texture":texture, "facing":pose_facing()}
		# Do not stack identical ghosts while stationary. Startup motion still
		# leaves a trail, and recovery lets existing samples finish fading.
		if emitting and pose != last_trail_pose and trail_clock + 0.000001 >= maxf(profile.trail_interval, 1.0 / 144):
			var duration: float = maxf(profile.trail_lifetime, 0.01)
			var tint: Color = profile.trail_color if profile.trail_color.a > 0 else profile.color
			var fade: Color = profile.trail_end_color if profile.trail_end_color.a > 0 else tint
			afterimages.append({"texture":texture, "x":fighter.x, "y":fighter.y, "facing":pose_facing(),
				"life":duration, "duration":duration, "color":tint, "end_color":fade, "silhouette":move.is_super(), "alpha":profile.trail_alpha,
				"scale":_pose_scale(), "anchor":visual.feet_anchor, "factor":visual.drawing_scale()})
			while afterimages.size() > profile.trail_count:
				afterimages.pop_front()
			last_trail_pose = pose
			trail_clock = fmod(maxf(0, trail_clock - profile.trail_interval), maxf(profile.trail_interval, 1.0 / 144))
	if not freeze_pose and fighter.awakening_ticks > 0 and fighter.character == "zenitsu" and fighter.state in ["walk", "dash"] and texture != null and trail_clock >= 0.045:
		afterimages.append({"texture":texture, "x":fighter.x, "y":fighter.y, "facing":pose_facing(),
			"life":0.16, "duration":0.16, "color":visual.awakening.color, "end_color":visual.awakening.color, "silhouette":false, "alpha":0.2,
			"scale":_pose_scale(), "anchor":visual.feet_anchor, "factor":visual.drawing_scale()})
		while afterimages.size() > 3:
			afterimages.pop_front()
		trail_clock = 0
	if awakening_effects != null:
		awakening_effects.sync(delta, freeze_pose)
	queue_redraw()
	if trail_layer != null:
		trail_layer.queue_redraw()

func _clip() -> String:
	if fighter.awakening_startup > 0 and fighter.state == "awakening" and visual.awakening_frames != null:
		return visual.awakening.start_clip
	if combat.phase == "intro" and combat.phase_frames > Flow.INTRO:
		return _state_clip("round_intro", "idle")
	if combat.phase == "round_end":
		if combat.outro_ticks >= combat.victory_at and combat.round_winner == fighter.slot:
			return _state_clip("round_victory", "victory")
		if fighter.hp == 0 and combat.outro_ticks >= Flow.FREEZE and not combat.preserves_throw_pose(fighter.slot):
			return _state_clip("round_defeat", "knockdown")
		if not combat.is_knockout() and fighter.grounded:
			return "idle"
	if combat.phase == "match_end":
		if combat.match_winner == fighter.slot:
			return _state_clip("round_victory", "victory")
		if fighter.hp > 0:
			return "idle"
		return _state_clip("thrown_back" if fighter.throw_back else "thrown_forward", "thrown") if combat.preserves_throw_pose(fighter.slot) else _state_clip("round_defeat", "knockdown")
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
	var count: int = _frames().get_frame_count(clip)
	if visual.awakening != null and clip == visual.awakening.start_clip:
		var duration := 6 if fighter.awakening_quick else 18
		return mini(count - 1, int(float(duration - fighter.awakening_startup) / duration * count))
	if clip == "round_intro":
		return mini(count - 1, int(combat.actor_intro_ticks() * float(count) / Flow.ACTOR_INTRO))
	if clip == "round_defeat":
		return mini(count - 1, combat.defeat_frame(fighter.slot))
	if clip == "round_victory":
		return count - 1 if combat.phase == "match_end" else mini(count - 1, int(clock_ticks * count / (Flow.RESULT - 15)))
	# A hit begins on impact, never on the neutral lead-in or recovered drawing.
	# Hitstop holds the impact; renewed hits restart the same authored pain sequence.
	if clip == "hit" and not visual.hit_reaction_frames.is_empty():
		var reaction_step := mini(visual.hit_reaction_frames.size() - 1, int(clock_ticks / 5.0))
		return clampi(visual.hit_reaction_frames[reaction_step], 0, count - 1)
	if combat.phase == "round_end" and clip in ["victory", "knockdown", "hit"]:
		return mini(count - 1, int(clock_ticks / 60.0 * _frames().get_animation_speed(clip)))
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
		if move.lift != 0 and not fighter.grounded:
			# Active ascent -> apex -> falling pose. Never show the planted final
			# recovery drawing in midair (especially visible on Zenitsu's upward iai).
			return maxi(first, second - 1) if fighter.vy < 0 else mini(count - 2, second)
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
	var frame := int(clock_ticks / 60.0 * _frames().get_animation_speed(clip))
	return frame % count if _frames().get_animation_loop(clip) else mini(frame, count - 1)

func visual_bounds() -> Rect2:
	if texture == null or visual == null:
		return Rect2(-36, -84, 72, 84)
	var factor: Vector2 = _pose_scale() * visual.drawing_scale()
	var bounds := Rect2(Vector2.ZERO, texture.get_size())
	if texture is AtlasTexture:
		bounds = Rect2(texture.margin.position, texture.region.size)
	bounds.position = (bounds.position - visual.feet_anchor) * factor
	bounds.size *= factor
	if pose_facing() < 0:
		bounds.position.x = -bounds.end.x
	return bounds

func _pose_scale() -> Vector2:
	var size: float = float(visual.awakening.form_scale) if form_active() and visual.awakening != null else 1.0
	var breath := 1.0 + sin(clock_ticks / 60.0 * TAU / IDLE_BREATH_SECONDS) * IDLE_BREATH_AMOUNT if clip == "idle" else 1.0
	return Vector2(size, size * breath)

func _draw() -> void:
	if fighter == null:
		return
	_draw_awakening()
	if texture != null:
		var factor: float = visual.drawing_scale()
		for ghost: Dictionary in afterimages:
			if not ghost.get("silhouette", false):
				_draw_ghost(self, ghost)
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

func trail_modulate(ghost: Dictionary) -> Color:
	var remaining := clampf(float(ghost.life) / float(ghost.duration), 0, 1)
	if not ghost.get("silhouette", false):
		return Color(ghost.color, ghost.alpha * remaining)
	var tint: Color = ghost.color.lerp(ghost.end_color, 1 - remaining)
	# Hold the fresh silhouette briefly, then fade smoothly through blue-violet.
	return Color(tint, ghost.alpha * smoothstep(0.0, 0.85, remaining))

func _draw_ghost(canvas: Node2D, ghost: Dictionary) -> void:
	canvas.draw_set_transform(Vector2(ghost.x - fighter.x, ghost.y - fighter.y), 0, Vector2(ghost.facing, 1))
	var factor: Vector2 = ghost.scale * ghost.factor
	canvas.draw_texture_rect(ghost.texture, Rect2(-ghost.anchor * factor, ghost.texture.get_size() * factor), false, trail_modulate(ghost))

func _draw_super_trails() -> void:
	if fighter == null:
		return
	for ghost: Dictionary in afterimages:
		if ghost.get("silhouette", false):
			_draw_ghost(trail_layer, ghost)
	trail_layer.draw_set_transform(Vector2.ZERO)

func pose_facing() -> int:
	if clip == "round_defeat" and not combat.outro_paths[fighter.slot].is_empty():
		return int(combat.outro_paths[fighter.slot].pose_facing)
	if not fighter.throw_role.is_empty() or (fighter.state == "knockdown" and fighter.throw_frame >= Arena.THROW_IMPACT_TICK):
		return fighter.throw_facing
	if clip in ["jump_forward", "jump_back"]:
		return fighter.facing if fighter.roll_frame >= 0 else fighter.jump_facing
	return fighter.facing

func form_active() -> bool:
	if fighter == null or fighter.hp <= 0:
		return false
	return fighter.awakening_ticks > 0 or (fighter.character == "nezuko" and fighter.move != null and fighter.move.clip_id() == "awakened_combo")

func _frames() -> SpriteFrames:
	if form_active() and visual.awakening_frames != null and visual.awakening_frames.has_animation(clip):
		return visual.awakening_frames
	return visual.frames

func _draw_awakening() -> void:
	# Akaza retains his approved compass and original particle treatment.
	if fighter.character != "akaza":
		return
	if fighter.awakening_ticks <= 0 or visual.awakening == null:
		return
	var color: Color = visual.awakening.color
	var phase := clock_ticks / 60.0
	var fade := 0.7 + 0.3 * sin(phase * 6.0) if fighter.awakening_ticks <= 120 else 1.0
	# Local effects share the frozen pose clock and never drive collision.
	for n in range(7):
		var progress := fmod(phase * 0.8 + n / 7.0, 1.0)
		var side := -1.0 if n % 2 == 0 else 1.0
		var at := Vector2(side * (12 + sin(progress * PI) * 11), -progress * 80)
		draw_circle(at, 2.0 + 3.0 * (1.0 - progress), Color(color, (1.0 - progress) * 0.12 * fade))
		draw_line(at + Vector2(0, 7), at - Vector2(1, 3), Color(color, (1.0 - progress) * 0.5 * fade), 1.1, true)
	if fighter.awakening_startup > 0:
		var duration := 6 if fighter.awakening_quick else 18
		var radius: float = 12 + (duration - fighter.awakening_startup) * 2.5
		draw_arc(Vector2(0, -32), radius, 0, TAU, 48, Color(color, 0.65), 1.3, true)
	if fighter.character == "akaza":
		var floor_offset: float = Arena.FLOOR_Y - fighter.y
		draw_set_transform(Vector2(0, floor_offset), 0, Vector2(1, 0.3))
		var shine := 0.85 if fighter.state == "block" else 0.4
		draw_arc(Vector2.ZERO, 33, 0, TAU, 64, Color(color, shine * fade), 1.2, true)
		for n in range(12):
			var direction := Vector2.from_angle(n * TAU / 12 + phase * 0.12)
			draw_line(direction * 6, direction * 33, Color(color, shine * fade), 1.1, true)
			for side in [-1, 1]:
				draw_line(direction * 22, direction * 18 + direction.orthogonal() * side * 5, Color(color, shine * fade), 1.1, true)
		draw_set_transform(Vector2.ZERO)
	elif fighter.character == "zenitsu":
		for side in [-1, 1]:
			var points := PackedVector2Array()
			for n in range(7):
				points.append(Vector2(side * (16 + sin(phase * 18 + n * 2) * 5), -8 - n * 10))
			draw_polyline(points, Color(color, 0.65 * fade), 0.9, true)
	elif fighter.character == "nezuko":
		var anchors := [Vector2(-9, -3), Vector2(10, -3), Vector2(fighter.facing * 15, -36)]
		if fighter.move != null and fighter.move.kind in ["light", "heavy", "skill"]:
			var strike_at: Vector2 = fighter.move.box.get_center()
			strike_at.x *= fighter.facing
			anchors[2] = strike_at
		for at: Vector2 in anchors:
			for n in range(3):
				var progress := fmod(phase * 2.5 + n / 3.0, 1.0)
				draw_circle(at + Vector2(sin(phase * 12 + n) * 2, -progress * 9), 2.7 * (1 - progress), Color(color, 0.6 * (1 - progress) * fade))
	elif fighter.character == "tanjiro":
		for n in range(3):
			var p := fmod(phase * 0.5 + n / 3.0, 1.0)
			draw_circle(Vector2(fighter.facing * (8 + p * 12), -62 - p * 6), 1.2 + p * 3, Color(0.95, 0.96, 1, (1 - p) * 0.22))
