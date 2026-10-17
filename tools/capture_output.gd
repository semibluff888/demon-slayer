extends RefCounted
## Review-only capture storage. The game never loads this helper.
## Default: encode bounded PNG batches into capture.mp4 and recycle the frames.
## --keep-frames retains lossless PNGs, with a per-sequence 512 MiB default limit.
const BATCH_BYTES := 128 * 1024 * 1024
const BATCH_FRAMES := 120
static var maintained := false
var folder := ""
var python := ""
var keep_frames := false
var raw_limit := 512 * 1024 * 1024
var raw_bytes := 0
var batch_frames := 0
var total_frames := 0
var failed := false

func begin(destination: String, fps: float = 60.0) -> bool:
	folder = destination
	keep_frames = "--keep-frames" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--max-raw-mib="):
			var limit := argument.trim_prefix("--max-raw-mib=").to_int()
			if limit < 1 or limit > 2048:
				return _fail("--max-raw-mib must be 1..2048")
			raw_limit = limit * 1024 * 1024
	python = ProjectSettings.globalize_path("res://.venv/Scripts/python.exe")
	if not FileAccess.file_exists(python):
		python = "python"
	var arguments := PackedStringArray(["--pid", str(OS.get_process_id()), "--fps", str(fps)])
	if keep_frames:
		arguments.append("--keep-frames")
	if not maintained:
		arguments.append("--maintain")
	if not _call("prepare", arguments):
		return false
	maintained = true
	return true

func save(image: Image, filename: String) -> bool:
	if failed:
		return false
	if total_frames >= 18000:
		return _fail("Capture limit reached (18000 frames); split the sequence")
	var data := image.save_png_to_buffer()
	if keep_frames and raw_bytes + data.size() > raw_limit:
		return _fail("PNG budget reached; split the capture or use the default video output")
	var file := FileAccess.open(folder.path_join(filename), FileAccess.WRITE)
	if file == null:
		return _fail("Cannot write capture frame")
	file.store_buffer(data)
	var error := file.get_error()
	file.close()
	if error != OK:
		return _fail("Cannot save capture frame: %s" % error_string(error))
	raw_bytes += data.size()
	batch_frames += 1
	total_frames += 1
	if not keep_frames and (raw_bytes >= BATCH_BYTES or batch_frames >= BATCH_FRAMES):
		if not _call("encode"):
			return false
		raw_bytes = 0
		batch_frames = 0
	return true

func finish() -> bool:
	return not failed and _call("finish")

func _call(command: String, extra: PackedStringArray = PackedStringArray()) -> bool:
	var output: Array = []
	var arguments := PackedStringArray([ProjectSettings.globalize_path("res://tools/capture_output.py"), command,
		ProjectSettings.globalize_path(folder)])
	arguments.append_array(extra)
	var code := OS.execute(python, arguments, output, true)
	for line in output:
		if not str(line).strip_edges().is_empty():
			print(str(line).strip_edges())
	if code != 0:
		return _fail("Capture storage failed (%s); existing frames/chunks were retained" % code)
	return true

func _fail(message: String) -> bool:
	failed = true
	printerr("CAPTURE ERROR: ", message)
	Engine.get_main_loop().quit(1)
	return false
