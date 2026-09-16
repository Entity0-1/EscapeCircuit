class_name BrainClient
extends Node

## Non-blocking loopback client for the versioned neural-service protocol.
## Gameplay never waits for the service; the latest valid response is reused.

const HOST := "127.0.0.1"
const PORT := 8765
const PROTOCOL_VERSION := 1
const SEND_INTERVAL := 1.0 / 30.0
const MAX_BUFFER_BYTES := 64 * 1024
const RECONNECT_DELAY := 1.0

var peer := StreamPeerTCP.new()
var sequence := 0
var send_accumulator := 0.0
var reconnect_time := 0.0
var receive_buffer := PackedByteArray()
var latest_output: Dictionary = {}
var latest_sequence := -1
var connection_label := "LOCAL FALLBACK"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_if_needed()


func step(delta: float, sensors: Dictionary) -> Dictionary:
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		connection_label = "PROTOTYPE SERVICE"
		_read_available()
		send_accumulator += delta
		if send_accumulator >= SEND_INTERVAL:
			var neural_delta := send_accumulator
			send_accumulator = fmod(send_accumulator, SEND_INTERVAL)
			_send_step(neural_delta, sensors)
		return latest_output

	connection_label = "LOCAL FALLBACK"
	latest_output = {}
	if status in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
		reconnect_time -= delta
		if reconnect_time <= 0.0:
			_connect_if_needed()
	return {}


func get_connection_label() -> String:
	return connection_label


func _connect_if_needed() -> void:
	if peer.get_status() in [StreamPeerTCP.STATUS_CONNECTING, StreamPeerTCP.STATUS_CONNECTED]:
		return
	peer = StreamPeerTCP.new()
	var result := peer.connect_to_host(HOST, PORT)
	if result != OK:
		reconnect_time = RECONNECT_DELAY
	else:
		reconnect_time = RECONNECT_DELAY


func _send_step(delta: float, sensors: Dictionary) -> void:
	sequence += 1
	var payload := {
		"protocol": PROTOCOL_VERSION,
		"sequence": sequence,
		"dt_ms": clampf(delta * 1000.0, 0.01, 250.0),
		"sensors": {
			"loom_left": clampf(float(sensors.get("loom_left", 0.0)), 0.0, 1.0),
			"loom_right": clampf(float(sensors.get("loom_right", 0.0)), 0.0, 1.0),
			"loom_up": clampf(float(sensors.get("loom_up", 0.0)), 0.0, 1.0),
			"loom_down": clampf(float(sensors.get("loom_down", 0.0)), 0.0, 1.0),
			"lc4_left": clampf(float(sensors.get("lc4_left", 0.0)), 0.0, 1.0),
			"lc4_right": clampf(float(sensors.get("lc4_right", 0.0)), 0.0, 1.0),
			"lplc2_left": clampf(float(sensors.get("lplc2_left", 0.0)), 0.0, 1.0),
			"lplc2_right": clampf(float(sensors.get("lplc2_right", 0.0)), 0.0, 1.0),
			"proximity": clampf(float(sensors.get("proximity", 0.0)), 0.0, 1.0),
			"impact": clampf(float(sensors.get("impact", 0.0)), 0.0, 1.0),
		},
	}
	var encoded := (JSON.stringify(payload) + "\n").to_utf8_buffer()
	var result := peer.put_data(encoded)
	if result != OK:
		latest_output = {}


func _read_available() -> void:
	var available := peer.get_available_bytes()
	if available <= 0:
		return
	var result := peer.get_data(available)
	if result[0] != OK:
		latest_output = {}
		return
	receive_buffer.append_array(result[1])
	if receive_buffer.size() > MAX_BUFFER_BYTES:
		receive_buffer.clear()
		latest_output = {}
		return

	var text := receive_buffer.get_string_from_utf8()
	var newline_index := text.find("\n")
	while newline_index >= 0:
		var line := text.substr(0, newline_index)
		text = text.substr(newline_index + 1)
		_parse_response(line)
		newline_index = text.find("\n")
	receive_buffer = text.to_utf8_buffer()


func _parse_response(line: String) -> void:
	var value = JSON.parse_string(line)
	if not value is Dictionary:
		return
	if int(value.get("protocol", -1)) != PROTOCOL_VERSION:
		return
	var response_sequence := int(value.get("sequence", -1))
	if response_sequence <= latest_sequence:
		return
	var brain_value = value.get("brain", {})
	var activity_value = value.get("activity", {})
	if not brain_value is Dictionary or not activity_value is Dictionary:
		return
	latest_sequence = response_sequence
	latest_output = {
		"escape_drive": clampf(float(brain_value.get("escape_drive", 0.0)), 0.0, 1.0),
		"turn_bias": clampf(float(brain_value.get("turn_bias", 0.0)), -1.0, 1.0),
		"forward_drive": clampf(float(brain_value.get("forward_drive", 0.0)), 0.0, 1.0),
		"takeoff_drive": clampf(float(brain_value.get("takeoff_drive", 0.0)), 0.0, 1.0),
		"fast_takeoff_drive": clampf(float(brain_value.get("fast_takeoff_drive", brain_value.get("takeoff_drive", 0.0))), 0.0, 1.0),
		"backward_takeoff_drive": clampf(float(brain_value.get("backward_takeoff_drive", 0.0)), 0.0, 1.0),
		"forward_takeoff_drive": clampf(float(brain_value.get("forward_takeoff_drive", 0.0)), 0.0, 1.0),
		"flight_saccade_drive": clampf(float(brain_value.get("flight_saccade_drive", 0.0)), 0.0, 1.0),
		"saccade_side": clampf(float(brain_value.get("saccade_side", 0.0)), -1.0, 1.0),
		"yaw_drive": clampf(float(brain_value.get("yaw_drive", brain_value.get("turn_bias", 0.0))), -1.0, 1.0),
		"pitch_drive": clampf(float(brain_value.get("pitch_drive", 0.0)), -1.0, 1.0),
		"roll_drive": clampf(float(brain_value.get("roll_drive", 0.0)), -1.0, 1.0),
		"flight_power": clampf(float(brain_value.get("flight_power", 0.5)), 0.0, 1.0),
		"landing_drive": clampf(float(brain_value.get("landing_drive", 0.0)), 0.0, 1.0),
		"trigger_escape": bool(brain_value.get("trigger_escape", false)),
		"activity": activity_value,
		"mode": str(value.get("mode", "NEURAL SERVICE")),
		"compute_ms": maxf(0.0, float(value.get("compute_ms", 0.0))),
	}
