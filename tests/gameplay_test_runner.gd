extends SceneTree

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_resource := load("res://scenes/main.tscn") as PackedScene
	_assert(scene_resource != null, "main scene loads")
	if scene_resource == null:
		quit(1)
		return
	var game = scene_resource.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	_test_direct_hit(game)
	_test_smaller_swatter_hitbox(game)
	_test_near_miss(game)
	_test_fly_moves_in_three_dimensions(game)
	_test_cruise_altitude_is_gameplay_only(game)
	_test_neural_motor_channels_steer_fly(game)
	_test_distinct_escape_actions(game)
	_test_observed_escape_circuit_selects_takeoffs(game)
	_test_flight_turn_motif_steers_cruising(game)
	_test_player_approach_threatens_fly(game)
	_test_vertical_escape_is_fast(game)
	_test_imported_fly_model(game)
	_test_fly_faces_its_actual_travel(game)
	_test_fly_uses_compact_difficulty_scale(game)
	_test_threat_telemetry(game)
	_test_split_screen_replay(game)
	_test_charge_up_does_not_alert_fly(game)
	_test_perched_fly_launches_before_impact(game)
	_test_fly_resolves_furniture_collision(game)
	_test_expanded_apartment_rooms(game)
	_test_room_doorways_and_shared_collision(game)
	_test_fly_uses_doorway_to_reach_kitchen(game)
	_test_fly_uses_doorway_to_reach_bedroom(game)
	_test_player_walks_and_respects_furniture(game)
	_test_swatter_uses_first_person_pose(game)
	_test_timeout(game)

	game.audio.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	if failures == 0:
		print("PASS: 26 gameplay integration tests")
		quit(0)
	else:
		push_error("FAIL: %d gameplay test(s) failed" % failures)
		quit(1)


func _test_direct_hit(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.40, 1.60, 3.0)
	game._on_swing_started(1.0)
	game.swatter.global_position = game.fly.global_position
	game.swatter.phase = SwatterController.Phase.STRIKE
	game.swatter.vertical_speed = -8.0
	game.last_hit_checked = false
	game._check_swept_hit()
	_assert(game.fly.is_hit(), "direct overlap marks the fly hit")
	_assert(game.game_state == game.GameState.WON, "direct overlap wins the round")
	_assert(game.swings == 1, "winning strike is counted")


func _test_smaller_swatter_hitbox(game) -> void:
	game._start_round()
	var center := Vector3(-0.40, 1.60, 3.0)
	game.swatter.global_position = center
	game.swatter.previous_height = center.y
	_assert(game.swatter.contains_world_point(center), "a centered strike remains hittable")
	_assert(not game.swatter.contains_world_point(center + Vector3(0.40, 0.0, 0.0)), "outer left-right edge is outside the tighter hitbox")
	_assert(not game.swatter.contains_world_point(center + Vector3(0.0, 0.0, 0.32)), "outer front-back edge is outside the tighter hitbox")
	_assert(not game.swatter.contains_world_point(center + Vector3(0.0, 0.18, 0.0)), "vertical strike padding is reduced")
	game.fly.global_position = center + Vector3(0.40, 0.0, 0.0)
	game.swatter.phase = SwatterController.Phase.STRIKE
	game.swatter.vertical_speed = -8.0
	game.last_hit_checked = false
	game._check_swept_hit()
	_assert(not game.fly.is_hit(), "off-center fly survives a strike")


func _test_near_miss(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.40, 1.55, 3.0)
	game.swatter.global_position = Vector3(0.85, 1.90, 3.0)
	game._on_swing_started(0.8)
	game._on_swatter_impact(game.swatter.global_position, 0.8)
	_assert(game.swings == 1, "near miss increments the swing counter")
	_assert(game.fly.shock_input > 0.0, "near miss applies a sensory shock")
	_assert(not game.fly.is_hit(), "near miss does not hit the fly")


func _test_fly_moves_in_three_dimensions(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.5, 1.10, 2.90)
	game.fly.velocity = Vector3.ZERO
	game.fly.state = FlyController.State.FLYING
	game.fly.state_time = 0.0
	game.fly.decision_time = 5.0
	game.fly.wander_target = Vector3(0.60, 2.20, 3.62)
	game.fly.brain_output = {}
	var start_position: Vector3 = game.fly.global_position
	for _step in range(60):
		game.fly._physics_process(1.0 / 60.0)
	var movement: Vector3 = game.fly.global_position - start_position
	_assert(absf(movement.x) > 0.20, "fly traverses apartment width")
	_assert(absf(movement.y) > 0.20, "fly changes altitude")
	_assert(absf(movement.z) > 0.20, "fly traverses apartment depth")


