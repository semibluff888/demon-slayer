extends Node
## Reproducible PCM cues shared by live playback and the engine capture mixer.
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var cursor := 0
var muted := false
var paused := false
const SAMPLE_RATE := 22050
const KINDS := ["hit", "body_hit", "block", "swing", "body_swing", "select", "fight", "round_end", "throw", "clash", "water_slash", "water_wheel", "iai", "thunder", "super", "max", "roll", "meter_empty", "meter_spend", "throw_tech", "flame"]

func _ready() -> void:
	for n in range(10):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	for kind: String in KINDS:
		streams[kind] = _make_sound(kind)

func cues(events: Array, combat: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tech := events.any(func(event: Dictionary) -> bool: return event.type == "throw_tech")
	for event: Dictionary in events:
		var kind: String = event.type
		var gain := 1.0
		var move: Resource = combat.moves.get(event.get("move", ""))
		match kind:
			"ready":
				kind = "select"
				gain = 0.55
			"ko_announce":
				kind = "round_end"
			"round_end":
				if event.get("knockout", false):
					continue
			"swing":
				kind = "body_swing"
				gain = 0.20 # A quiet cloth cue acknowledges input during startup.
			"strike":
				kind = move.presentation.sound_key if move != null and move.presentation != null else "swing"
				gain = 0.46 if int(event.get("segment",0)) > 0 else 0.70
			"hit", "block":
				if kind == "hit" and move != null and move.effect() == "body":
					kind = "body_hit"
				if move != null:
					var segment: int = event.get("segment",0)
					gain = 0.52 if segment > 0 and segment < move.hit_count()-1 else (0.78 if move.kind=="light" else 1.0)
			"super":
				kind = "max" if move != null and move.kind == "max" else "super"
				gain = 0.80
			"meter":
				if int(event.amount) >= 0:
					continue
				kind = "meter_spend"
				gain = 0.50
			"clash":
				if tech:
					continue
			_:
				pass
		if streams.has(kind):
			result.append({"kind":kind,"gain":gain})
	return result

func consume(events: Array, combat: RefCounted) -> void:
	if events.any(func(event: Dictionary) -> bool: return event.type == "round_end" and not event.get("knockout", false)):
		reset_audio()
	for cue in cues(events,combat):
		play(cue.kind,cue.gain)

func play(kind: String, gain: float = 1.0) -> void:
	if muted or paused or not streams.has(kind) or voices.is_empty():
		return
	var voice := voices[cursor % voices.size()]
	cursor += 1
	voice.stream = streams[kind]
	voice.volume_db = -17.0 + linear_to_db(maxf(gain,0.01))
	voice.stream_paused = false
	voice.play()

func set_paused(value: bool) -> void:
	paused = value
	for voice in voices:
		voice.stream_paused = value

func reset_audio() -> void:
	for voice in voices:
		voice.stop()
		voice.stream_paused = false
	paused = false
	cursor = 0

func toggle() -> void:
	muted = not muted
	if muted:
		for voice in voices:
			voice.stop()

func _make_sound(kind: String) -> AudioStreamWAV:
	var duration := 0.105
	if kind in ["water_slash","water_wheel","super","max"]: duration = 0.28
	if kind in ["fight","round_end","throw","throw_tech","meter_empty","meter_spend"]: duration = 0.20
	if kind in ["thunder","flame"]: duration = 0.16
	var frames := int(SAMPLE_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames*2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 84
	for i in range(frames):
		var t := float(i)/SAMPLE_RATE
		var progress := float(i)/frames
		var envelope := pow(1-progress,2.0)*minf(t*500,1.0)
		var value: float
		match kind:
			"swing": value = noise.randf_range(-0.30,0.30)*sin(progress*PI)+sin(TAU*(1500*t-2200*t*t))*0.12
			"body_swing", "roll": value = noise.randf_range(-0.25,0.25)*sin(progress*PI)
			"body_hit": value = sin(TAU*(95*t-120*t*t))*0.7+noise.randf_range(-0.16,0.16)*exp(-t*35)
			"hit": value = sin(TAU*(145*t-210*t*t))*0.60+noise.randf_range(-0.24,0.24)
			"throw": value = sin(TAU*(75*t-70*t*t))*0.8+noise.randf_range(-0.15,0.15)*exp(-t*30)
			"water_slash", "water_wheel": value = noise.randf_range(-0.3,0.3)*sin(progress*PI)+sin(TAU*(370*t-230*t*t))*0.16
			"iai": value = sin(TAU*(2400*t-6200*t*t))*0.22+noise.randf_range(-0.10,0.10)
			"thunder": value = noise.randf_range(-0.42,0.42)*pow(1-progress,2)+sin(TAU*62*t)*0.3
			"super": value = (sin(TAU*(360*t+1200*t*t))+sin(TAU*720*t))*0.25
			"max": value = sin(TAU*(180*t+1800*t*t))*0.32+sin(TAU*360*t)*0.20
			"flame": value = noise.randf_range(-0.35,0.35)+sin(TAU*95*t)*0.28
			"meter_empty": value = sin(TAU*(160 if progress<0.45 else 125)*t)*0.25*(1 if progress<0.38 or progress>0.52 else 0)
			"meter_spend": value = sin(TAU*(1200*t-2000*t*t))*0.22
			"throw_tech": value = sin(TAU*(820*t+2100*t*t))*0.30+sin(TAU*1370*t)*0.20
			"block", "clash": value = sin(TAU*1200*t)*0.28+sin(TAU*1760*t)*0.16
			"select": value = sin(TAU*660*t)*0.35
			_: value = (sin(TAU*440*t)+sin(TAU*660*t))*0.25
		bytes.encode_s16(i*2,int(clampf(value*envelope,-1,1)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	return stream
