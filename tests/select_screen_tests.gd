extends SceneTree
## Character select: 4-column grid with placeholders and the random cell, cursor wrap,
## random locks and reveal hold, mouse cells, and the showcase clip wiring.
const Main = preload("res://scenes/main.tscn")
const RosterCard = preload("res://scripts/ui/roster_card.gd")
const Selection = preload("res://scripts/ui/selection_controller.gd")
const SelectVideo = preload("res://scripts/ui/select_video.gd")
const GradientText = preload("res://scripts/ui/gradient_text.gd")
const SHADER = preload("res://scripts/ui/shaders/stacked_alpha.gdshader")
var passed := 0
var failures: Array[String] = []
var game: Node2D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else: failures.append(message)

func _run() -> void:
	game = Main.instantiate()
	game.settings.path = "res://artifacts/select_screen_tests-settings.cfg"
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	game.settings.save_config()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	await process_frame
	await _test_grid()
	await _test_navigation()
	await _test_random()
	await _test_mouse_and_local()
	await _test_showcase()
	await _test_fallback_and_playback()
	game.queue_free()
	await process_frame
	for failure in failures: printerr("FAIL: ", failure)
	print("SELECT SCREEN TESTS: %d passed, %d failed" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _key(key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	game._input(event)

func _setup(mode: String, picks: Array = ["tanjiro", "zenitsu"]) -> void:
	game.devices.assign(["keyboard:0", "keyboard:1"])
	game.characters.assign(picks)
	game.choose_mode(mode)
	await process_frame

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame

func _test_grid() -> void:
	await _setup("cpu")
	var gui: Control = game.gui
	var names: Array[String] = []
	for card: Button in gui.roster_cells:
		names.append(str(card.name))
	var expected: Array[String] = ["character_tanjiro", "character_zenitsu", "character_nezuko", "character_akaza"]
	for i in range(4, 15):
		expected.append("empty_%d" % i)
	expected.append("random")
	check(names == expected, "16 cells: roster, placeholders, random last (%s)" % [names])
	check(gui.roster_cards.size() == 4 and gui.random_card == gui.roster_cells[15], "roster_cards holds characters only")
	await process_frame
	var view: Rect2 = gui.roster_scroll.get_global_rect()
	check(Rect2(412, 112, 456, 488).encloses(view), "grid viewport inside its plate")
	for card: Button in gui.roster_cells:
		check(card.size == RosterCard.CELL and view.grow(0.5).encloses(card.get_global_rect()), "cell %s sized and visible" % card.name)
		check(card.has_meta("select_cell"), "cell %s marked for Enter confirm" % card.name)
	check(gui.roster_cells[15].kind == "random" and gui.roster_cells[4].kind == "empty", "cell kinds")
	check(not gui.get_children().any(func(child: Node) -> bool: return child.get_script() == GradientText), "VS emblem removed")
	for slot in range(2):
		var showcase: Control = gui.fighter_portraits[slot]
		await _wait(0.35)
		check(showcase.video.position == showcase._video_rect().position, "showcase %d clip settles in place" % slot)
	check(gui.fighter_portraits[0]._video_rect() == Rect2(0, 144, 384, 576) and gui.fighter_portraits[1]._video_rect() == Rect2(896, 144, 384, 576),
		"clips flush with the outer screen edges")

func _test_navigation() -> void:
	await _setup("cpu")
	var gui: Control = game.gui
	var selection: RefCounted = game.selection
	_key(KEY_A)
	check(game.characters[0] == "akaza", "left wraps within the row")
	_key(KEY_D)
	check(game.characters[0] == "tanjiro", "right wraps back")
	_key(KEY_W)
	check(selection.cursor_cell(0) == 12 and game.characters[0] == "tanjiro", "up wraps to the placeholder row; pick kept")
	check(gui.fighter_names[0].text == "敬请期待" and gui.fighter_portraits[0].kind == "empty", "placeholder panel")
	check(gui.roster_cells[12].cursors == [0], "placeholder shows the cursor")
	_key(KEY_U)
	check(not selection.ready[0] and game.screen == "setup", "placeholder cannot be confirmed")
	gui.actions.start.pressed.emit()
	check(not selection.ready[0], "start button also rejects a placeholder")
	for i in range(3):
		_key(KEY_D)
	check(selection.cell_id(0) == Selection.RANDOM and gui.fighter_names[0].text == "随机角色", "random cell reached")
	check(gui.fighter_portraits[0].kind == "random" and gui.fighter_portraits[0].video.visual == null, "random panel hides the clip")
	_key(KEY_S)
	check(game.characters[0] == "akaza" and selection.special[0] == -1, "down wraps to the top row")
	game.characters.assign(["nezuko", "zenitsu"])
	gui.refresh_setup()
	_key(KEY_D)
	check(game.characters[0] == "akaza", "cursor follows assigned picks")

func _test_random() -> void:
	await _setup("cpu")
	var gui: Control = game.gui
	var selection: RefCounted = game.selection
	var ids: Array = game.catalog.characters.keys()
	var oracle := RandomNumberGenerator.new()
	oracle.seed = 7
	var first: String = ids[oracle.randi_range(0, ids.size() - 1)]
	var second: String = ids[oracle.randi_range(0, ids.size() - 1)]
	selection.rng.seed = 7
	selection.point(0, 15)
	_key(KEY_U)
	check(selection.ready[0] and selection.rolled[0] and game.characters[0] == first, "random lock picks with the seeded rng")
	check(selection.cursor_cell(0) == ids.find(first), "cursor jumps to the rolled character")
	check(gui.fighter_portraits[0].rolling() and gui.fighter_portraits[0]._shown_kind() == "random", "showcase spins the roulette")
	await process_frame
	check(gui.fighter_names[0].modulate.a == 0.0, "name hidden while rolling")
	check(selection.active_slot == 1 and game.screen == "setup", "P1 then picks the CPU")
	selection.point(1, 15)
	_key(KEY_U)
	check(game.characters[1] == second and selection.ready == [true, true], "CPU random lock")
	check(game.screen == "setup" and selection.revealing(), "final random lock holds before the stage screen")
	_key(KEY_I)
	game._back_or_pause()
	gui.actions.start.pressed.emit()
	check(selection.ready == [true, true] and game.screen == "setup", "input held during the reveal")
	await _wait(Selection.REVEAL_SECONDS + 0.1)
	check(game.screen == "stage", "stage screen follows the reveal")
	game.gui.actions.back.pressed.emit()
	check(game.screen == "setup" and selection.rolled == [false, false] and selection.cursor_cell(0) == ids.find(first),
		"back to select keeps rolled picks unlocked")
	await process_frame
	check(game.gui.fighter_names[0].modulate.a == 1.0, "name visible again")
	# A random lock that is not the last one, then an ordinary final lock: no hold.
	selection.point(0, 15)
	_key(KEY_U)
	_key(KEY_U)
	check(game.screen == "stage", "ordinary final lock opens the stage immediately")

func _test_mouse_and_local() -> void:
	await _setup("local")
	var gui: Control = game.gui
	var selection: RefCounted = game.selection
	gui.actions.random.pressed.emit()
	check(selection.cursor_cell(selection.active_slot) == 15, "clicking random moves the active cursor")
	gui.actions.empty_5.pressed.emit()
	check(selection.cursor_cell(selection.active_slot) == 5, "clicking a placeholder moves the active cursor")
	gui.actions.character_nezuko.pressed.emit()
	check(game.characters[selection.active_slot] == "nezuko" and selection.special[selection.active_slot] == -1 and not selection.ready[selection.active_slot],
		"clicking a character picks without locking")
	await _setup("local")
	gui = game.gui
	await _wait(SelectVideo.DEBOUNCE + 0.05)
	var p1_video: Control = gui.fighter_portraits[0].video
	var p1_stream: VideoStream = p1_video.player.stream
	_key(KEY_UP)
	check(selection.cursor_cell(1) == 13 and selection.cursor_cell(0) == 0, "P2 arrows move only P2")
	check(gui.fighter_portraits[1].kind == "empty" and gui.fighter_portraits[0].kind == "character", "panels follow their own cursor")
	await process_frame
	check(p1_video.player.stream == p1_stream and p1_stream != null and p1_video.pending < 0.0, "moving P2 leaves P1's clip running")
	_key(KEY_KP_5)
	check(not selection.ready[1], "P2 cannot lock a placeholder")
	_key(KEY_DOWN)
	_key(KEY_KP_5)
	check(selection.ready[1] and game.characters[1] == "zenitsu", "P2 locks after returning to a character")

func _test_showcase() -> void:
	await _setup("local")
	var gui: Control = game.gui
	for id: String in game.catalog.characters:
		var visual: Resource = game.catalog.characters[id]
		check(visual.select_video != null and visual.select_poster != null and visual.select_layout.get("gutter", 0) == 16,
			"select clip assets load for " + id)
		game.select_character(0, id)
		game.select_character(1, id)
		await _wait(SelectVideo.DEBOUNCE + 0.05)
		for slot in range(2):
			var video: Control = gui.fighter_portraits[slot].video
			var paint: ShaderMaterial = video.player.material
			check(video.visual == visual and video.player.stream == visual.select_video and video.poster.texture == visual.select_poster,
				"slot %d shows %s clip and poster" % [slot, id])
			check(paint.shader == SHADER and paint.get_shader_parameter("mirror") == (slot == 1)
				and paint.get_shader_parameter("inner_right") == (slot == 0), "slot %d stacked-alpha material mirrored correctly" % slot)
			var colour_end: float = paint.get_shader_parameter("colour_end")
			check(absf(colour_end - 864.0 / 1744.0) < 0.0001, "band layout from select.json for " + id)
	# Rapid cursor movement only starts the clip the cursor rests on.
	var video: Control = gui.fighter_portraits[0].video
	game.select_character(0, "tanjiro")
	game.select_character(0, "zenitsu")
	check(video.pending > 0.0 and video.player.stream == null, "switching is debounced")
	await _wait(SelectVideo.DEBOUNCE + 0.05)
	check(video.player.stream == game.catalog.characters.zenitsu.select_video, "resting cursor starts its clip")

func _test_fallback_and_playback() -> void:
	var originals: Dictionary = game.catalog.characters.duplicate()
	var plain: Resource = originals.tanjiro.duplicate()
	plain.character_id = "test_plain"
	plain.display_name = "Plain"
	game.catalog.characters["test_plain"] = plain
	await _setup("local", ["test_plain", "zenitsu"])
	var showcase: Control = game.gui.fighter_portraits[0]
	check(plain.select_video == null and not showcase.shows_clip() and showcase.video.visual == null and plain.portrait != null,
		"characters without a clip fall back to the portrait")
	game.characters.assign(["tanjiro", "zenitsu"])
	game.catalog.characters = originals
	# Real decoding once: headless playback is opt-in.
	SelectVideo.headless_playback = true
	await _setup("local", ["zenitsu", "akaza"])
	await _wait(0.6)
	var video: Control = game.gui.fighter_portraits[0].video
	check(video.is_playing() and video.player.stream_position > 0.1 and not video.poster.visible, "clip plays and replaces its poster")
	check(video.player.loop and video.player.volume == 0.0, "clip loops silently")
	game.select_character(0, "nezuko")
	check(video.outgoing.visible and video.outgoing.texture != null, "previous clip fades out underneath")
	game.show_title()
	await process_frame
	SelectVideo.headless_playback = false
	check(game.screen == "title", "leaving select frees the players")
