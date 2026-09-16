class_name ConnectomeBrain
extends RefCounted

## In-process population-rate controller built from the checked-in MaleCNS
## sensorimotor artifact. Observed contact counts drive descending populations;
## the dynamics, stimulus encoding, and 3D motor decoder are engineering choices.

const CIRCUIT_PATH := "res://brain/circuits/malecns-v1.0-looming-escape.json"
const RESPONSE_RATE := 11.0
const ADAPTATION_RATE := 0.58
const DIRECTIONAL_TARGETS := ["DNp02", "DNp04", "DNp11"]
const COLLISION_TARGETS := ["DNp03", "DNp06"]

var contacts: Dictionary = {}
var target_activity: Dictionary = {}
var escape_drive := 0.0
var motor_bias := 0.0
var pitch_drive := 0.0
var adaptation := 0.0
var load_error := ""


func _init(circuit_path := CIRCUIT_PATH) -> void:
	_load_circuit(circuit_path)
	reset()


func is_loaded() -> bool:
	return not contacts.is_empty()


func reset() -> void:
	target_activity.clear()
	for target_key in contacts:
		target_activity[target_key] = 0.0
	escape_drive = 0.0
	motor_bias = 0.0
	pitch_drive = 0.0
	adaptation = 0.0


func step(delta: float, sensors: Dictionary) -> Dictionary:
	if not is_loaded():
		return {}

	var loom_left := clampf(float(sensors.get("loom_left", 0.0)), 0.0, 1.0)
	var loom_right := clampf(float(sensors.get("loom_right", 0.0)), 0.0, 1.0)
	var proximity := clampf(float(sensors.get("proximity", 0.0)), 0.0, 1.0)
	var impact := clampf(float(sensors.get("impact", 0.0)), 0.0, 1.0)
	var loom_up := clampf(float(sensors.get("loom_up", 0.0)), 0.0, 1.0)
	var loom_down := clampf(float(sensors.get("loom_down", 0.0)), 0.0, 1.0)
	var alpha := 1.0 - exp(-RESPONSE_RATE * delta)
	# Legacy inputs remain supported for recorded/test callers; live gameplay
	# supplies separate angular-speed (LC4) and size (LPLC2) feature channels.
	var lc4_left := clampf(float(sensors.get("lc4_left", loom_left)), 0.0, 1.0)
	var lc4_right := clampf(float(sensors.get("lc4_right", loom_right)), 0.0, 1.0)
	var lplc2_left := clampf(float(sensors.get("lplc2_left", loom_left * (0.72 + proximity * 0.28))), 0.0, 1.0)
	var lplc2_right := clampf(float(sensors.get("lplc2_right", loom_right * (0.72 + proximity * 0.28))), 0.0, 1.0)
	var source_activity := {
		"LC4:L": lc4_left,
		"LC4:R": lc4_right,
		"LPLC2:L": lplc2_left,
		"LPLC2:R": lplc2_right,
	}

	for target_key in contacts:
		var incoming: Dictionary = contacts[target_key]
		var total_contacts := 0
		var weighted_drive := 0.0
		for source_key in incoming:
			var weight := int(incoming[source_key])
			total_contacts += weight
			weighted_drive += float(source_activity.get(source_key, 0.0)) * weight
		var drive := weighted_drive / total_contacts if total_contacts > 0 else 0.0
		target_activity[target_key] = lerpf(float(target_activity[target_key]), drive, alpha)

	var left_fast := _activity("DNp01", "L")
	var right_fast := _activity("DNp01", "R")
	var left_directional := _maximum_activity(DIRECTIONAL_TARGETS, "L")
	var right_directional := _maximum_activity(DIRECTIONAL_TARGETS, "R")
	var left_collision := _maximum_activity(COLLISION_TARGETS, "L")
	var right_collision := _maximum_activity(COLLISION_TARGETS, "R")
	var left_backward := (_activity("DNp02", "L") + _activity("DNp04", "L")) * 0.5
	var right_backward := (_activity("DNp02", "R") + _activity("DNp04", "R")) * 0.5
	var backward_takeoff := maxf(left_backward, right_backward)
	var forward_takeoff := maxf(_activity("DNp11", "L"), _activity("DNp11", "R"))
	var left_saccade := _activity("DNp03", "L")
	var right_saccade := _activity("DNp03", "R")
	var flight_saccade := maxf(left_saccade, right_saccade)
	var evasive := maxf(left_collision, right_collision)
	var fast := maxf(left_fast, right_fast)
	var directional := maxf(left_directional, right_directional)
	var target_escape := minf(
		1.0,
		fast * 0.48 + directional * 0.30 + evasive * 0.22 + proximity * 0.10 + impact
	)
	escape_drive = lerpf(escape_drive, target_escape, alpha)
	var target_bias := (
		left_directional + left_fast + left_collision * 0.75
		- right_directional - right_fast - right_collision * 0.75
	) / 2.75
	motor_bias = lerpf(motor_bias, target_bias, alpha)
	var vertical_threat := loom_down - loom_up
	pitch_drive = lerpf(pitch_drive, vertical_threat * maxf(evasive, escape_drive) * 1.25, alpha)
	adaptation = maxf(0.0, adaptation - ADAPTATION_RATE * delta)
	var trigger := escape_drive > 0.36 + adaptation * 0.16
	if trigger:
		adaptation = 1.0

	var takeoff_drive := clampf(fast * 0.66 + directional * 0.19 + evasive * 0.15 + impact, 0.0, 1.0)
	var flight_power := clampf(0.48 + maxf(escape_drive, evasive) * 0.52, 0.0, 1.0)
	var landing_drive := clampf(1.0 - maxf(escape_drive, proximity * 0.72), 0.0, 1.0)
	var yaw_drive := clampf(motor_bias, -1.0, 1.0)
	var roll_drive := clampf(-yaw_drive * (0.62 + evasive * 0.30), -1.0, 1.0)
	return {
		"escape_drive": escape_drive,
		"turn_bias": yaw_drive,
		"forward_drive": minf(1.0, 0.58 + flight_power * 0.42),
		"takeoff_drive": takeoff_drive,
		"fast_takeoff_drive": fast,
		"backward_takeoff_drive": backward_takeoff,
		"forward_takeoff_drive": forward_takeoff,
		"flight_saccade_drive": flight_saccade,
		"saccade_side": clampf(left_saccade - right_saccade, -1.0, 1.0),
		"yaw_drive": yaw_drive,
		"pitch_drive": clampf(pitch_drive, -1.0, 1.0),
		"roll_drive": roll_drive,
		"flight_power": flight_power,
		"landing_drive": landing_drive,
		"trigger_escape": trigger,
		"activity": {
			"visual_left": maxf(loom_left, left_fast),
			"visual_right": maxf(loom_right, right_fast),
			"lc4": maxf(lc4_left, lc4_right),
			"lplc2": maxf(lplc2_left, lplc2_right),
			"dn_takeoff": fast,
			"dn_backward": backward_takeoff,
			"dn_forward": forward_takeoff,
			"dn_saccade": flight_saccade,
			"escape": escape_drive,
			"motor": minf(1.0, maxf(absf(yaw_drive), maxf(absf(pitch_drive), flight_power * escape_drive))),
		},
		"mode": "MALECNS SENSORIMOTOR",
	}


