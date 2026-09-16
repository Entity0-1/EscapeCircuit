class_name ApartmentLayout
extends RefCounted

## Walkable bounds, furniture footprints, perch surfaces, and fly route hints for
## Visthétique's Modern Apartment. Architectural collision comes from its mesh.

const FLY_MIN := Vector3(-6.18, 0.38, -1.14)
const FLY_MAX := Vector3(13.94, 2.54, 4.04)
const PLAYER_MIN := Vector2(-6.12, -1.10)
const PLAYER_MAX := Vector2(13.98, 4.00)
const PLAYER_START := Vector3(-0.80, 0.16, 3.15)
const FLY_START := Vector3(-0.45, 1.78, 2.82)
const PERCH_POINTS := [
	Vector3(1.05, 0.97, 1.05), # Dining table
	Vector3(-3.35, 1.06, 3.70), # Sofa back
	Vector3(-4.65, 1.02, -0.77), # Kitchen counter
	Vector3(12.25, 1.12, 0.32), # Bedroom bed
	Vector3(4.90, 1.40, -0.56), # Office desk
]

var solids: Array[AABB] = []
var solid_names: Array[String] = []


func register_solid(node_name: String, center: Vector3, size: Vector3) -> void:
	solids.append(AABB(center - size * 0.5, size))
	solid_names.append(node_name)


func is_player_blocked(candidate: Vector3, radius: float) -> bool:
	var point := Vector2(candidate.x, candidate.z)
	for solid in solids:
		if solid.position.y > 1.75 or solid.end.y < 0.30:
			continue
		var footprint := Rect2(
			Vector2(solid.position.x, solid.position.z),
			Vector2(solid.size.x, solid.size.z)
		)
		if footprint.grow(radius).has_point(point):
			return true
	return false


func is_fly_inside_solid(point: Vector3, radius: float) -> bool:
	for solid in solids:
		if solid.grow(radius).has_point(point):
			return true
	return false


func room_at(point: Vector3) -> String:
	if point.x < -1.65 and point.z < 0.15:
		return "kitchen"
	if point.x < 1.60:
		return "living"
	if point.z >= 2.62:
		return "hall"
	if point.x < 6.40:
		return "office"
	if point.x > 9.35:
		return "bedroom"
	return "hall"


func route_point(from_point: Vector3, destination: Vector3) -> Vector3:
	var current_room := room_at(from_point)
	var destination_room := room_at(destination)
	if current_room == destination_room:
		return destination
	var altitude := clampf(from_point.y, 0.78, 2.35)
	# The living/kitchen zone is open-plan. The other rooms connect via the
	# long corridor behind them; these waypoints keep cruising out of partitions.
	if current_room == "kitchen" or destination_room == "kitchen":
		if current_room == "kitchen" and destination_room == "living":
			return Vector3(-1.62, altitude, 0.50)
		if current_room == "living" and destination_room == "kitchen":
			if from_point.x > -1.55 and from_point.z > 0.50:
				return Vector3(-1.62, altitude, 3.20)
			return Vector3(-2.20, altitude, 0.10)
	if current_room == "office":
		return Vector3(5.16, altitude, 2.95)
	if destination_room == "office" and current_room == "hall":
		if absf(from_point.x - 5.16) > 0.46:
			return Vector3(5.16, altitude, 3.15)
		return Vector3(5.16, altitude, 2.24)
	if current_room == "living" or current_room == "kitchen":
		return Vector3(1.85, altitude, 3.22)
	if destination_room == "living" or destination_room == "kitchen":
		return Vector3(1.15, altitude, 3.22)
	if current_room == "bedroom":
		return Vector3(10.90, altitude, 2.95)
	if destination_room == "bedroom":
		if absf(from_point.x - 10.90) > 0.46:
			return Vector3(10.90, altitude, 3.22)
		return Vector3(10.90, altitude, 2.16)
	return destination


func random_air_point(rng: RandomNumberGenerator) -> Vector3:
	for _attempt in range(40):
		var choice := rng.randf()
		var point := Vector3.ZERO
		if choice < 0.48:
			point = Vector3(rng.randf_range(-5.8, 1.2), rng.randf_range(0.75, 2.30), rng.randf_range(0.30, 3.80))
		elif choice < 0.67:
			point = Vector3(rng.randf_range(-5.7, -2.0), rng.randf_range(0.85, 2.25), rng.randf_range(-1.00, -0.32))
		elif choice < 0.82:
			point = Vector3(rng.randf_range(2.0, 5.85), rng.randf_range(0.75, 2.30), rng.randf_range(-0.20, 1.95))
		elif choice < 0.92:
			point = Vector3(rng.randf_range(9.8, 13.4), rng.randf_range(1.18, 2.30), rng.randf_range(-0.70, 2.10))
		else:
			point = Vector3(rng.randf_range(2.0, 12.8), rng.randf_range(0.75, 2.30), rng.randf_range(2.95, 3.75))
		if not is_fly_inside_solid(point, 0.12):
			return point
	return FLY_START
