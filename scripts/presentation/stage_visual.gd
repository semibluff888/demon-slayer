class_name StageVisual
extends Resource
@export var display_name: String = "藤袭之庭"
@export var subtitle: String = "月夜 · 紫藤庭院"
@export var layers: Array[Texture2D] = []
@export var parallax_factors: PackedFloat32Array = PackedFloat32Array([1.0])
@export var render_size: Vector2 = Vector2(3168,792)
@export var floor_screen_y: float = 594.0
var canvas_size: Vector2 = Vector2(4608,1152)
var tile_origins: Array[Vector2] = []
var art_ready: bool = false

func load_local_assets() -> void:
	layers.clear()
	tile_origins.clear()
	parallax_factors.clear()
	var manifest_path := "res://art/stages/wisteria/stage.json"
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else {}
	var dimensions: Array = info.get("size",[4608,1152])
	canvas_size = Vector2(dimensions[0],dimensions[1])
	for tile: Dictionary in info.get("tiles",[]):
		var path: String = "res://art/stages/wisteria/" + str(tile.texture)
		tile_origins.append(Vector2(tile.rect[0],tile.rect[1]))
		parallax_factors.append(1.0)
		if not ResourceLoader.exists(path):
			layers.append(null)
			continue
		var texture := AtlasTexture.new()
		texture.atlas = load(path)
		var region: Array = tile.region
		texture.region = Rect2(region[0],region[1],region[2],region[3])
		texture.filter_clip = true
		layers.append(texture)
	if layers.is_empty():
		var path := "res://art/stages/wisteria/panorama.png"
		layers.append(load(path) if ResourceLoader.exists(path) else null)
		tile_origins.append(Vector2.ZERO)
		parallax_factors.append(1.0)
	art_ready = not layers.has(null) and tile_origins.size()==layers.size()
