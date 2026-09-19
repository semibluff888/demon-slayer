extends Node
## Small synthesized PCM sounds; no external audio assets are required.
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var cursor: int = 0
var muted: bool = false

func _ready() -> void:
	for i in range(8):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -15.0
		add_child(voice)
		voices.append(voice)
	for kind in ["hit", "block", "swing", "select", "fight", "round_end", "throw", "clash", "water_slash", "water_wheel", "iai", "thunder"]:
		streams[kind] = _make_sound(kind)

func play(kind: String) -> void:
	if muted or not streams.has(kind) or voices.is_empty():
		return
	var voice := voices[cursor % voices.size()]
	cursor += 1
	voice.stream = streams[kind]
	voice.play()

func toggle() -> void:
	muted = not muted
	if muted:
		for voice in voices:
			voice.stop()

func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var duration := 0.32 if kind in ["water_slash", "water_wheel", "thunder"] else (0.22 if kind in ["fight", "round_end", "throw"] else 0.105)
	var frames := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 84
	for i in range(frames):
		var t := float(i) / rate
		var progress := float(i) / frames
		var envelope := pow(1.0 - progress, 2.0) * minf(t * 500.0, 1.0)
		var value: float
		match kind:
			"swing": value = noise.randf_range(-1.0, 1.0) * 0.22 * sin(progress * PI)
			"hit": value = sin(TAU * (140.0 * t - 250.0 * t * t)) * 0.65 + noise.randf_range(-0.3, 0.3)
			"throw": value = sin(TAU * (85.0 * t - 95.0 * t * t)) * 0.75 + noise.randf_range(-0.2, 0.2) * exp(-t * 30)
			"water_slash", "water_wheel": value = noise.randf_range(-0.25, 0.25) * sin(progress * PI) + sin(TAU * (370 * t - 230 * t * t)) * 0.18
			"iai": value = sin(TAU * (2600 * t - 7000 * t * t)) * 0.25 + noise.randf_range(-0.12, 0.12)
			"thunder": value = noise.randf_range(-0.5, 0.5) * pow(1 - progress, 2) + sin(TAU * 62 * t) * 0.35
			"block", "clash": value = sin(TAU * 1200.0 * t) * 0.35 + sin(TAU * 1760.0 * t) * 0.2
			"select": value = sin(TAU * 660.0 * t) * 0.35
			_: value = (sin(TAU * 440.0 * t) + sin(TAU * 660.0 * t)) * 0.25
		var sample := int(clampf(value * envelope, -1.0, 1.0) * 32767)
		bytes.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
