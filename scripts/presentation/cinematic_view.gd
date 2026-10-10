extends Node2D
## Owns video playback and the short in-engine landing. Combat owns damage.
const KO_SECONDS := 0.8
const KO_TRANSITION := 0.12
const RoundBanner = preload("res://scripts/presentation/round_banner.gd")
const CATALOG := "res://resources/cinematics/catalog.json"
var app: Node
var world: Node2D
var profiles: Dictionary = {}
var streams: Dictionary = {}
var audio_streams: Dictionary = {}
var soundtrack: AudioStreamPlayer
var active: bool = false
var phase: String = ""
var profile: Dictionary = {}
var move_id: String = ""
var profile_id: String = ""
var actor_slot: int = 0
var elapsed: float = 0.0
var tail_time: float = 0.0
var stalled: float = 0.0
var previous_position: float = -1.0
var movie: VideoStreamPlayer
var backdrop: ColorRect
var landed: bool = false
var residual_effect: Sprite2D
var ko_overlay: Node2D
var ko_banner: Control
var freeze_texture: ImageTexture
var ko_time: float = 0.0
var tail_prepared: bool = false
var map_ko: bool = false

func _ready() -> void:
	if FileAccess.file_exists(CATALOG):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if data is Dictionary:
			profiles = data.get("moves", {})
	# Effect textures use black-backed additive artwork. Keep this material off
	# the controller itself so the movie and its backdrop retain normal blending.
	residual_effect = Sprite2D.new()
	residual_effect.name = "RecoveryEffect"
	residual_effect.show_behind_parent = true
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	residual_effect.material = additive
	add_child(residual_effect)
	residual_effect.hide()
	soundtrack = AudioStreamPlayer.new()
	add_child(soundtrack)
	backdrop = ColorRect.new()
	backdrop.size = Vector2(1280, 720)
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	movie = VideoStreamPlayer.new()
	movie.name = "UltimateVideo"
	movie.expand = true
	movie.size = Vector2(1280, 720)
	movie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	movie.finished.connect(_video_finished)
	add_child(movie)
	backdrop.hide()
	movie.hide()
	ko_overlay = Node2D.new()
	ko_overlay.name = "KnockoutFreeze"
	add_child(ko_overlay)
	ko_overlay.draw.connect(_draw_ko_overlay)
	ko_banner = RoundBanner.new()
	ko_banner.title_font = world.catalog.title_font
	ko_banner.body_font = world.catalog.body_font
	ko_overlay.add_child(ko_banner)
	ko_overlay.hide()

func prepare(characters: Array) -> void:
	streams.clear()
	audio_streams.clear()
	for id: String in profiles:
		if id.get_slice("_", 0) not in characters:
			continue
		var path: String = profiles[id].video
		if ResourceLoader.exists(path):
			var stream := load(path) as VideoStream
			var audio_path: String = profiles[id].get("audio", "")
			var audio: AudioStream = load(audio_path) as AudioStream if ResourceLoader.exists(audio_path) else null
			if stream != null and audio != null:
				streams[id] = stream
				audio_streams[id] = audio

func blocks_combat() -> bool:
	return active and world.combat.cinematic_blocks_combat()

func is_video_visible() -> bool:
	return active and phase in ["video", "ko_freeze"]

func hides_stage() -> bool:
	return is_video_visible() and not tail_prepared

func available_moves() -> Dictionary:
	# A missing alternate must not substitute the wrong character form.
	var available := streams.duplicate()
	for id: String in available.keys():
		var alternate: String = profiles[id].get("awakened_profile", "")
		if not alternate.is_empty() and not streams.has(alternate):
			available.erase(id)
	return available

func begin() -> void:
	var model: RefCounted = world.combat
	if active or model.cinematic.is_empty():
		return
	actor_slot = int(model.cinematic.attacker)
	move_id = str(model.cinematic.move)
	profile_id = move_id
	if model.cinematic.get("awakened", false):
		profile_id = profiles.get(move_id, {}).get("awakened_profile", move_id)
	profile = profiles.get(profile_id, {})
	active = true
	phase = "video"
	elapsed = 0
	tail_time = 0
	stalled = 0
	previous_position = -1
	landed = false
	tail_prepared = false
	map_ko = false
	ko_time = 0
	_clear_ko_overlay()
	world.effects.reset_effects()
	world.super_view.reset_effects()
	for actor in world.fighters:
		actor.reset_pose()
	app.sound.reset_audio()
	movie.stream = streams.get(profile_id)
	if movie.stream == null:
		# Missing/failed assets cannot leave the match locked.
		_begin_tail()
		return
	soundtrack.stream = audio_streams.get(profile_id)
	soundtrack.stream_paused = false
	sync_audio()
	movie.paused = false
	movie.show()
	backdrop.show()
	movie.play()
	soundtrack.play()
	world.hud.cinematic_mode = true
	app.gui.visible = false

