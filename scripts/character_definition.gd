class_name CharacterDefinition
extends Resource
@export var id: String = ""
@export var display_name: String = ""
@export var epithet: String = ""
@export var element_name: String = ""
@export var role: String = ""
@export var accent: Color = Color.WHITE
@export var walk_speed: float = 2.15
@export var visual_directory: String = ""
@export var normals: Dictionary = {}
@export var motions: Dictionary = {}
@export var throw_move: Resource
@export var move_list: Array[Dictionary] = []
@export var combos: PackedStringArray = ["2B → 2A → 5C → 236A", "j.C → 5A → 5C → 214B",
	"5A → 5C → 236A → 236236A", "5C → 214D → 236236AC"]

func all_moves() -> Array:
	var result: Array = []
	for move in normals.values() + motions.values() + [throw_move]:
		if move != null and not move in result:
			result.append(move)
	return result
