extends RefCounted
const Character = preload("res://scripts/presentation/character_visual.gd")
const Stage = preload("res://scripts/presentation/stage_visual.gd")
const CombatData = preload("res://scripts/combat_catalog.gd")
var data := CombatData.new()
var characters: Dictionary = {}
var stage := Stage.new()
var body_font: Font
var title_font: Font

func _init() -> void:
	body_font = _font("res://art/fonts/NotoSansSC-ui.ttf", "Microsoft YaHei UI", 450)
	title_font = _font("res://art/fonts/NotoSerifSC-title.ttf", "KaiTi", 700)
	for id in data.characters:
		var definition = data.characters[id]
		var visual := Character.new()
		visual.character_id = id
		visual.display_name = definition.display_name
		visual.epithet = definition.epithet
		visual.element_name = definition.element_name
		visual.accent = definition.accent
		visual.asset_directory = definition.visual_directory
		for move in definition.all_moves():
			if not move.clip_id() in visual.required_move_clips:
				visual.required_move_clips.append(move.clip_id())
		visual.load_local_assets()
		characters[id] = visual
	stage.load_local_assets()

func _font(path: String, fallback: String, weight: int) -> Font:
	if ResourceLoader.exists(path):
		var font := FontVariation.new()
		font.base_font = load(path)
		font.variation_opentype = {"wght": weight}
		return font
	var system := SystemFont.new()
	system.font_names = PackedStringArray([fallback, "Microsoft YaHei", "sans-serif"])
	system.font_weight = weight
	return system

func readiness() -> Dictionary:
	var report := {"stage": stage.art_ready, "characters": {}}
	for id: String in characters:
		report.characters[id] = {"ready": characters[id].art_ready,
			"missing_clips": characters[id].missing_clips(), "portrait": characters[id].portrait != null}
	return report