func _test_cruise_altitude_is_gameplay_only(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.50, 1.55, 2.90)
	game.fly.velocity = Vector3.ZERO
	game.fly.state = FlyController.State.FLYING
	game.fly.decision_time = 5.0
	game.fly.wander_target = Vector3(-5.30, 1.55, 3.00)
	game.fly.cruise_altitude_timer = 0.0
	game.fly.brain_output = {"escape_drive": 0.0, "yaw_drive": 0.0, "pitch_drive": 0.0}
	var original_output: Dictionary = game.fly.brain_output.duplicate(true)
	for _step in range(20):
		game.fly._physics_process(1.0 / 60.0)
	_assert(absf(game.fly.cruise_altitude_target - 1.55) > 0.45, "ordinary flight selects a meaningful height change")
	_assert(absf(game.fly.global_position.y - 1.55) > 0.08, "ordinary flight moves vertically toward the new height")
	_assert(game.fly.brain_output == original_output, "cruise altitude does not change the circuit output")
	var cruise_target: float = game.fly.cruise_altitude_target
	var cruise_timer: float = game.fly.cruise_altitude_timer
	game.fly.state = FlyController.State.DODGING
	game.fly._update_dodge(1.0 / 60.0)
	_assert(is_equal_approx(game.fly.cruise_altitude_target, cruise_target) and is_equal_approx(game.fly.cruise_altitude_timer, cruise_timer), "neural dodge does not use cruise altitude changes")


func _test_neural_motor_channels_steer_fly(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.45, 1.70, 3.05)
	game.fly.rotation = Vector3.ZERO
	game.fly.velocity = Vector3.FORWARD * FlyController.DODGE_SPEED
	game.fly.desired_direction = Vector3.FORWARD
	game.fly.state = FlyController.State.DODGING
	game.fly.state_time = 0.0
	game.fly.brain_output = {
		"escape_drive": 1.0,
		"yaw_drive": 1.0,
		"pitch_drive": 0.0,
		"roll_drive": -0.8,
		"forward_drive": 0.7,
		"flight_power": 1.0,
	}
	var start_position: Vector3 = game.fly.global_position
	for _step in range(8):
		game.fly._physics_process(1.0 / 60.0)
	_assert(game.fly.global_position.x > start_position.x + 0.1, "connectome yaw command continuously changes the 3D trajectory")
	_assert(game.fly.body_root.rotation.z < -0.1, "connectome roll command banks the fly during the turn")


func _test_distinct_escape_actions(game) -> void:
	for case in [
		{"fast": 0.85, "back": 0.15, "forward": 0.15, "action": "FAST_TAKEOFF", "sign": 0},
		{"fast": 0.15, "back": 0.75, "forward": 0.25, "action": "BACKWARD_TAKEOFF", "sign": 1},
		{"fast": 0.15, "back": 0.25, "forward": 0.75, "action": "FORWARD_TAKEOFF", "sign": -1},
	]:
		game._start_round()
		game.fly.state = FlyController.State.PERCHED
		game.fly.global_position = FlyController.PERCH_POINTS[0]
		game.fly.rotation = Vector3.ZERO
		game.fly.brain_output = {
			"fast_takeoff_drive": case.fast,
			"backward_takeoff_drive": case.back,
			"forward_takeoff_drive": case.forward,
		}
		game.fly._begin_perch_takeoff(true)
		_assert(game.fly.selected_action == case.action, "descending-population ratios choose %s" % case.action)
		if case.sign != 0:
			_assert(signf(game.fly.velocity.z) == float(case.sign), "%s moves in its distinct body-relative direction" % case.action)
	game._start_round()
	game.fly.state = FlyController.State.FLYING
	game.fly.velocity = Vector3.FORWARD * FlyController.CRUISE_SPEED
	game.fly.brain_output = {"flight_saccade_drive": 0.85, "saccade_side": 1.0}
	game.fly._update_flight_behavior(1.0 / 60.0)
	_assert(game.fly.selected_action == "FLIGHT_SACCADE", "DNp03 activity selects an airborne saccade")
	_assert(game.fly.desired_direction.x > 0.4, "airborne saccade turns sharply away from lateral threat")


