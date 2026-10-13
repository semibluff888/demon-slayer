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
@export var awakening: Resource
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
# Optional move-set expansion. Empty tables keep the original lookup exactly.
# command_normals: "6B", "3C"… (direction relative to facing + button).
# air_motions: "j236A", "j214D"… chosen only while airborne.
@export var command_normals: Dictionary = {}
@export var air_motions: Dictionary = {}
# Help rows for the advanced page, same shape as move_list.
@export var advanced_list: Array[Dictionary] = []

## Every reachable move: base tables first (original order), then follow-up stages.
func all_moves() -> Array:
	var result: Array = []
	var queue: Array = normals.values() + motions.values() + [throw_move] + command_normals.values() + air_motions.values()
	while not queue.is_empty():
		var move = queue.pop_front()
		if move == null or move in result:
			continue
		result.append(move)
		queue.append_array(move.follow_ups.values())
	return result
