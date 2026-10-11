extends RefCounted
## Hilt and tip of the drawn katana on each atlas drawing, measured offline by
## tools/build_blade_tracks.py in shared canvas pixels. Pure data; combat never
## reads it.

static var _cache: Dictionary = {}

static func clips(directory: String) -> Dictionary:
	if not _cache.has(directory):
		var data: Dictionary = {}
		var path := directory.path_join("blade-tracks.json")
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				data = parsed.get("clips", {})
		_cache[directory] = data
	return _cache[directory]

## [hilt, tip] in canvas pixels, or an empty array when no blade is held.
static func pose(directory: String, clip: String, index: int) -> PackedVector2Array:
	var frames: Array = clips(directory).get(clip, [])
	if index < 0 or index >= frames.size() or not frames[index] is Dictionary:
		return PackedVector2Array()
	var entry: Dictionary = frames[index]
	return PackedVector2Array([Vector2(entry.hilt[0], entry.hilt[1]), Vector2(entry.tip[0], entry.tip[1])])