func sync_audio() -> void:
	if movie != null and app != null:
		movie.volume = 0.0 if app.settings.muted else app.settings.volume
		soundtrack.volume_db = linear_to_db(maxf(movie.volume, 0.00001))

func _process(delta: float) -> void:
	if not active or app == null:
		return
	var frozen: bool = app.paused or app.screen != "battle"
	movie.paused = frozen or phase != "video"
	soundtrack.stream_paused = frozen
	sync_audio()
	app.gui.visible = frozen or not is_video_visible()
	if frozen:
		return
	if phase == "video":
		elapsed += delta
		var position := movie.stream_position
		stalled = stalled + delta if is_equal_approx(position, previous_position) else 0.0
		previous_position = position
		world.combat.advance_cinematic(position / maxf(0.1, float(profile.get("duration", 1.0))))
		world.hud.consume(world.combat.events)
		# Some clips end in a white transition. Cache their authored last impact,
		# but still play the complete video and soundtrack before showing KO.
		var frame_limit := float(profile.get("ko_frame_time", profile.get("duration", 1.0)))
		if world.combat.cinematic_is_lethal() and position >= frame_limit - 0.25 and position <= frame_limit:
			_cache_video_frame()
		if app.mode == "practice":
			app.practice_controller.after_step(world.combat)
		# Decoder failure fallback, paused time excluded. Normal completion uses finished.
		if stalled > 2.0 or elapsed > float(profile.get("duration", 1.0)) + 8.0:
			_finish_video()
	elif phase == "ko_freeze":
		ko_time = minf(KO_SECONDS, ko_time + delta)
		if ko_time >= KO_SECONDS - KO_TRANSITION and not tail_prepared:
			_prepare_tail()
		_update_ko_overlay(ko_time)
		if ko_time >= KO_SECONDS:
			_begin_tail()
	elif phase == "tail":
		tail_time += delta
		_update_tail()
		if map_ko:
			_update_ko_overlay(tail_time)
		if tail_time >= float(profile.get("tail_seconds", 1.15)):
			_complete()
	queue_redraw()

func _cache_video_frame() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var texture := movie.get_video_texture()
	if texture == null:
		return
	var frame := texture.get_image()
	if frame == null or frame.is_empty():
		return
	if freeze_texture == null:
		freeze_texture = ImageTexture.create_from_image(frame)
	else:
		freeze_texture.update(frame)

func _video_finished() -> void:
	if active and phase == "video":
		_finish_video()

func _finish_video() -> void:
	if not active or phase != "video":
		return
	world.combat.advance_cinematic(1.0)
	world.hud.consume(world.combat.events)
	if world.combat.cinematic_is_lethal() and freeze_texture != null:
		phase = "ko_freeze"
		ko_time = 0
		movie.stop()
		soundtrack.stop()
		movie.hide()
		backdrop.hide()
		_announce_ko()
		_update_ko_overlay(0.0)
	else:
		_begin_tail()

func _announce_ko() -> void:
	world.combat.events.clear()
	world.combat.announce_cinematic_ko()
	app.sound.consume(world.combat.events, world.combat)

func _prepare_tail() -> void:
	if tail_prepared:
		return
	tail_prepared = true
	tail_time = 0
	world.combat.begin_cinematic_tail(bool(profile.get("face_away", false)))
	world.hud.consume(world.combat.events)
	if app.mode == "practice":
		app.practice_controller.after_step(world.combat)
	world.camera.reset(world.combat.fighters)
	_update_tail()
	world._process(0.0)

func _begin_tail() -> void:
	if not active or phase == "tail":
		return
	phase = "tail"
	movie.stop()
	soundtrack.stop()
	movie.hide()
	backdrop.hide()
	_clear_ko_overlay()
	world.hud.cinematic_mode = false
	app.gui.visible = true
	_prepare_tail()
	if world.combat.cinematic_is_lethal() and not world.combat.cinematic.get("ko_announced", false):
		# Failed video has no trustworthy final frame: announce once on the map.
		map_ko = true
		_announce_ko()
		_update_ko_overlay(0.0)
	world._process(0.0)
	app.sound.play(str(profile.get("effect", "shockwave")), 0.75)