func _test_observed_escape_circuit_selects_takeoffs(game) -> void:
	for case in [
		{"lc4": 0.2, "lplc2": 0.9, "action": "FAST_TAKEOFF"},
		{"lc4": 0.9, "lplc2": 0.1, "action": "BACKWARD_TAKEOFF"},
		{"lc4": 0.9, "lplc2": 0.0, "action": "FORWARD_TAKEOFF"},
	]:
		var circuit := ConnectomeBrain.new()
		var output: Dictionary = {}
		var sensors := {
			"lc4_left": case.lc4,
			"lc4_right": case.lc4,
			"lplc2_left": case.lplc2,
			"lplc2_right": case.lplc2,
			"proximity": 0.5,
		}
		for _step in range(30):
			output = circuit.step(1.0 / 60.0, sensors)
		game.fly.brain_output = output
		_assert(game.fly._select_takeoff_action() == case.action, "observed contact ratios can select %s" % case.action)


func _test_flight_turn_motif_steers_cruising(game) -> void:
	game._start_round()
	_assert(game.fly.turn_brain.is_loaded(), "separate MaleCNS flight-turn motif loads")
	game.fly.global_position = Vector3(-0.50, 1.55, 2.90)
	game.fly.state = FlyController.State.FLYING
	game.fly.decision_time = 5.0
	game.fly.wander_target = Vector3(-1.65, 1.60, 2.90)
	game.fly.turn_pulse_timer = 5.0
	game.fly.turn_pulse_remaining = 0.25
	game.fly.turn_pulse_side = 1.0
	game.fly.brain_output = {}
	for _step in range(12):
		game.fly._physics_process(1.0 / 60.0)
	_assert(float(game.fly.turn_output.get("saccade_drive", 0.0)) > 0.2, "turn motif responds to spontaneous pulse")
	_assert(float(game.fly.turn_output.get("turn_drive", 0.0)) > 0.2, "connectome-weighted spontaneous turn steers right")
	_assert(game.fly.selected_action == "NONE", "ordinary turn does not masquerade as an escape")


func _test_player_approach_threatens_fly(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.50, 2.20, 2.90)
	game.fly.rotation = Vector3.ZERO
	game.player.position = Vector3(-0.50, 0.16, 3.80)
	game.player.movement_velocity = Vector3(0.0, 0.0, -PlayerController.MOVE_SPEED)
	game.swatter.phase = SwatterController.Phase.READY
	game.swatter.global_position = Vector3(4.0, 4.0, 4.0)
	var triggered := false
	for _step in range(45):
		game._update_fly_sensors(1.0 / 60.0)
		triggered = triggered or bool(game.fly.brain_output.get("trigger_escape", false))
	_assert(triggered, "a nearby approaching player triggers the visual escape circuit")
	_assert(float(game.fly.brain_output.get("pitch_drive", 0.0)) > 0.0, "fly climbs away from a player approaching below it")


func _test_vertical_escape_is_fast(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.50, 0.82, 3.12)
	game.fly.rotation = Vector3.ZERO
	game.fly.state = FlyController.State.DODGING
	game.fly.state_time = 0.0
	game.fly.desired_direction = Vector3.FORWARD
	game.fly.brain_output = {
		"escape_drive": 1.0,
		"yaw_drive": 0.0,
		"pitch_drive": 1.0,
		"roll_drive": 0.0,
		"forward_drive": 0.35,
		"flight_power": 1.0,
	}
	for _step in range(8):
		game.fly._update_dodge(1.0 / 60.0)
	var horizontal_speed := Vector2(game.fly.velocity.x, game.fly.velocity.z).length()
	_assert(game.fly.velocity.y > horizontal_speed, "vertical escape velocity exceeds horizontal velocity for a climb")
	_assert(game.fly.velocity.y > FlyController.DODGE_SPEED, "vertical dodge has a high-speed burst")


