extends SceneTree

var failures := 0


func _init() -> void:
	_test_fallback_brain_is_deterministic()
	_test_lateral_bias_changes_sign()
	_test_escape_threshold()
	_test_malecns_artifact_is_loaded()
	_test_malecns_controller_escapes()
	_test_malecns_controller_emits_3d_motor_commands()
	if failures == 0:
		print("PASS: 6 neural-controller tests")
		quit(0)
	else:
		push_error("FAIL: %d test(s) failed" % failures)
		quit(1)


func _test_fallback_brain_is_deterministic() -> void:
	var first := FallbackBrain.new()
	var second := FallbackBrain.new()
	var sensors := {"loom_left": 0.8, "loom_right": 0.1, "proximity": 0.7, "impact": 0.0}
	var first_output: Dictionary
	var second_output: Dictionary
	for _step in range(12):
		first_output = first.step(1.0 / 60.0, sensors)
		second_output = second.step(1.0 / 60.0, sensors)
	_assert_close(float(first_output.escape_drive), float(second_output.escape_drive), "deterministic escape output")


func _test_lateral_bias_changes_sign() -> void:
	var left_brain := FallbackBrain.new()
	var right_brain := FallbackBrain.new()
	var left_output: Dictionary
	var right_output: Dictionary
	for _step in range(30):
		left_output = left_brain.step(1.0 / 60.0, {"loom_left": 1.0, "loom_right": 0.0})
		right_output = right_brain.step(1.0 / 60.0, {"loom_left": 0.0, "loom_right": 1.0})
	_assert(float(left_output.turn_bias) > 0.0, "left input produces positive bias")
	_assert(float(right_output.turn_bias) < 0.0, "right input produces negative bias")


func _test_escape_threshold() -> void:
	var brain := FallbackBrain.new()
	var triggered := false
	for _step in range(30):
		var output := brain.step(1.0 / 60.0, {"loom_left": 1.0, "loom_right": 1.0, "proximity": 1.0})
		triggered = triggered or bool(output.trigger_escape)
	_assert(triggered, "strong looming input triggers escape")


func _test_malecns_artifact_is_loaded() -> void:
	var brain := ConnectomeBrain.new()
	_assert(brain.is_loaded(), "checked-in MaleCNS circuit artifact loads")
	_assert(
		brain.get_observed_contacts("LC4", "L", "DNp01", "L") == 3782,
		"known observed MaleCNS contact count is preserved"
	)
	_assert(
		brain.get_observed_contacts("LC4", "L", "DNp03", "L") == 1827,
		"observed DNp03 collision-avoidance contacts are preserved"
	)


func _test_malecns_controller_escapes() -> void:
	var brain := ConnectomeBrain.new()
	var triggered := false
	var output: Dictionary = {}
	for _step in range(90):
		output = brain.step(1.0 / 60.0, {
			"loom_left": 1.0,
			"loom_right": 0.25,
			"proximity": 0.95,
			"impact": 0.0,
		})
		triggered = triggered or bool(output.get("trigger_escape", false))
	_assert(triggered, "strong looming input triggers the MaleCNS circuit")
	_assert(float(output.get("turn_bias", 0.0)) > 0.0, "MaleCNS circuit preserves lateral bias")
	_assert(str(output.get("mode", "")) == "MALECNS SENSORIMOTOR", "MaleCNS mode is labeled")


func _test_malecns_controller_emits_3d_motor_commands() -> void:
	var brain := ConnectomeBrain.new()
	var baseline := brain.step(1.0 / 60.0, {})
	var output: Dictionary = {}
	for _step in range(30):
		output = brain.step(1.0 / 60.0, {
			"loom_left": 1.0,
			"loom_right": 0.05,
			"loom_up": 1.0,
			"loom_down": 0.0,
			"proximity": 0.9,
			"impact": 0.0,
		})
	_assert(float(output.get("yaw_drive", 0.0)) > 0.0, "left-side threat produces rightward yaw")
	_assert(float(output.get("pitch_drive", 0.0)) < 0.0, "threat above produces a downward pitch command")
	_assert(float(output.get("takeoff_drive", 0.0)) > 0.4, "descending activity produces takeoff drive")
	_assert(float(output.get("flight_power", 0.0)) > float(baseline.get("flight_power", 0.0)), "threat increases flight power")
	_assert(float(output.get("landing_drive", 1.0)) < 0.4, "nearby threat suppresses landing")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _assert_close(actual: float, expected: float, message: String) -> void:
	_assert(absf(actual - expected) < 0.000001, message)
