extends Node

## Autoload singleton for procedural audio. Generates all sound effects and BGM in-memory using AudioStreamWAV, no external files required.

signal muted_changed(is_muted: bool)

@export_range(0.0, 1.0, 0.01) var master_volume: float = 0.7
@export_range(0.0, 1.0, 0.01) var bgm_volume: float = 0.5
@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 0.8

const Singleton: String = "AudioManager"
const SAMPLE_RATE: int = 44100
const AMPLITUDE: float = 0.5

var _sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()
var _bgm_player: AudioStreamPlayer = AudioStreamPlayer.new()


func _ready() -> void:
	_sfx_player.name = "SFXPlayer"
	_bgm_player.name = "BGMPlayer"
	add_child(_sfx_player)
	add_child(_bgm_player)
	_bgm_player.stream = _generate_bgm()
	_bgm_player.volume_db = _linear_to_db(bgm_volume * master_volume)
	_bgm_player.bus = "Music"
	_sfx_player.bus = "SFX"
	_play_bgm()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("audio_mute"):
		toggle_mute()


func play_shoot() -> void:
	_play_sfx(_generate_shoot())


func play_hit() -> void:
	_play_sfx(_generate_hit())


func play_explode() -> void:
	_play_sfx(_generate_explode())


func play_powerup() -> void:
	_play_sfx(_generate_powerup())


func play_gameover() -> void:
	_play_sfx(_generate_gameover())


func toggle_mute() -> void:
	AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
	muted_changed.emit(AudioServer.is_bus_mute(0))


func set_mute(value: bool) -> void:
	AudioServer.set_bus_mute(0, value)
	muted_changed.emit(value)


func is_muted() -> bool:
	return AudioServer.is_bus_mute(0)


func _play_sfx(stream: AudioStreamWAV) -> void:
	_sfx_player.volume_db = _linear_to_db(sfx_volume * master_volume)
	_sfx_player.stream = stream
	_sfx_player.play()


func _play_bgm() -> void:
	_bgm_player.volume_db = _linear_to_db(bgm_volume * master_volume)
	_bgm_player.play()


func _linear_to_db(linear: float) -> float:
	if linear <= 0.0001:
		return -80.0
	return 20.0 * log(linear) / log(10.0)


func _generate_wave(duration: float, frequency: Callable, envelope: Callable, sample_rate: int = SAMPLE_RATE) -> AudioStreamWAV:
	var frame_count: int = int(duration * float(sample_rate))
	if frame_count <= 0:
		frame_count = 1
	var data: PackedByteArray = PackedByteArray()
	data.resize(frame_count * 2)
	for i: int in range(frame_count):
		var t: float = float(i) / float(sample_rate)
		var freq: float = frequency.call(t) as float
		var env: float = envelope.call(t, duration) as float
		var sample: float = sin(TAU * freq * t) * env * AMPLITUDE
		var sample16: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample16)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = frame_count
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func _generate_noise(duration: float, envelope: Callable, sample_rate: int = SAMPLE_RATE) -> AudioStreamWAV:
	var frame_count: int = int(duration * float(sample_rate))
	if frame_count <= 0:
		frame_count = 1
	var data: PackedByteArray = PackedByteArray()
	data.resize(frame_count * 2)
	for i: int in range(frame_count):
		var t: float = float(i) / float(sample_rate)
		var env: float = envelope.call(t, duration) as float
		var sample: float = (randf() * 2.0 - 1.0) * env * AMPLITUDE
		var sample16: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample16)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = frame_count
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


func _generate_shoot() -> AudioStreamWAV:
	var freq: Callable = func(t: float) -> float:
		return 880.0 - t * 600.0
	var env: Callable = func(t: float, duration: float) -> float:
		return maxf(0.0, 1.0 - t / duration)
	return _generate_wave(0.15, freq, env)


func _generate_hit() -> AudioStreamWAV:
	var freq: Callable = func(t: float) -> float:
		return 220.0 + sin(t * 50.0) * 100.0
	var env: Callable = func(t: float, duration: float) -> float:
		return maxf(0.0, 1.0 - t / duration)
	return _generate_wave(0.2, freq, env)


func _generate_explode() -> AudioStreamWAV:
	var env: Callable = func(t: float, duration: float) -> float:
		return maxf(0.0, 1.0 - t / duration)
	return _generate_noise(0.5, env)


func _generate_powerup() -> AudioStreamWAV:
	var freq: Callable = func(t: float) -> float:
		return 440.0 + t * 800.0
	var env: Callable = func(t: float, duration: float) -> float:
		return maxf(0.0, 1.0 - t / duration)
	return _generate_wave(0.35, freq, env)


func _generate_gameover() -> AudioStreamWAV:
	var freq: Callable = func(t: float) -> float:
		return 330.0 - t * 200.0
	var env: Callable = func(t: float, duration: float) -> float:
		return maxf(0.0, 1.0 - t / duration)
	return _generate_wave(1.2, freq, env)


func _generate_bgm() -> AudioStreamWAV:
	var beat_duration: float = 0.5
	var beats: int = 8
	var duration: float = beat_duration * float(beats)
	var sample_rate: int = SAMPLE_RATE
	var frame_count: int = int(duration * float(sample_rate))
	if frame_count <= 0:
		frame_count = 1
	var data: PackedByteArray = PackedByteArray()
	data.resize(frame_count * 2)
	var notes: Array[float] = [220.0, 220.0, 165.0, 196.0, 220.0, 165.0, 196.0, 220.0]
	for i: int in range(frame_count):
		var t: float = float(i) / float(sample_rate)
		var beat_index: int = int(t / beat_duration) % beats
		var note_freq: float = notes[beat_index]
		var beat_t: float = fmod(t, beat_duration) / beat_duration
		var env: float = maxf(0.0, 1.0 - beat_t * 2.0)
		var sample: float = sin(TAU * note_freq * t) * env * 0.15
		var sample16: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample16)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