func _test_imported_fly_model(game) -> void:
	_assert(game.fly.imported_model != null, "credited housefly glTF model is active")
	if game.fly.imported_model != null:
		_assert(game.fly.imported_model.find_children("*", "MeshInstance3D", true, false).size() > 0, "housefly contains textured geometry")
		_assert(is_equal_approx(game.fly.imported_model.rotation.y, PI), "source model forward axis is aligned with flight")
		var pedestal: Array[Node] = game.fly.imported_model.find_children("Cylinder001*", "MeshInstance3D", true, false)
		_assert(pedestal.size() == 1 and not pedestal[0].visible, "source display pedestal is hidden")
	_assert(game.fly.left_wing_pivot != null and game.fly.right_wing_pivot != null, "housefly has separate wing pivots")
	if game.fly.left_wing_pivot and game.fly.right_wing_pivot:
		var left_mesh := (game.fly.left_wing_pivot.get_child(0) as MeshInstance3D).mesh
		var right_mesh := (game.fly.right_wing_pivot.get_child(0) as MeshInstance3D).mesh
		_assert(left_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 1044, "left wing uses one half of source geometry")
		_assert(right_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 1044, "right wing uses the other half")
		game.fly.state = FlyController.State.FLYING
		game.fly._update_animation(1.0 / 60.0)
		_assert(absf(game.fly.left_wing_pivot.rotation.z) > 0.01, "flight visibly flaps the left wing")
		_assert(is_equal_approx(game.fly.left_wing_pivot.rotation.z, -game.fly.right_wing_pivot.rotation.z), "wing stroke is symmetric")
	game.fly.rotation.y = 0.0
	game.fly.body_root.rotation.x = 0.0
	game.fly.velocity = Vector3.RIGHT * 4.0
	game.fly._face_velocity(0.2)
	_assert(absf(game.fly.rotation.y + PI / 2.0) < 0.1, "fly turns its head toward lateral movement")
	game.fly.velocity = Vector3.UP * 4.0
	game.fly._face_velocity(0.2)
	_assert(game.fly.body_root.rotation.x > 0.2, "fly pitches upward while climbing vertically")
	_assert(FlyController.IMPORTED_FLY_PATH.contains("fly_housefly_ccby"), "runtime uses the credited housefly")


func _test_fly_faces_its_actual_travel(game) -> void:
	game._start_round()
	game.fly.rotation.y = 0.0
	game.fly.state = FlyController.State.DODGING
	game.fly.velocity = Vector3.LEFT * 8.0
	game.fly._face_velocity(1.0 / 60.0, Vector3.RIGHT * (8.0 / 60.0))
	_assert((-game.fly.global_basis.z).dot(Vector3.RIGHT) > 0.95, "fast dodge faces actual travel within one frame")
	for _step in range(3):
		game.fly.velocity = Vector3.RIGHT * 8.0
		game.fly._face_velocity(1.0 / 60.0, Vector3.LEFT * (8.0 / 60.0))
	_assert((-game.fly.global_basis.z).dot(Vector3.LEFT) > 0.95, "fly turns to face a reversed path")


func _test_fly_uses_compact_difficulty_scale(game) -> void:
	_assert(is_equal_approx(FlyController.IMPORTED_FLY_SIZE, 0.08), "fly model is half its previous size")
	_assert(is_equal_approx(FlyController.BODY_RADIUS, 0.023), "fly collision radius is halved with its body")
	_assert(is_equal_approx(game.fly.architecture_shape.radius, FlyController.BODY_RADIUS), "architecture clearance uses the resized body")
	_assert((game.fly.shadow.mesh as QuadMesh).size.is_equal_approx(Vector2(0.08, 0.0575)), "fly shadow is halved with the smaller model")
	_assert(SwatterController.PADDLE_HALF_SIZE.x <= 0.361, "swatter strike area requires precise aim")


func _test_threat_telemetry(game) -> void:
	game._start_round()
	game.fly.set_sensors(1.0 / 60.0, {
		"loom_left": 0.70,
		"loom_right": 0.15,
		"lc4_left": 0.40,
		"lplc2_left": 0.30,
		"proximity": 0.8,
	})
	game.fly.turn_output = {"saccade_drive": 0.45, "straight_drive": 0.15}
	game.fly.selected_action = "FLIGHT_SACCADE"
	game.ui.update_hud(game.time_left, game.swings, game.escapes, 0.0, game.fly.get_activity(), game.fly.get_brain_mode(), game.fly.get_sensed_threat(), game.fly.get_circuit_response())
	_assert(game.ui.activity_values["loom_left"].text == "0.70", "telemetry shows sensed threat rather than merged neural activity")
	_assert(game.ui.activity_values["lc4"].text == "0.40", "telemetry distinguishes modeled angular speed")
	_assert(game.ui.activity_values["lplc2"].text == "0.30", "telemetry distinguishes modeled apparent size")
	_assert(game.ui.activity_values["turn_saccade"].text == "0.45", "telemetry shows the separate flight-turn response")
	_assert(game.ui.action_label.text.contains("FLIGHT SACCADE"), "telemetry names the selected escape action")
	_assert(game.ui.activity_values["dn_takeoff"].text != "", "telemetry shows descending-circuit response")
	game.ui.set_telemetry_visible(false)
	_assert(not game.ui.telemetry_panel.visible, "telemetry can be hidden for clean footage")
	game.ui.set_telemetry_visible(true)


