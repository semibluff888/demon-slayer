extends SceneTree
## Records the character select screen with real Theora decoding for review, and checks
## the composited clips. Run with a window and a fixed clock:
##   godot --path . --fixed-fps 60 --script res://tools/capture_select_screen.gd -- [--hd] [--keep-frames]
## Output: artifacts/select-screen[-1080]/capture.mp4 plus stills; prints
## "SELECT SCREEN CAPTURE: N checks, M failed".
const Main = preload("res://scenes/main.tscn")
const CaptureOutput = preload("res://tools/capture_output.gd")
const Selection = preload("res://scripts/ui/selection_controller.gd")
const SelectVideo = preload("res://scripts/ui/select_video.gd")
var game: Node2D
var out := "res://artifacts/select-screen"
var checks := 0
var failures: Array[String] = []
var frame := 0
var capture: CaptureOutput
var last_image: Image

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _key(key: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	game._input(event)
	event.pressed = false
	game._input(event)

## Advances `count` frames, recording each one.
func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
		last_image = root.get_texture().get_image()
		capture.save(last_image, "frame-%05d.png" % frame)
		frame += 1

func _still(id: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [out, id])

func _video(slot: int) -> Control:
	return game.gui.fighter_portraits[slot].video

## Decoded matte: clear corners and a solid figure mean the stacked layout is intact.
func _check_matte(slot: int, label: String) -> void:
	var video := _video(slot)
	check(video.is_playing(), label + ": clip playing")
	var texture: Texture2D = video.player.get_video_texture()
	if texture == null:
		check(false, label + ": no video texture")
		return
	var image := texture.get_image()
	var height := int((image.get_height() - 16) / 2.0)
	var corner := maxf(image.get_pixel(6, height + 16 + 6).g, image.get_pixel(image.get_width() - 7, height + 16 + 6).g)
	var torso := image.get_pixel(int(image.get_width() / 2.0), height + 16 + int(height * 0.52)).g
	check(corner < 0.05 and torso > 0.9, "%s: matte corner %.3f torso %.3f" % [label, corner, torso])

## No key colour may survive on screen inside the showcase rectangles.
## Mean brightness of a block on P1's torso in the last recorded frame; a dropped clip
## frame would show the dark backdrop here.
func _torso_luma() -> float:
	var scale := last_image.get_width() / 1280.0
	var area: Rect2 = game.gui.fighter_portraits[0]._video_rect()
	var center := Vector2(area.get_center().x, area.position.y + area.size.y * 0.5) * scale
	var total := 0.0
	for y in range(-8, 9, 4):
		for x in range(-8, 9, 4):
			total += last_image.get_pixel(int(center.x) + x, int(center.y) + y).get_luminance()
	return total / 25.0

func _check_magenta(label: String) -> void:
	var image := root.get_texture().get_image()
	var scale := image.get_width() / 1280.0
	var magenta := 0
	var total := 0
	for slot in range(2):
		var area: Rect2 = game.gui.fighter_portraits[slot]._video_rect()
		for y in range(int(area.position.y * scale), int(area.end.y * scale) - 1, 3):
			for x in range(int(area.position.x * scale), int(area.end.x * scale) - 1, 3):
				var c := image.get_pixel(x, y)
				total += 1
				if c.r > 0.7 and c.b > 0.7 and c.g < 0.3:
					magenta += 1
	check(float(magenta) / maxf(total, 1) < 0.0005, "%s: %d magenta pixels on screen" % [label, magenta])

func _run() -> void:
	var hd := "--hd" in OS.get_cmdline_user_args()
	if hd:
		out += "-1080"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080) if hd else Vector2i(1280, 720)
	game = Main.instantiate()
	game.settings.path = out + "/capture-settings.cfg"
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.muted = true
	# Only the scripted events below drive the menu; stray keyboard/mouse input reaching
	# the capture window must not move the cursors.
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	root.gui_disable_input = true
	await process_frame
	capture = CaptureOutput.new()
	if not capture.begin(out + "/"):
		return
	game.devices.assign(["keyboard:0", "keyboard:1"])
	game.characters.assign(["tanjiro", "zenitsu"])
	game.choose_mode("cpu")
	game.selection.rng.seed = 3
	await _frames(100)
	_still("select-cpu")
	_check_matte(0, "tanjiro P1")
	_check_matte(1, "zenitsu CPU")
	_check_magenta("cpu start")
	for id in ["zenitsu", "nezuko", "akaza", "tanjiro"]:
		_key(KEY_D)
		await _frames(80)
		check(game.characters[0] == id, "P1 cursor on " + id)
		_check_matte(0, id + " P1")
		_check_magenta(id)
	_key(KEY_W)
	await _frames(60)
	_still("select-placeholder")
	check(game.gui.fighter_portraits[0].kind == "empty", "placeholder panel")
	_key(KEY_A)
	await _frames(70)
	_still("select-random")
	check(game.selection.cell_id(0) == Selection.RANDOM, "random cell")
	_key(KEY_U)
	await _frames(20)
	_still("select-roulette")
	await _frames(80)
	_still("select-random-locked")
	check(game.selection.ready[0] and game.gui.fighter_portraits[0].shows_clip(), "random lock lands on a clip")
	var p1_stream: VideoStream = _video(0).player.stream
	_key(KEY_D)
	await _frames(40)
	_key(KEY_D)
	await _frames(60)
	check(_video(0).player.stream == p1_stream and _video(0).is_playing(), "CPU cursor leaves P1's clip running")
	_still("select-ready")
	_key(KEY_U)
	await _frames(30)
	_still("select-lockin")
	check(game.selection.lockin_time() >= 0.0 and game.gui.lockin_vs.visible, "matchup lock-in shows")
	await _frames(80)
	check(game.screen == "stage", "stage screen")
	game.gui.actions.back.pressed.emit()
	await _frames(30)
	# Hold one clip past its loop point: the wrap must not blank or jump.
	game.select_character(0, "akaza")
	var length: float = game.catalog.characters.akaza.select_layout.frames / 24.0
	await _frames(int(SelectVideo.DEBOUNCE * 60) + 2)
	var stream: VideoStream = _video(0).player.stream
	var previous := 0.0
	var wrap_at := -1
	var lumas: Array[float] = []
	for i in range(int((length + 1.0) * 60)):
		await _frames(1)
		lumas.append(_torso_luma())
		var position: float = _video(0).player.stream_position
		if wrap_at < 0 and position + 0.5 < previous and _video(0).player.stream == stream:
			wrap_at = i
			_still("select-loop-wrap")
		elif wrap_at >= 0 and i == wrap_at + 2:
			_check_matte(0, "after loop wrap")
		previous = position
	var wrapped := wrap_at >= 0
	if wrapped:
		var steady: float = lumas.slice(maxi(wrap_at - 30, 0), wrap_at - 2).min()
		var around: float = lumas.slice(wrap_at - 2, mini(wrap_at + 3, lumas.size())).min()
		check(around > steady * 0.6, "loop wrap keeps the figure on screen (%.3f vs %.3f)" % [around, steady])
	check(_video(0).player.stream == stream, "hold keeps one clip")
	check(wrapped, "clip looped")
	game.devices.assign(["keyboard:0", "keyboard:1"])
	game.characters.assign(["nezuko", "akaza"])
	game.choose_mode("local")
	await _frames(90)
	_still("select-local")
	_check_matte(0, "nezuko local")
	_check_matte(1, "akaza local")
	_check_magenta("local")
	if not capture.finish():
		return
	game.queue_free()
	await process_frame
	print("SELECT SCREEN CAPTURE: %d checks, %d failed" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
