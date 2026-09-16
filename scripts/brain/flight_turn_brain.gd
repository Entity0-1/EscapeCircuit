class_name FlightTurnBrain
extends RefCounted

## A separate six-cell spontaneous-turn motif. Contacts are observed MaleCNS
## counts; tonic input, signs, rate dynamics, and motor decoding are modeled.

const CIRCUIT_PATH := "res://brain/circuits/malecns-v1.0-flight-turn.json"
const RESPONSE_RATE := 18.0

var contacts: Dictionary = {}
var activity: Dictionary = {}
var contact_scale := 1.0
var load_error := ""


func _init(circuit_path := CIRCUIT_PATH) -> void:
	_load_circuit(circuit_path)
	reset()


func is_loaded() -> bool:
	return not contacts.is_empty()


func reset() -> void:
	activity.clear()
	for node_type in ["VES041", "DNa15", "DNb01"]:
		for side in ["L", "R"]:
			activity[_key(node_type, side)] = 0.0


func step(delta: float, inputs: Dictionary) -> Dictionary:
	if not is_loaded():
		return {}
	var left_pulse := clampf(float(inputs.get("left_pulse", 0.0)), 0.0, 1.0)
	var right_pulse := clampf(float(inputs.get("right_pulse", 0.0)), 0.0, 1.0)
	var straight_input := clampf(float(inputs.get("straight", 0.0)), 0.0, 1.0)
	var alpha := 1.0 - exp(-RESPONSE_RATE * maxf(delta, 0.0))
	var next_activity := activity.duplicate()
	for side in ["L", "R"]:
		# The VES041 tonic drive is an engineered proxy for a straight-flight state.
		next_activity[_key("VES041", side)] = lerpf(
			float(activity[_key("VES041", side)]), straight_input, alpha
		)
	for side in ["L", "R"]:
		var pulse := left_pulse if side == "L" else right_pulse
		var dna_key := _key("DNa15", side)
		var dnb_key := _key("DNb01", side)
		var dna_target := clampf(
			pulse
			- _weighted_input(dna_key, "VES041", next_activity) * 0.55
			- _weighted_input(dna_key, "DNb01", activity) * 0.30,
			0.0, 1.0
		)
		var dnb_target := clampf(
			pulse
			- _weighted_input(dnb_key, "VES041", next_activity) * 0.95
			- _weighted_input(dnb_key, "DNa15", activity) * 0.15,
			0.0, 1.0
		)
		next_activity[dna_key] = lerpf(float(activity[dna_key]), dna_target, alpha)
		next_activity[dnb_key] = lerpf(float(activity[dnb_key]), dnb_target, alpha)
	activity = next_activity
	var left_turn := minf(float(activity[_key("DNa15", "L")]), float(activity[_key("DNb01", "L")]))
	var right_turn := minf(float(activity[_key("DNa15", "R")]), float(activity[_key("DNb01", "R")]))
	return {
		"turn_drive": clampf(right_turn - left_turn, -1.0, 1.0),
		"saccade_drive": maxf(left_turn, right_turn),
		"straight_drive": maxf(float(activity[_key("VES041", "L")]), float(activity[_key("VES041", "R")])),
		"activity": activity.duplicate(),
		"mode": "MALECNS FLIGHT TURN",
	}


func get_observed_contacts(source_type: String, source_side: String, target_type: String, target_side: String) -> int:
	var incoming: Dictionary = contacts.get(_key(target_type, target_side), {})
	return int(incoming.get("%s:%s" % [source_type, source_side], 0))


func _weighted_input(target_key: String, source_type: String, values: Dictionary) -> float:
	var incoming: Dictionary = contacts.get(target_key, {})
	var drive := 0.0
	for source_side in ["L", "R"]:
		var source_key := "%s:%s" % [source_type, source_side]
		drive += float(incoming.get(source_key, 0)) * float(values.get(_key(source_type, source_side), 0.0))
	return drive / contact_scale


func _load_circuit(path: String) -> void:
	if not FileAccess.file_exists(path):
		load_error = "Flight-turn artifact is missing: %s" % path
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", -1)) != 1:
		load_error = "Flight-turn artifact has an unsupported schema"
		return
	var rows = parsed.get("observed_aggregates", [])
	if not rows is Array:
		load_error = "Flight-turn artifact has no observed aggregates"
		return
	for value in rows:
		if not value is Dictionary:
			continue
		var target_key := _key(str(value.get("target_type", "")), str(value.get("target_side", "")))
		var source_key := "%s:%s" % [value.get("source_type", ""), value.get("source_side", "")]
		if target_key == "|" or source_key == ":":
			continue
		if not contacts.has(target_key):
			contacts[target_key] = {}
		var incoming: Dictionary = contacts[target_key]
		incoming[source_key] = int(incoming.get(source_key, 0)) + int(value.get("synaptic_contacts", 0))
	for target_key in contacts:
		var incoming: Dictionary = contacts[target_key]
		var total := 0
		for source_key in incoming:
			total += int(incoming[source_key])
		contact_scale = maxf(contact_scale, float(total))
	if contacts.is_empty():
		load_error = "Flight-turn artifact contains no usable connections"


func _key(node_type: String, side: String) -> String:
	return "%s|%s" % [node_type, side]
