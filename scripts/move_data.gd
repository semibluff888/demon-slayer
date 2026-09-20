class_name DuelMove
extends Resource
## Frame data is shared, immutable at runtime. Instances live in Fighter/Combat.
@export var id: String = ""
@export var display_name: String = ""
@export_enum("light", "heavy", "skill", "super", "max", "throw") var kind: String = "light"
@export_enum("mid", "low", "high", "throw") var level: String = "mid"
@export var startup: int = 5
@export var active: int = 3
@export var recovery: int = 12
@export var damage: int = 45
@export var hitstun: int = 22
@export var blockstun: int = 10
@export var hitstop: int = 4
@export var push: float = 1.5
@export var travel: float = 0.0
@export var startup_travel: float = 0.0
@export var lift: float = 0.0
@export var box: Rect2 = Rect2(10, -48, 44, 24)
@export var cancel_window: int = 18
@export var knockdown: bool = false
@export var stance: String = "stand"
@export var animation_id: String = ""
@export var effect_id: String = ""
@export var presentation: Resource
@export var cancel_targets: PackedStringArray = []
@export var meter_cost: int = 0
@export var freeze_frames: int = 0
@export var anti_air_until: int = 0
@export var hit_frames: PackedInt32Array = []
@export var projectile_speed: float = 0.0
@export var projectile_lifetime: int = 0
@export var projectile_box: Rect2 = Rect2(-12, -18, 24, 36)

func total_frames() -> int:
	return startup + active + recovery

func clip_id() -> String:
	return animation_id if not animation_id.is_empty() else id

func effect() -> String:
	return effect_id if not effect_id.is_empty() else clip_id()

func segment(frame: int) -> int:
	if frame < startup or frame >= startup + active:
		return -1
	if hit_frames.is_empty():
		return 0
	for n in range(hit_frames.size() - 1, -1, -1):
		if frame >= hit_frames[n]:
			return n
	return -1

func segment_start(index: int) -> int:
	return hit_frames[index] if not hit_frames.is_empty() else startup

func segment_end(index: int) -> int:
	return hit_frames[index + 1] if index + 1 < hit_frames.size() else startup + active

func segment_progress(frame: int) -> float:
	var index := segment(frame)
	if index < 0:
		return 0.0
	return float(frame - segment_start(index)) / maxi(1, segment_end(index) - segment_start(index) - 1)

func hit_count() -> int:
	return maxi(1, hit_frames.size())

func segment_damage(index: int) -> int:
	return int(damage / hit_count()) + (damage % hit_count() if index == hit_count() - 1 else 0)

func is_super() -> bool:
	return kind in ["super", "max"]