func get_observed_contacts(source_type: String, source_side: String, target_type: String, target_side: String) -> int:
	var incoming: Dictionary = contacts.get(_target_key(target_type, target_side), {})
	return int(incoming.get("%s:%s" % [source_type, source_side], 0))


func _load_circuit(path: String) -> void:
	if not FileAccess.file_exists(path):
		load_error = "Circuit artifact is missing: %s" % path
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", -1)) != 1:
		load_error = "Circuit artifact has an unsupported schema"
		return
	var rows = parsed.get("observed_aggregates", [])
	if not rows is Array:
		load_error = "Circuit artifact has no observed aggregates"
		return
	for value in rows:
		if not value is Dictionary:
			continue
		var target_key := _target_key(str(value.get("target_type", "")), str(value.get("target_side", "")))
		var source_key := "%s:%s" % [value.get("source_type", ""), value.get("source_side", "")]
		if target_key == "|" or source_key == ":":
			continue
		if not contacts.has(target_key):
			contacts[target_key] = {}
		var incoming: Dictionary = contacts[target_key]
		incoming[source_key] = int(incoming.get(source_key, 0)) + int(value.get("synaptic_contacts", 0))
	if contacts.is_empty():
		load_error = "Circuit artifact contains no usable connections"


func _activity(target_type: String, side: String) -> float:
	return float(target_activity.get(_target_key(target_type, side), 0.0))


func _maximum_activity(targets: Array, side: String) -> float:
	var maximum := 0.0
	for target in targets:
		maximum = maxf(maximum, _activity(str(target), side))
	return maximum


func _target_key(target_type: String, side: String) -> String:
	return "%s|%s" % [target_type, side]