func _clear_ko_overlay() -> void:
	freeze_texture = null
	if ko_overlay != null:
		ko_overlay.hide()
		ko_overlay.modulate = Color.WHITE
		ko_overlay.queue_redraw()
		ko_banner.cue = {}

func _update_ko_overlay(age: float) -> void:
	ko_overlay.visible = age < KO_SECONDS
	ko_overlay.modulate.a = clampf((KO_SECONDS - age) / KO_TRANSITION, 0, 1)
	ko_banner.cue = {"text":"K.O.", "age":age * 60.0, "duration":KO_SECONDS * 60.0 + 8.0, "pop_ticks":9.6}
	ko_banner.queue_redraw()
	ko_overlay.queue_redraw()

func _draw_ko_overlay() -> void:
	var age := ko_time if phase == "ko_freeze" else tail_time
	if phase == "ko_freeze" and freeze_texture != null:
		var shake := Vector2(sin(age * 83), cos(age * 97)) * (4.0 * maxf(0, 1.0 - age / 0.16))
		ko_overlay.draw_texture_rect(freeze_texture, Rect2(Vector2(-7, -4) + shake, Vector2(1294, 728)), false)
		ko_overlay.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.025, 0.04, 0.18))
	var flash := 0.5 * maxf(0, 1.0 - age / 0.08)
	if flash > 0:
		ko_overlay.draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, flash))

func _update_tail() -> void:
	var model: RefCounted = world.combat
	var actor: RefCounted = model.fighters[actor_slot]
	var victim: RefCounted = model.fighters[1 - actor_slot]
	var recovery_seconds := maxf(0.01, float(profile.get("recovery_seconds", 0.65)))
	var progress := clampf(tail_time / recovery_seconds, 0, 1)
	var fall := clampf(tail_time / 0.32, 0, 1)
	var land := clampf(tail_time / 0.24, 0, 1)
	if blocks_combat():
		actor.y = model.FLOOR_Y - float(profile.get("attacker_height", 0.0)) * (1.0 - land * land)
		actor.grounded = land >= 1.0 or is_zero_approx(float(profile.get("attacker_height", 0.0)))
		var frames: Array = profile.get("recovery_frames", [0])
		world.fighters[actor_slot].cinematic_pose = {"clip":profile.get("recovery_clip", "idle"),
			"frame":frames[mini(frames.size() - 1, floori(progress * frames.size()))], "facing":actor.facing,
			"awakened":profile_id == "nezuko_max"}
		if progress >= 1.0 and not model.cinematic_is_lethal():
			model.release_cinematic_actor()
			app._reset_inputs()
			# Hand off without clearing the current texture or restarting other effects.
			world.fighters[actor_slot].cinematic_pose.clear()
			world.fighters[actor_slot].sync(0.0, true)
	victim.y = model.FLOOR_Y - 28.0 * (1.0 - fall * fall)
	victim.grounded = fall >= 1.0
	world.fighters[1 - actor_slot].cinematic_pose = {"clip":"round_defeat", "frame":mini(11, 4 + floori(tail_time / 0.065)), "facing":victim.facing}
	_update_residual_effect()
	if fall >= 1.0 and not landed:
		landed = true
		app.sound.play("throw", 0.45)
	if blocks_combat():
		world.camera.shake = Vector2(sin(tail_time * 83), cos(tail_time * 97)) * (3.0 * maxf(0, 1 - absf(tail_time - 0.32) / 0.15))

func _complete() -> void:
	residual_effect.hide()
	var model: RefCounted = world.combat
	var actor_locked: bool = blocks_combat()
	model.finish_cinematic()
	# Switch directly from the held recovery to the first victory drawing.
	if actor_locked:
		world.fighters[actor_slot].cinematic_pose.clear()
		world.fighters[actor_slot].sync(0.0, true)
		app._reset_inputs()
	world.fighters[1 - actor_slot].cinematic_pose.clear()
	_clear_ko_overlay()
	active = false
	phase = ""
	world.hud.cinematic_mode = false
	world.fighters[1 - actor_slot].sync(0.0, true)
	world.consume(model.events)
	app.sound.consume(model.events, model)
	app.gui.visible = true
	queue_redraw()