func _test_split_screen_replay(game) -> void:
	game._start_round()
	game.replay_elapsed = 1.0
	game.fly.global_position = Vector3(-0.4, 1.7, 3.0)
	game._capture_replay_frame()
	game._finish_round(false)
	var frozen_pose: Transform3D = game.fly.global_transform
	var frozen_wing_phase: float = game.fly.wing_phase
	game._begin_replay()
	_assert(game.game_state == game.GameState.REPLAY, "completed round opens a synchronized replay")
	_assert(game.replay_view.visible, "two-camera replay overlay appears")
	_assert(game.replay_view.player_camera.get_viewport().world_3d == game.get_viewport().world_3d, "player replay camera shares the apartment world")
	game._step_replay(0.5)
	_assert(game.replay_view.timestamp_label.text != "", "recorded frames advance on a replay timeline")
	_assert(is_equal_approx(game.fly.left_wing_pivot.rotation.z, -game.fly.right_wing_pivot.rotation.z), "split-screen replay restores synchronized wing motion")
	game._end_replay()
	_assert(game.game_state == game.GameState.LOST, "closing replay restores the result")
	_assert(game.fly.global_transform.is_equal_approx(frozen_pose), "closing replay restores the live fly pose")
	_assert(is_equal_approx(game.fly.wing_phase, frozen_wing_phase), "closing replay restores the live wing phase")


func _test_charge_up_does_not_alert_fly(game) -> void:
	game._start_round()
	game.fly.state = FlyController.State.PERCHED
	game.fly.global_position = FlyController.PERCH_POINTS[0]
	game.fly.velocity = Vector3.ZERO
	game.fly.decision_time = 3.0
	game.player.position = Vector3(-0.80, 0.16, 3.90)
	game.player.movement_velocity = Vector3.ZERO
	game.swatter.reset_swatter()
	game.swatter.aim_position = game.fly.global_position
	game.swatter.global_position = game.fly.global_position + Vector3.UP * SwatterController.READY_OFFSET
	game.swatter.phase = SwatterController.Phase.WINDUP
	for _step in range(30):
		game.swatter._process(1.0 / 60.0)
		game._update_fly_sensors(1.0 / 60.0)
		game.fly._physics_process(1.0 / 60.0)
	_assert(game.swatter.get_charge() > 0.5, "swatter builds a substantial charge")
	_assert(game.fly.state == FlyController.State.PERCHED, "charging a swatter does not scare a stationary fly")
	_assert(float(game.fly.brain_output.get("escape_drive", 0.0)) < 0.05, "windup adds no neural escape drive")
	_assert(float(game.fly.sensed_threat.get("lc4_left", 0.0)) == 0.0, "windup adds no LC4 expansion signal")
	_assert(float(game.fly.sensed_threat.get("lplc2_left", 0.0)) == 0.0, "windup adds no LPLC2 looming size signal")


func _test_perched_fly_launches_before_impact(game) -> void:
	game._start_round()
	game.fly.state = FlyController.State.PERCHED
	game.fly.global_position = FlyController.PERCH_POINTS[0]
	game.fly.velocity = Vector3.ZERO
	game.fly.decision_time = 3.0
	game.player.position = Vector3(-0.80, 0.16, 3.90)
	game.player.movement_velocity = Vector3.ZERO
	game.swatter.reset_swatter()
	game.swatter.aim_position = game.fly.global_position
	game.swatter.global_position = game.fly.global_position + Vector3.UP * SwatterController.WINDUP_OFFSET
	game.swatter.phase = SwatterController.Phase.WINDUP
	game.swatter.charge = 0.55
	game.swatter.release_swing()
	for _step in range(5):
		game.swatter._process(1.0 / 60.0)
		game._update_fly_sensors(1.0 / 60.0)
		game.fly._physics_process(1.0 / 60.0)
	_assert(game.swatter.phase == SwatterController.Phase.STRIKE, "fly reacts before the paddle reaches impact")
	_assert(game.fly.state == FlyController.State.TAKEOFF, "descending swatter motion triggers a pre-impact escape")
	_assert(float(game.fly.sensed_threat.get("lc4_left", 0.0)) > 0.0, "strike generates angular expansion for LC4")
	_assert(float(game.fly.sensed_threat.get("lplc2_left", 0.0)) > 0.0, "strike generates apparent-size input for LPLC2")
	_assert(game.fly.velocity.length() > FlyController.CRUISE_SPEED * 2.5, "perched escape starts with an action-specific burst")
	_assert(game.fly.velocity.y > 0.0, "perched escape burst launches upward instead of into the surface")


