extends RefCounted
## Master feeds three buses: Music (BGM, with a pause low-pass), SFX (combat and UI cues,
## cinematic soundtracks) and Voice (reserved for character voices). A hard limiter on
## Master keeps stacked hits over loud music from clipping. Built in code because the
## release only stages fixed folders, so a root default_bus_layout.tres would not ship.
const MUSIC := &"Music"
const SFX := &"SFX"
const VOICE := &"Voice"
const OPEN_CUTOFF := 20000.0
const CEILING_DB := -0.5

static func ensure() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = CEILING_DB
		AudioServer.add_bus_effect(0, limiter)
	for bus: StringName in [MUSIC, SFX, VOICE]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")
	var music := AudioServer.get_bus_index(MUSIC)
	if AudioServer.get_bus_effect_count(music) == 0:
		var filter := AudioEffectLowPassFilter.new()
		filter.cutoff_hz = OPEN_CUTOFF
		AudioServer.add_bus_effect(music, filter)
		AudioServer.set_bus_effect_enabled(music, 0, false)

## Master carries the main volume and the mute (F2), so music, cues and cinematics follow it.
static func apply(settings: RefCounted) -> void:
	ensure()
	AudioServer.set_bus_mute(0, settings.muted)
	AudioServer.set_bus_volume_db(0, level_db(settings.volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC), level_db(settings.music_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX), level_db(settings.sfx_volume))

static func level_db(level: float) -> float:
	return linear_to_db(maxf(level, 0.00001))

## 0 leaves the music open; 1 closes the low-pass to `cutoff` (log-spaced in between).
static func set_lowpass(amount: float, cutoff: float) -> void:
	var music := AudioServer.get_bus_index(MUSIC)
	if music < 0 or AudioServer.get_bus_effect_count(music) == 0:
		return
	var filter := AudioServer.get_bus_effect(music, 0) as AudioEffectLowPassFilter
	filter.cutoff_hz = exp(lerpf(log(OPEN_CUTOFF), log(cutoff), clampf(amount, 0, 1)))
	AudioServer.set_bus_effect_enabled(music, 0, amount > 0.001)
