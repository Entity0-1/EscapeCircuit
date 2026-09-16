class_name SwatterController
extends Node3D

signal impact(position: Vector3, intensity: float)
signal swing_started(intensity: float)

enum Phase { READY, WINDUP, STRIKE, IMPACT, RECOVER }

const READY_OFFSET := 0.86
const WINDUP_OFFSET := 1.46
# World-space strike area. It is intentionally smaller than the forgiving
# prototype so the player must lead and center a fast, realistically tiny fly.
const PADDLE_HALF_SIZE := Vector2(0.36, 0.28)
const SWEEP_VERTICAL_PADDING := 0.16
const VIEW_SCALE := 0.19
const VIEW_READY_OFFSET := Vector3(0.27, -0.11, -1.18)
const VIEW_WINDUP_OFFSET := Vector3(0.34, -0.06, -1.02)
const VIEW_STRIKE_OFFSET := Vector3(0.02, 0.02, -0.96)
# These camera-side poses only rotate the visual model; the world-space strike
# surface and its sweep remain fixed by the SwatterController node above.
const VIEW_READY_ROTATION := Vector3(PI / 2.0 - 0.10, -0.10, 0.34)
const VIEW_WINDUP_ROTATION := Vector3(PI / 2.0 - 0.24, -0.20, 0.12)
const VIEW_STRIKE_ROTATION := Vector3(PI / 2.0 + 0.12, 0.04, -0.06)
const SWATTER_MODEL := preload("res://assets/models/swatter_ccby/scene.gltf")

var phase := Phase.READY
var phase_time := 0.0
var charge := 0.0
var aim_position := Vector3(0.0, 2.2, 0.0)
var strike_position := Vector3.ZERO
var strike_origin_height := 3.0
var vertical_speed := 0.0
var previous_height := 3.0
var model_root: Node3D
var paddle_root: Node3D
var imported_model: Node3D
var view_camera: Camera3D


func _ready() -> void:
	_build_model()
	global_position = aim_position + Vector3.UP * READY_OFFSET
	strike_position = aim_position


func set_aim(world_point: Vector3) -> void:
	aim_position = world_point


func bind_view_camera(value: Camera3D) -> void:
	view_camera = value
	if model_root and is_instance_valid(view_camera):
		model_root.global_transform = _get_view_transform()


func begin_windup() -> void:
	if phase != Phase.READY:
		return
	phase = Phase.WINDUP
	phase_time = 0.0
	charge = 0.0


func release_swing() -> void:
	if phase != Phase.WINDUP:
		return
	phase = Phase.STRIKE
	phase_time = 0.0
	charge = maxf(charge, 0.18)
	strike_position = aim_position
	strike_origin_height = global_position.y
	emit_signal("swing_started", lerpf(0.55, 1.0, charge))


func reset_swatter() -> void:
	phase = Phase.READY
	phase_time = 0.0
	charge = 0.0
	vertical_speed = 0.0
	global_position = aim_position + Vector3.UP * READY_OFFSET
	strike_position = aim_position
	strike_origin_height = global_position.y
	if model_root and is_instance_valid(view_camera):
		model_root.global_transform = _get_view_transform()


func is_dangerous() -> bool:
	return phase == Phase.STRIKE and vertical_speed < -2.0


func is_winding_up() -> bool:
	return phase == Phase.WINDUP


func get_charge() -> float:
	return charge


func get_downward_speed() -> float:
	return maxf(0.0, -vertical_speed)


func contains_world_point(point: Vector3) -> bool:
	var local_point := to_local(point)
	var swept_min_y := minf(global_position.y, previous_height) - SWEEP_VERTICAL_PADDING
	var swept_max_y := maxf(global_position.y, previous_height) + SWEEP_VERTICAL_PADDING
	return (
		absf(local_point.x) <= PADDLE_HALF_SIZE.x
		and absf(local_point.z) <= PADDLE_HALF_SIZE.y
		and point.y >= swept_min_y
		and point.y <= swept_max_y
	)


func spatial_distance_to(point: Vector3) -> float:
	return global_position.distance_to(point)


