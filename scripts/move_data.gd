class_name DuelMove
extends Resource
## All durations are simulation ticks at 60 Hz. Boxes are relative to the feet,
## facing right; the model mirrors them when the fighter faces left.

@export var id: String = ""
@export var display_name: String = ""
@export_enum("light", "heavy", "skill", "throw") var kind: String = "light"
@export_enum("mid", "low", "high", "throw") var level: String = "mid"
@export var startup: int = 5
@export var active: int = 3
@export var recovery: int = 12
@export var damage: int = 45
@export var hitstun: int = 18
@export var blockstun: int = 10
@export var hitstop: int = 4
@export var push: float = 3.0
@export var travel: float = 0.0
@export var lift: float = 0.0
@export var box: Rect2 = Rect2(10, -48, 44, 24)
@export var cancel_window: int = 9
@export var knockdown: bool = false

func total_frames() -> int:
	return startup + active + recovery

func rank() -> int:
	return {"light": 1, "heavy": 2, "skill": 3, "throw": 4}[kind]
