class_name AudioController
extends Node

## Small procedural sound set. All samples are synthesized at runtime so the
## project ships without third-party audio assets or attribution ambiguity.

const SAMPLE_RATE := 22050

var buzz_player: AudioStreamPlayer3D
var effects_player: AudioStreamPlayer
var buzz_stream: AudioStreamWAV
var whoosh_stream: AudioStreamWAV
var hit_stream: AudioStreamWAV
var miss_stream: AudioStreamWAV
var dodge_stream: AudioStreamWAV
var enabled := true


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	buzz_stream = _make_buzz()
	whoosh_stream = _make_whoosh()
	hit_stream = _make_hit()
	miss_stream = _make_miss()
	dodge_stream = _make_dodge()
	effects_player = AudioStreamPlayer.new()
	effects_player.name = "Effects"
	effects_player.volume_db = -8.0
	add_child(effects_player)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	if buzz_player:
		buzz_player.stop()
		buzz_player.stream = null
	if effects_player:
		effects_player.stop()
		effects_player.stream = null
	buzz_stream = null
	whoosh_stream = null
	hit_stream = null
	miss_stream = null
	dodge_stream = null


func attach_fly(fly: Node3D) -> void:
	if not enabled:
		return
	buzz_player = AudioStreamPlayer3D.new()
	buzz_player.name = "ProceduralBuzz"
	buzz_player.stream = buzz_stream
	buzz_player.volume_db = -17.0
	buzz_player.max_distance = 14.0
	buzz_player.unit_size = 2.4
	buzz_player.panning_strength = 1.4
	fly.add_child(buzz_player)


func set_active(active: bool) -> void:
	if not buzz_player:
		return
	if active and not buzz_player.playing:
		buzz_player.play()
	elif not active and buzz_player.playing:
		buzz_player.stop()


func update_fly_energy(energy: float) -> void:
	if buzz_player:
		buzz_player.pitch_scale = lerpf(0.84, 1.36, clampf(energy, 0.0, 1.0))


func play_swing() -> void:
	_play_effect(whoosh_stream, 1.0)


func play_hit() -> void:
	_play_effect(hit_stream, 1.0)


func play_miss() -> void:
	_play_effect(miss_stream, 0.94)


func play_dodge() -> void:
	_play_effect(dodge_stream, 1.0)


func _play_effect(stream: AudioStreamWAV, pitch: float) -> void:
	if not effects_player or not stream:
		return
	effects_player.stop()
	effects_player.stream = stream
	effects_player.pitch_scale = pitch
	effects_player.play()


func _make_buzz() -> AudioStreamWAV:
	var duration := 0.12
	var samples := int(duration * SAMPLE_RATE)
	var values := PackedFloat32Array()
	values.resize(samples)
	for index in samples:
		var time := float(index) / SAMPLE_RATE
		values[index] = (
			sin(TAU * 178.0 * time) * 0.12
			+ sin(TAU * 356.0 * time) * 0.065
			+ sin(TAU * 534.0 * time) * 0.025
		)
	var stream := _stream_from_values(values)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	return stream


func _make_whoosh() -> AudioStreamWAV:
	var duration := 0.24
	var samples := int(duration * SAMPLE_RATE)
	var values := PackedFloat32Array()
	values.resize(samples)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4815
	var filtered := 0.0
	for index in samples:
		var progress := float(index) / samples
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.18)
		var envelope := sin(progress * PI) * (1.0 - progress * 0.35)
		values[index] = filtered * envelope * 0.68
	return _stream_from_values(values)


func _make_hit() -> AudioStreamWAV:
	var duration := 0.34
	var samples := int(duration * SAMPLE_RATE)
	var values := PackedFloat32Array()
	values.resize(samples)
	for index in samples:
		var time := float(index) / SAMPLE_RATE
		var progress := float(index) / samples
		var envelope := exp(-progress * 8.0)
		values[index] = (sin(TAU * 76.0 * time) * 0.72 + sin(TAU * 122.0 * time) * 0.25) * envelope
	return _stream_from_values(values)


func _make_miss() -> AudioStreamWAV:
	var duration := 0.16
	var samples := int(duration * SAMPLE_RATE)
	var values := PackedFloat32Array()
	values.resize(samples)
	for index in samples:
		var time := float(index) / SAMPLE_RATE
		var progress := float(index) / samples
		values[index] = sin(TAU * (145.0 - progress * 35.0) * time) * exp(-progress * 7.0) * 0.38
	return _stream_from_values(values)


func _make_dodge() -> AudioStreamWAV:
	var duration := 0.18
	var samples := int(duration * SAMPLE_RATE)
	var values := PackedFloat32Array()
	values.resize(samples)
	var phase := 0.0
	for index in samples:
		var progress := float(index) / samples
		var frequency := lerpf(430.0, 860.0, progress)
		phase += TAU * frequency / SAMPLE_RATE
		values[index] = sin(phase) * sin(progress * PI) * 0.22
	return _stream_from_values(values)


func _stream_from_values(values: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 2)
	for index in values.size():
		var sample := int(clampf(values[index], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
