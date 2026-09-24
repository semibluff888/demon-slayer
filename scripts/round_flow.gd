extends RefCounted
## Presentation timing in unscaled 60 Hz ticks, shared by battle and demos.
const ROUND := 54
const READY := 42
const GO := 24
const INTRO := ROUND + READY
const FREEZE := 9
const SLOW := 30
const SETTLE := 51
const RESULT_AT := FREEZE + SLOW + SETTLE
const RESULT := 120
const OUTRO := RESULT_AT + RESULT
const ACTOR_INTRO := 120
const OPENING := ACTOR_INTRO + INTRO
# Fixed presentation-only recoil; gameplay hitstun and damage are unchanged.
const KO_FLIGHT := 28.0
const KO_DISTANCE := 112.0
const KO_SLIDE := 10.0
const KO_EDGE_MARGIN := 24.0
const KO_SETTLE_DRAWING := 4.0

static func motion_ticks(elapsed: int, knockout: bool) -> float:
	if not knockout:
		return float(elapsed)
	return clampf(elapsed - FREEZE, 0, SLOW) * 0.25 + maxf(0, elapsed - FREEZE - SLOW)

static func speed(elapsed: int, knockout: bool) -> float:
	if not knockout:
		return 1.0
	return 0.0 if elapsed < FREEZE else (0.25 if elapsed < FREEZE + SLOW else 1.0)
