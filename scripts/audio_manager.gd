extends Node

var _sfx_players = []
var _music_player: AudioStreamPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 16:
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	_music_player.volume_db = -10
	add_child(_music_player)

func play_sfx(type):
	var stream = _generate_sfx(type)
	if stream == null:
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = randf_range(-3, 0)
			p.pitch_scale = randf_range(0.92, 1.08)
			p.play()
			return
	var p = _sfx_players[0]
	p.stream = stream
	p.play()

func play_music(track):
	var stream = _generate_music(track)
	if stream == null:
		return
	if _music_player.stream != null and _music_player.playing:
		_music_player.stop()
	_music_player.stream = stream
	_music_player.play()

func stop_music():
	if _music_player and _music_player.playing:
		_music_player.stop()

func _generate_sfx(type):
	var rate = 22050.0
	var duration = 0.15
	if type == "shoot":
		duration = 0.09
	elif type == "hit":
		duration = 0.2
	elif type == "explode":
		duration = 0.5
	elif type == "powerup":
		duration = 0.45
	elif type == "click":
		duration = 0.04
	elif type == "damage":
		duration = 0.25
	elif type == "gameover":
		duration = 1.2
	elif type == "wave":
		duration = 0.6
	elif type == "warning":
		duration = 0.5
	else:
		return null
	var frames = int(rate * duration)
	var stream = AudioStreamWAV.new()
	stream.mix_rate = rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	var data = PackedByteArray()
	data.resize(frames * 2)
	var phase = 0.0
	var phase2 = 0.0
	for i in frames:
		var p = float(i) / rate
		var s = 0.0
		if type == "shoot":
			var f = lerp(1400.0, 220.0, p / duration)
			phase += f / rate
			s = sin(phase * TAU) * exp(-p * 28.0) * 0.6
		elif type == "hit":
			var f = lerp(900.0, 120.0, p / duration)
			phase += f / rate
			s = sin(phase * TAU) * exp(-p * 9.0) * 0.5
			s += (randf() * 2.0 - 1.0) * exp(-p * 18.0) * 0.4
		elif type == "explode":
			s = (randf() * 2.0 - 1.0) * exp(-p * 3.5) * (1.0 - p / duration) * 0.7
			s += sin(p * 70.0) * exp(-p * 7.0) * 0.3
		elif type == "powerup":
			var f = 440.0 + 800.0 * (p / duration)
			phase += f / rate
			s = sin(phase * TAU) * exp(-p * 2.5) * 0.6
		elif type == "click":
			s = sin(p * 1600.0) * exp(-p * 90.0) * 0.5
		elif type == "damage":
			s = (randf() * 2.0 - 1.0) * exp(-p * 6.0) * 0.8
		elif type == "gameover":
			var f = lerp(440.0, 70.0, p / duration)
			phase += f / rate
			s = sin(phase * TAU) * exp(-p * 1.8)
		elif type == "wave":
			var f = 660.0
			phase += f / rate
			phase2 += f * 1.5 / rate
			s = (sin(phase * TAU) + sin(phase2 * TAU) * 0.5) * exp(-p * 3.0) * 0.7
		elif type == "warning":
			# 警示音：双音警报，3 次重复
			var cycle = fmod(p, 0.18)
			var in_burst = cycle < 0.08
			if in_burst:
				var f = 880.0
				phase += f / rate
				s = sin(phase * TAU) * 0.5
			else:
				s = 0.0
		s = clamp(s, -1.0, 1.0)
		var sample = int(s * 32767.0)
		data[i * 2] = sample & 0xff
		data[i * 2 + 1] = (sample >> 8) & 0xff
	stream.data = data
	return stream

func _generate_music(track):
	var rate = 22050.0
	var bpm = 130.0 if track == "game" else 80.0
	var beat_dur = 60.0 / bpm
	var beats = 16.0
	var duration = beat_dur * beats
	var frames = int(rate * duration)
	var stream = AudioStreamWAV.new()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	stream.mix_rate = rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	var data = PackedByteArray()
	data.resize(frames * 2)
	var notes = [392.0, 523.25, 659.25, 523.25, 392.0, 329.63, 392.0, 523.25,
				 440.0, 587.33, 698.46, 587.33, 440.0, 349.23, 440.0, 523.25]
	if track == "menu":
		notes = [261.63, 329.63, 392.0, 329.63, 261.63, 196.0, 261.63, 329.63,
				 293.66, 349.23, 440.0, 349.23, 293.66, 220.0, 293.66, 349.23]
	var bass_notes = [98.0, 130.81, 146.83, 110.0, 98.0, 87.31, 98.0, 130.81,
					  110.0, 146.83, 164.81, 130.81, 110.0, 98.0, 110.0, 146.83]
	for i in frames:
		var t = float(i) / rate
		var beat_idx = int(t / beat_dur)
		var bar_pos = beat_idx % notes.size()
		var beat = fmod(t, beat_dur) / beat_dur
		var note = notes[bar_pos]
		var bass = bass_notes[bar_pos]
		var env = 0.0
		if beat < 0.04:
			env = beat / 0.04
		elif beat < 0.12:
			env = 1.0 - (beat - 0.04) / 0.08 * 0.4
		else:
			env = exp(-(beat - 0.12) * 2.5) * 0.55
		var s = sin(t * note * TAU) * env * 0.22
		s += sin(t * bass * TAU) * env * 0.25
		if beat_idx % 4 == 1 or beat_idx % 4 == 3:
			if beat < 0.05:
				s += (randf() * 2.0 - 1.0) * exp(-beat * 35.0) * 0.4
		if beat_idx % 4 == 0 or beat_idx % 4 == 2:
			if beat < 0.08:
				var k_env = 1.0 - beat / 0.08
				s += sin(t * 60.0 * TAU * exp(-beat * 12.0)) * k_env * 0.45
		s = clamp(s, -1.0, 1.0)
		var sample = int(s * 32767.0)
		data[i * 2] = sample & 0xff
		data[i * 2 + 1] = (sample >> 8) & 0xff
	stream.data = data
	return stream
