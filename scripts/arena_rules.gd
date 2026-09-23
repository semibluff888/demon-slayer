class_name ArenaRules
extends RefCounted
## Shared stage geometry; simulation never depends on a render camera.
const WIDTH: float = 960.0
const CENTER: float = WIDTH * 0.5
const VIEW_WIDTH: float = 1280.0
const ZOOM: float = 3.0
const BODY_MARGIN: float = 28.0
const LEFT: float = BODY_MARGIN
const RIGHT: float = WIDTH - BODY_MARGIN
const HALF_VIEW: float = VIEW_WIDTH / ZOOM * 0.5
const MAX_SEPARATION: float = VIEW_WIDTH / ZOOM - BODY_MARGIN * 2.0
const FLOOR_Y: float = 286.0
const FLOOR_SCREEN_Y: float = 594.0
const DASH_WINDOW: int = 12
const DASH_FORWARD_TICKS: int = 16
const DASH_BACK_TICKS: int = 14
const DASH_JUMP_MULTIPLIER: float = 1.5
const DASH_FORWARD_SPEED: float = 4.6
const DASH_BACK_SPEED: float = 4.0
const THROW_TICKS: int = 30
const THROW_IMPACT_TICK: int = 20
const THROW_DISTANCE: float = 56.0
