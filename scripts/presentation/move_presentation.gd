class_name MovePresentation
extends Resource
## Immutable presentation only. Combat never uses these values for rules.
@export var shape: String = "blade"
@export var color: Color = Color("c8e6ff")
@export var sound_key: String = "swing"
@export var trail_count: int = 0
@export var trail_alpha: float = 0.12

@export var texture_key: String = ""
@export var body_opacity: float = 0.86
@export var glow_strength: float = 0.55
@export var particle_scale: float = 1.0
@export var super_tier: int = 0