func cancel() -> void:
	_clear_ko_overlay()
	tail_prepared = false
	map_ko = false
	ko_time = 0
	if residual_effect != null:
		residual_effect.hide()
	active = false
	phase = ""
	if movie != null:
		movie.stop()
		soundtrack.stop()
		soundtrack.stream = null
		movie.stream = null
		movie.hide()
		backdrop.hide()
	for actor in world.fighters:
		actor.cinematic_pose.clear()
	world.hud.cinematic_mode = false
	world.combat.cinematic.clear()
	world.combat.cinematic_victory_form_slot = -1
	if app != null:
		app.gui.visible = true
	queue_redraw()

func _update_residual_effect() -> void:
	var kind: String = profile.get("effect", "shockwave")
	var texture_keys := {"water":"water-slash-spray", "flame":"sun-flame-arc", "blood":"blood-flame", "thunder":"thunder", "shockwave":"shockwave"}
	residual_effect.texture = world.effects.textures.get(texture_keys[kind])
	var fade := maxf(0, 1 - tail_time / float(profile.get("tail_seconds", 1.15)))
	residual_effect.visible = residual_effect.texture != null and fade >= 0.02
	if not residual_effect.visible:
		return
	var model: RefCounted = world.combat
	var victim: RefCounted = model.fighters[1 - actor_slot]
	var at: Vector2 = world.camera.point(Vector2(victim.x, model.FLOOR_Y))
	var extent := Vector2(360, 210) * (1.0 + tail_time * 0.25)
	residual_effect.scale = extent / residual_effect.texture.get_size()
	residual_effect.modulate = Color(1, 1, 1, fade * fade * 0.7)
	# Rotate the authored horizontal lightning into an upright bolt at impact.
	residual_effect.rotation = PI / 2 if kind == "thunder" else 0.0
	residual_effect.position = at - Vector2(0, extent.x * 0.45 if kind == "thunder" else extent.y * 0.38)

func _draw() -> void:
	if not active or not tail_prepared:
		return
	var model: RefCounted = world.combat
	var victim: RefCounted = model.fighters[1 - actor_slot]
	var at: Vector2 = world.camera.point(Vector2(victim.x, model.FLOOR_Y))
	var fade := maxf(0, 1 - tail_time / float(profile.get("tail_seconds", 1.15)))
	if fade < 0.02:
		return
	var kind: String = profile.get("effect", "shockwave")
	var colors := {"water":Color("72dfff"), "flame":Color("ff9c3e"), "thunder":Color("a6dcff"), "blood":Color("ff4e97"), "shockwave":Color("70dfff")}
	var tint: Color = colors[kind]
	# Draw the residual element at the actual victim, never the prerecorded opponent.
	for n in range(22):
		var angle := n * 2.39996
		var age := tail_time + (n % 4) * 0.017
		var distance := 24 + age * (35 + n % 5 * 17)
		var p := at + Vector2(cos(angle) * distance, -absf(sin(angle)) * (36 + age * 120) + age * age * 100)
		draw_line(p, p + Vector2(cos(angle) * 5, -5 - n % 4 * 2), Color(tint, fade * 0.8), 1.5, true)
	if kind in ["flame", "blood"]:
		for n in range(11):
			var base := at + Vector2((n - 5) * 19, 0)
			var height := (45 + sin(n * 1.9) * 20) * fade
			draw_colored_polygon(PackedVector2Array([base + Vector2(-10, 0), base + Vector2(3 + sin(tail_time * 14 + n) * 8, -height), base + Vector2(10, 0)]), Color(tint, 0.5 * fade))
	elif kind == "water":
		draw_set_transform(at, 0, Vector2(1, 0.26))
		for n in range(3):
			draw_arc(Vector2.ZERO, 32 + n * 24 + tail_time * 54, 0, TAU, 60, Color(tint, fade * 0.55), 3 - n * 0.6, true)
		draw_set_transform(Vector2.ZERO)
	elif kind == "shockwave":
		draw_set_transform(at, 0, Vector2(1, 0.36))
		draw_arc(Vector2.ZERO, 70 + tail_time * 85, 0, TAU, 64, Color(tint, fade * 0.6), 2, true)
		for n in range(12):
			var direction := Vector2.from_angle(n * TAU / 12)
			draw_line(direction * 25, direction * 100, Color(tint, fade * 0.35), 1.5, true)
		draw_set_transform(Vector2.ZERO)
	if tail_time >= 0.24:
		var dust_age := tail_time - 0.24
		for n in range(9):
			var side := -1 if n % 2 == 0 else 1
			var p := at + Vector2(side * (12 + n * 8 + dust_age * 55), -4 - sin(n * 1.7) * 8)
			draw_circle(p, (6 + n % 3 * 3) * maxf(0, 1 - dust_age), Color(0.66, 0.69, 0.72, fade * 0.24))