func _test_fly_resolves_furniture_collision(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-3.15, 0.65, 1.26)
	_assert(game.fly.is_inside_apartment_obstacle(), "test starts inside the imported sofa")
	game.fly._resolve_apartment_obstacles()
	_assert(not game.fly.is_inside_apartment_obstacle(), "fly is pushed clear of imported furniture")


func _test_expanded_apartment_rooms(game) -> void:
	_assert(game.get_node_or_null("ModernApartment") != null, "imported Modern Apartment replaces procedural boxes")
	_assert(game.get_node_or_null("ApartmentFloor") == null, "old procedural apartment floor is removed")
	var floor := game.find_child("Plane_002_Marble 015_0", true, false) as MeshInstance3D
	_assert(floor != null, "imported floor mesh is present")
	if floor != null:
		var bounds := floor.global_transform * floor.mesh.get_aabb()
		_assert(bounds.size.x > 12.0, "the imported floor spans the open-plan apartment")
	for part in ["CouchSet_Wood049_0", "DiningTable_001_Wood049_0", "Bed_White1_0", "Plane_007_Wood049_0"]:
		_assert(game.find_child(part, true, false) != null, "%s is in the imported apartment" % part)
	var architecture := game.find_child("Plane_002_SprayedWallTexture_0", true, false) as MeshInstance3D
	_assert(architecture != null and architecture.get_child_count() > 0, "architectural mesh creates a real collision body")
	_assert(game.apartment_layout.solids.size() >= 8, "imported furniture shares a solid registry")
	for perch in FlyController.PERCH_POINTS:
		_assert(not game.apartment_layout.is_fly_inside_solid(perch, FlyController.BODY_RADIUS), "perch point clears imported furniture")


func _test_room_doorways_and_shared_collision(game) -> void:
	game._start_round()
	game.player.yaw = 0.0
	game.player.position = Vector3(5.16, 0.16, 3.14)
	game.player.move_for_test(Vector2(0.0, -1.0), 0.55)
	_assert(game.player.position.z < 2.4, "player can enter the office through its doorway")
	game.player.position = Vector3(8.20, 0.16, 3.14)
	game.player.move_for_test(Vector2(0.0, -1.0), 0.55)
	_assert(game.player.position.z > 2.72, "player cannot cut through a corridor partition")
	game.player.position = Vector3(10.90, 0.16, 3.14)
	game.player.move_for_test(Vector2(0.0, -1.0), 0.55)
	_assert(game.player.position.z < 2.4, "player can enter the bedroom through its doorway")
	game.fly.global_position = Vector3(8.20, 1.72, 3.14)
	game.fly.rotation = Vector3.ZERO
	game.fly.state = FlyController.State.DODGING
	game.fly.state_time = 0.0
	game.fly.desired_direction = Vector3.FORWARD
	game.fly.brain_output = {}
	game.fly._update_dodge(0.50)
	_assert(game.fly.global_position.z > 2.60, "fast fly cannot tunnel through a corridor partition: %s" % game.fly.global_position)


func _test_fly_uses_doorway_to_reach_kitchen(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-1.55, 1.55, 3.12)
	game.fly.velocity = Vector3.ZERO
	game.fly.state = FlyController.State.FLYING
	game.fly.state_time = 0.0
	game.fly.decision_time = 20.0
	game.fly.wander_target = Vector3(-4.35, 1.55, -0.72)
	game.fly.brain_output = {}
	var crossed_kitchen_door := false
	var clipped_wall := false
	for _step in range(420):
		game.fly._physics_process(1.0 / 60.0)
		crossed_kitchen_door = crossed_kitchen_door or game.apartment_layout.room_at(game.fly.global_position) == "kitchen"
		clipped_wall = clipped_wall or game.fly.is_inside_apartment_obstacle()
	_assert(crossed_kitchen_door, "fly reaches the open-plan kitchen")
	_assert(not clipped_wall, "fly clears imported walls while changing zones")


