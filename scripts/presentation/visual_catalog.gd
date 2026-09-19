extends RefCounted
const Character = preload("res://scripts/presentation/character_visual.gd")
const Stage = preload("res://scripts/presentation/stage_visual.gd")
var characters: Dictionary = {}
var stage := Stage.new()
var body_font: Font
var title_font: Font

func _init() -> void:
	body_font = _font("res://art/fonts/NotoSansSC-ui.ttf", "Microsoft YaHei UI", 450)
	title_font = _font("res://art/fonts/NotoSerifSC-title.ttf", "KaiTi", 700)
	var water := Character.new()
	water.load_local_assets()
	characters["tanjiro"] = water
	var thunder := Character.new()
	thunder.character_id = "zenitsu"
	thunder.display_name = "我妻善逸"
	thunder.epithet = "雷鸣一瞬，意志不息"
	thunder.element_name = "雷之呼吸"
	thunder.accent = Color("f0c578")
	thunder.load_local_assets()
	characters["zenitsu"] = thunder
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
