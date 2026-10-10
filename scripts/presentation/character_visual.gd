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
@export var battle_portrait: Texture2D
@export var portrait_faces_right: bool = false
@export_range(0, 1) var menu_focus_x: float = 0.5
@export var portrait_focus: Vector2 = Vector2(0.5, 0.25)
@export var frames: SpriteFrames
@export var feet_anchor: Vector2 = Vector2(384, 704)
@export var source_height: float = 600.0
@export var canonical_height: float = 70.0
var model_scale: float = 1.0
var awakening: Resource
var awakening_frames: SpriteFrames
var awakened_portrait: Texture2D
var hit_reaction_frames: PackedInt32Array = []
@export var phases: Dictionary = {}
var clip_metadata: Dictionary = {}
var state_animations: Dictionary = {}
var asset_directory: String = ""
var required_move_clips: Array[String] = []
var art_ready: bool = false

const REQUIRED_CLIPS: Array[String] = ["idle", "walk", "walk_back", "crouch", "jump",
	"guard", "guard_low", "hit", "knockdown", "throw", "victory", "stand_light", "stand_heavy",
	"crouch_light", "crouch_heavy", "air_light", "air_heavy",
	"dash_forward", "dash_back", "jump_forward", "jump_back", "throw_success", "thrown"]

func load_local_assets(load_frames: bool = true) -> void:
	var directory := asset_directory if not asset_directory.is_empty() else "res://art/characters/%s/" % character_id
	if ResourceLoader.exists(directory + "portrait.png"):
		portrait = load(directory + "portrait.png")
	if ResourceLoader.exists(directory + "avatar.png"):
		avatar = load(directory + "avatar.png")
	if ResourceLoader.exists(directory + "battle-portrait.png"):
		battle_portrait = load(directory + "battle-portrait.png")
	if ResourceLoader.exists(directory + "awakened-portrait.png"):
		awakened_portrait = load(directory + "awakened-portrait.png")
	if ResourceLoader.exists(directory + "awakening/portrait.png"):
		awakened_portrait = load(directory + "awakening/portrait.png")
	if not load_frames:
		return
	var manifest_path := directory + "atlas.json"
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		return
	frames = SpriteFrames.new()
	frames.remove_animation("default")
	clip_metadata.clear()
	_load_atlas(directory, parsed)
	var round_path := directory + "round-atlas.json"
	if FileAccess.file_exists(round_path):
		var selected: Variant = JSON.parse_string(FileAccess.get_file_as_string(round_path))
		if selected is Dictionary:
			_load_atlas(directory, selected)
	_load_awakening_assets()
	art_ready = missing_clips().is_empty() and portrait != null

func _load_atlas(directory: String, parsed: Dictionary) -> void:
	feet_anchor = Vector2(parsed.get("feet_anchor", [384, 704])[0], parsed.get("feet_anchor", [384, 704])[1])
	source_height = float(parsed.get("source_height", 600))
	canonical_height = float(parsed.get("canonical_height", 70))
	for clip: String in parsed.get("clips", {}):
		var info: Dictionary = parsed.clips[clip]
		clip_metadata[clip] = info
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

func drawing_scale() -> float:
	return canonical_height / source_height * model_scale

func missing_clips() -> Array[String]:
	var required := REQUIRED_CLIPS.duplicate()
	required.append_array(required_move_clips)
	var missing: Array[String] = []
	for clip: String in required:
		if frames == null or not frames.has_animation(clip) or frames.get_frame_count(clip) == 0:
			missing.append(clip)
	if awakening != null:
		var alternate := required.duplicate()
		alternate.append(awakening.start_clip)
		for clip: String in alternate:
			if awakening_frames == null or not awakening_frames.has_animation(clip) or awakening_frames.get_frame_count(clip) == 0:
				missing.append("awakening/" + clip)
	return missing

func release_combat_assets() -> void:
	frames = null
	awakening_frames = null
	phases.clear()
	clip_metadata.clear()
	art_ready = false

func _load_awakening_assets() -> void:
	awakening_frames = null
	if awakening == null or not FileAccess.file_exists(awakening.form_atlas):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(awakening.form_atlas))
	if not parsed is Dictionary:
		return
	awakening_frames = SpriteFrames.new()
	awakening_frames.remove_animation("default")
	var directory: String = str(awakening.form_atlas).get_base_dir() + "/"
	for clip: String in parsed.get("clips", {}):
		var info: Dictionary = parsed.clips[clip]
		awakening_frames.add_animation(clip)
		awakening_frames.set_animation_loop(clip, info.get("loop", false))
		awakening_frames.set_animation_speed(clip, float(info.get("fps", 12)))
		for entry: Dictionary in info.frames:
			var packed := AtlasTexture.new()
			if not ResourceLoader.exists(directory + entry.texture):
				push_error("Missing awakening texture: " + directory + entry.texture)
				continue
			packed.atlas = load(directory + entry.texture)
			var region: Array = entry.region
			packed.region = Rect2(region[0], region[1], region[2], region[3])
			var canvas: Array = parsed.canvas_size
			packed.margin = Rect2(entry.offset[0], entry.offset[1], canvas[0] - region[2], canvas[1] - region[3])
			packed.filter_clip = true
			awakening_frames.add_frame(clip, packed)
	# Some form atlases still contain normal-form victory placeholders. Reuse
	# the configured form pose while keeping the authored victory timeline.
	var source: String = awakening.victory_source_clip
	if not source.is_empty() and awakening_frames.has_animation(source) and awakening_frames.has_animation("round_victory"):
		var count := awakening_frames.get_frame_count("round_victory")
		var source_count := awakening_frames.get_frame_count(source)
		for i in range(count):
			var index := mini(source_count - 1, int(float(i) * source_count / count))
			awakening_frames.set_frame("round_victory", i, awakening_frames.get_frame_texture(source, index))