func _test_fly_uses_doorway_to_reach_bedroom(game) -> void:
	game._start_round()
	game.fly.global_position = Vector3(-0.45, 1.72, 3.15)
	game.fly.velocity = Vector3.ZERO
	game.fly.state = FlyController.State.FLYING
	game.fly.state_time = 0.0
	game.fly.decision_time = 22.0
	game.fly.wander_target = Vector3(12.25, 1.78, 1.72)
	game.fly.brain_output = {}
	var crossed_bedroom_door := false
	var clipped_wall := false
	for _step in range(960):
		game.fly._physics_process(1.0 / 60.0)
		crossed_bedroom_door = crossed_bedroom_door or game.apartment_layout.room_at(game.fly.global_position) == "bedroom"
		clipped_wall = clipped_wall or game.fly.is_inside_apartment_obstacle()
	_assert(crossed_bedroom_door, "fly routes from living room through corridor to imported bedroom: %s" % game.fly.global_position)
	_assert(not clipped_wall, "fly stays outside imported solids")


func _test_player_walks_and_respects_furniture(game) -> void:
	game.player.position = ApartmentLayout.PLAYER_START
	game.player.yaw = 0.0
	game.player.move_for_test(Vector2(0.0, -1.0), 0.18)
	_assert(game.player.position.z < ApartmentLayout.PLAYER_START.z - 0.15, "WASD moves player through the apartment")
	game.player.position = Vector3(0.10, 0.16, 2.75)
	var blocked_start: Vector3 = game.player.position
	game.player.move_for_test(Vector2(0.0, -1.0), 0.4)
	_assert(game.player.position.is_equal_approx(blocked_start), "player cannot walk through imported dining table")


func _test_swatter_uses_first_person_pose(game) -> void:
	game._start_round()
	game.swatter.reset_swatter()
	game.swatter._process(1.0 / 60.0)
	_assert(is_instance_valid(game.swatter.imported_model), "credited swatter glTF model is active")
	_assert(game.swatter.paddle_root.get_child_count() == 1, "only the imported swatter is drawn")
	var swatter_mesh := _find_first_mesh(game.swatter.imported_model)
	_assert(swatter_mesh != null, "imported swatter contains rendered geometry")
	if swatter_mesh == null:
		return
	var camera_local_position: Vector3 = game.camera.to_local(game.swatter.model_root.global_position)
	# The imported source's handle ends near this mesh-local position.
	var grip_local_position: Vector3 = game.camera.to_local(swatter_mesh.to_global(Vector3(-18.2, -4.25, -65.0)))
	var face_normal: Vector3 = game.swatter.model_root.global_basis.y.normalized()
	var camera_back: Vector3 = game.camera.global_basis.z.normalized()
	_assert(camera_local_position.x > 0.0, "swatter is carried on the player's right side")
	_assert(camera_local_position.y < 0.0, "swatter handle originates below the player's eye line")
	_assert(camera_local_position.z < 0.0, "swatter renders in front of the first-person camera")
	_assert(absf(face_normal.dot(camera_back)) > 0.80, "swatter paddle is rotated 90 degrees toward the camera")
	_assert(grip_local_position.x > camera_local_position.x + 0.12, "swatter grip sits naturally to the lower right of the paddle")
	_assert(grip_local_position.y < camera_local_position.y - 0.15, "swatter grip sits below the paddle")
	game.swatter.global_position = Vector3(-0.40, 1.60, 3.0)
	game.swatter.previous_height = 1.60
	_assert(game.swatter.contains_world_point(game.swatter.global_position), "first-person pose does not move the strike center")
	_assert(not game.swatter.contains_world_point(game.swatter.global_position + Vector3(0.40, 0.0, 0.0)), "first-person pose does not widen the strike area")


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


func _test_timeout(game) -> void:
	game._start_round()
	game.time_left = 0.0
	game._finish_round(false)
	_assert(game.game_state == game.GameState.LOST, "timeout loses the round")
	_assert(game.ui.result_panel.visible, "timeout displays the result panel")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
