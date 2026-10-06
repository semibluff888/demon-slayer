class_name CharacterDefinition
extends Resource
@export var id: String = ""
@export var roster_order: int = 100
@export var portrait_faces_right: bool = false
@export_range(0, 1) var menu_focus_x: float = 0.5
@export var display_name: String = ""
@export var epithet: String = ""
@export var element_name: String = ""
@export var role: String = ""
@export var accent: Color = Color.WHITE
@export var walk_speed: float = 2.15
@export var visual_directory: String = ""
# Whole-model size and authored pain poses; independent of combat geometry.
@export_range(0.5, 1.5) var model_scale: float = 1.0
@export var hit_reaction_frames: PackedInt32Array = []
@export var normals: Dictionary = {}
@export var motions: Dictionary = {}
# Dedicated state clips are enabled by authored character resources after art validation.
@export var state_animations: Dictionary = {}
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
