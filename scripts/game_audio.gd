extends Node
## Tiny original synthesized cues; no third-party audio assets or runtime downloads.

var enabled: bool = true
var voices: Array[AudioStreamPlayer] = []
var cues: Dictionary = {}
var next_voice: int = 0


func _ready() -> void:
	for i in range(5):
		var player := AudioStreamPlayer.new()
		player.volume_db = -15.0
		add_child(player)
		voices.append(player)
	for spec in [["click", 650.0, 0.055], ["place", 390.0, 0.14],
		["upgrade", 790.0, 0.25], ["wave", 300.0, 0.22],
		["complete", 520.0, 0.28], ["victory", 660.0, 0.7],
		["defeat", 190.0, 0.4], ["error", 160.0, 0.09]]:
		cues[spec[0]] = _make_tone(float(spec[1]), float(spec[2]), str(spec[0]))


func play_cue(kind: String) -> void:
	if not enabled or not cues.has(kind) or voices.is_empty():
		return
	var player: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	player.stream = cues[kind]
	player.play()


func _make_tone(frequency: float, duration: float, kind: String) -> AudioStreamWAV:
	var rate: int = 22050
	var count: int = int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / rate
		var envelope: float = minf(t * 70.0, 1.0) * pow(1.0 - t / duration, 1.7)
		var pitch: float = frequency
		if kind == "victory":
			pitch *= [1.0, 1.25, 1.5, 2.0][mini(int(t / duration * 4.0), 3)]
		elif kind == "upgrade":
			pitch *= 1.0 + t / duration * 0.6
		var wave: float = sin(TAU * pitch * t) * 0.7 + sin(TAU * pitch * 2.0 * t) * 0.13
		bytes.encode_s16(i * 2, int(wave * envelope * 21000.0))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = rate
	audio.data = bytes
	return audio
