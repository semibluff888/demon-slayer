class_name CharacterVisual
extends Resource
## Display-only resource. Images share a feet anchor and canonical model height.
@export var character_id: String = "tanjiro"
@export var display_name: String = "灶门炭治郎"
@export var epithet: String = "心怀温柔，挥刀向前"
@export var element_name: String = "水之呼吸"
@export var accent: Color = Color("65cbd4")
@export var portrait: Texture2D
@export var avatar: Texture2D
@export var portrait_focus: Vector2 = Vector2(0.5, 0.25)
@export var frames: SpriteFrames
@export var feet_anchor: Vector2 = Vector2(384, 704)
@export var source_height: float = 600.0
@export var canonical_height: float = 70.0
@export var phases: Dictionary = {}
var art_ready: bool = false

const REQUIRED_CLIPS: Array[String] = ["idle", "walk", "walk_back", "crouch", "jump",
	"guard", "guard_low", "hit", "knockdown", "throw", "victory", "stand_light", "stand_heavy",
	"crouch_light", "crouch_heavy", "air_light", "air_heavy"]

func load_local_assets() -> void:
	var directory := "res://art/characters/%s/" % character_id
	if ResourceLoader.exists(directory + "portrait.png"):
		portrait = load(directory + "portrait.png")
	if ResourceLoader.exists(directory + "avatar.png"):
		avatar = load(directory + "avatar.png")
	var manifest_path := directory + "atlas.json"
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		return
	feet_anchor = Vector2(parsed.get("feet_anchor", [384, 704])[0], parsed.get("feet_anchor", [384, 704])[1])
	source_height = float(parsed.get("source_height", 600))
	canonical_height = float(parsed.get("canonical_height", 70))
	frames = SpriteFrames.new()
	frames.remove_animation("default")
	for clip: String in parsed.get("clips", {}):
		var info: Dictionary = parsed.clips[clip]
		frames.add_animation(clip)
		frames.set_animation_loop(clip, info.get("loop", false))
		frames.set_animation_speed(clip, float(info.get("fps", 12)))
		for entry: Variant in info.get("frames", []):
			if entry is String and ResourceLoader.exists(directory + entry):
				frames.add_frame(clip, load(directory + entry))
			elif entry is Dictionary and ResourceLoader.exists(directory + str(entry.get("texture", ""))):
				var packed := AtlasTexture.new()
				packed.atlas = load(directory + entry.texture)
				var region: Array = entry.region
				packed.region = Rect2(region[0], region[1], region[2], region[3])
				var canvas: Array = parsed.get("canvas_size", [768, 768])
				packed.margin = Rect2(entry.offset[0], entry.offset[1], canvas[0] - region[2], canvas[1] - region[3])
				packed.filter_clip = true
				frames.add_frame(clip, packed)
		phases[clip] = info.get("phase_breaks", [2, 4])
	art_ready = missing_clips().is_empty() and portrait != null

func missing_clips() -> Array[String]:
	var required := REQUIRED_CLIPS.duplicate()
	required.append_array(["water_slash", "water_wheel"] if character_id == "tanjiro" else ["iai", "thunder"])
	var missing: Array[String] = []
	for clip: String in required:
		if frames == null or not frames.has_animation(clip) or frames.get_frame_count(clip) == 0:
			missing.append(clip)
	return missing
