class_name StageVisual
extends Resource

@export var display_name: String = "藤袭之庭"
@export var subtitle: String = "月夜 · 紫藤庭院"
@export var layers: Array[Texture2D] = []
@export var parallax_factors: PackedFloat32Array = PackedFloat32Array([0.05, 0.16, 0.3, 0.6, 1.0])
@export var floor_screen_y: float = 594.0
var art_ready: bool = false

func load_local_assets() -> void:
	layers.clear()
	for filename in ["sky", "temple", "wisteria", "floor", "foreground"]:
		var path := "res://art/stages/wisteria/%s.png" % filename
		layers.append(load(path) if ResourceLoader.exists(path) else null)
	art_ready = not layers.has(null)