func _process(delta: float) -> void:
	phase_time += delta
	var follow_alpha := 1.0 - exp(-15.0 * delta)
	var follow_position := strike_position if phase in [Phase.STRIKE, Phase.IMPACT] else aim_position
	global_position.x = lerpf(global_position.x, follow_position.x, follow_alpha)
	global_position.z = lerpf(global_position.z, follow_position.z, follow_alpha)
	previous_height = global_position.y

	match phase:
		Phase.READY:
			var ready_height := aim_position.y + READY_OFFSET
			global_position.y = lerpf(global_position.y, ready_height, 1.0 - exp(-10.0 * delta))
		Phase.WINDUP:
			charge = clampf(charge + delta * 1.35, 0.0, 1.0)
			var target_height := aim_position.y + WINDUP_OFFSET + charge * 0.34
			global_position.y = lerpf(global_position.y, target_height, 1.0 - exp(-9.0 * delta))
		Phase.STRIKE:
			var strike_duration := lerpf(0.18, 0.095, charge)
			var progress := clampf(phase_time / strike_duration, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - progress, 3.0)
			global_position.y = lerpf(strike_origin_height, strike_position.y, eased)
			if progress >= 1.0:
				phase = Phase.IMPACT
				phase_time = 0.0
				emit_signal("impact", global_position, lerpf(0.55, 1.0, charge))
		Phase.IMPACT:
			global_position.y = strike_position.y
			if phase_time > 0.075:
				phase = Phase.RECOVER
				phase_time = 0.0
		Phase.RECOVER:
			var recover_progress := clampf(phase_time / 0.42, 0.0, 1.0)
			var eased_recover := 1.0 - pow(1.0 - recover_progress, 2.0)
			global_position.y = lerpf(strike_position.y, aim_position.y + READY_OFFSET, eased_recover)
			if recover_progress >= 1.0:
				phase = Phase.READY
				phase_time = 0.0
				charge = 0.0

	vertical_speed = (global_position.y - previous_height) / maxf(delta, 0.0001)
	_update_view_model(delta)


func _build_model() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.top_level = true
	add_child(model_root)

	paddle_root = Node3D.new()
	paddle_root.name = "Paddle"
	paddle_root.rotation.y = 0.34
	model_root.add_child(paddle_root)

	imported_model = SWATTER_MODEL.instantiate() as Node3D
	imported_model.name = "FlySwatterArt"
	paddle_root.add_child(imported_model)
	# The source mesh is upright in XY after its glTF root transform. Center its
	# paddle on the old visual origin and run the handle along local +Z, which
	# the unchanged first-person pose points down toward the player's hand.
	imported_model.transform = Transform3D(
		Basis(Vector3(0.065, 0.0, 0.0), Vector3(0.0, 0.0, -0.040), Vector3(0.0, 0.040, 0.0)),
		Vector3(-0.276, -0.728, -0.160)
	)


func _update_view_model(delta: float) -> void:
	if not is_instance_valid(view_camera):
		return
	var target := _get_view_transform()
	var follow_alpha := 1.0 - exp(-18.0 * delta)
	model_root.global_transform = model_root.global_transform.interpolate_with(target, follow_alpha)


func _get_view_transform() -> Transform3D:
	var offset := VIEW_READY_OFFSET
	var rotation_value := VIEW_READY_ROTATION
	match phase:
		Phase.WINDUP:
			var pose_amount := smoothstep(0.0, 1.0, charge)
			offset = VIEW_READY_OFFSET.lerp(VIEW_WINDUP_OFFSET, pose_amount)
			rotation_value = VIEW_READY_ROTATION.lerp(VIEW_WINDUP_ROTATION, pose_amount)
		Phase.STRIKE:
			var duration := lerpf(0.18, 0.095, charge)
			var progress := clampf(phase_time / duration, 0.0, 1.0)
			var pose_amount := 1.0 - pow(1.0 - progress, 3.0)
			offset = VIEW_WINDUP_OFFSET.lerp(VIEW_STRIKE_OFFSET, pose_amount)
			rotation_value = VIEW_WINDUP_ROTATION.lerp(VIEW_STRIKE_ROTATION, pose_amount)
		Phase.IMPACT:
			offset = VIEW_STRIKE_OFFSET
			rotation_value = VIEW_STRIKE_ROTATION
		Phase.RECOVER:
			var progress := clampf(phase_time / 0.42, 0.0, 1.0)
			var pose_amount := 1.0 - pow(1.0 - progress, 2.0)
			offset = VIEW_STRIKE_OFFSET.lerp(VIEW_READY_OFFSET, pose_amount)
			rotation_value = VIEW_STRIKE_ROTATION.lerp(VIEW_READY_ROTATION, pose_amount)
	var local_basis := Basis.from_euler(rotation_value).scaled(Vector3.ONE * VIEW_SCALE)
	return view_camera.global_transform * Transform3D(local_basis, offset)
