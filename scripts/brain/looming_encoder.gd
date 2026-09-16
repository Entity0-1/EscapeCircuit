class_name LoomingEncoder
extends RefCounted

## Game-world geometry becomes two modeled visual features. Tuning constants are
## engineering choices, not parameters measured from this MaleCNS connectome.

const SIZE_PEAK_RADIANS := 42.0 * PI / 180.0
const SIZE_LOG_WIDTH := 0.52
const SPEED_SATURATION_RADIANS := 5.0
const MIN_EXPANSION_RADIANS := 0.08


static func encode(radius: float, distance: float, closing_speed: float) -> Dictionary:
	var safe_radius := maxf(radius, 0.001)
	var safe_distance := maxf(distance, 0.05)
	var angular_size := 2.0 * atan(safe_radius / safe_distance)
	var angular_speed := 2.0 * safe_radius * maxf(closing_speed, 0.0) / (
		safe_distance * safe_distance + safe_radius * safe_radius
	)
	# A stationary object may occupy the visual field, but is not looming.
	var looming := angular_speed > MIN_EXPANSION_RADIANS
	var log_offset := log(angular_size / SIZE_PEAK_RADIANS) / SIZE_LOG_WIDTH
	return {
		"angular_size": angular_size,
		"angular_speed": angular_speed,
		"lplc2": exp(-0.5 * log_offset * log_offset) if looming else 0.0,
		"lc4": clampf(angular_speed / SPEED_SATURATION_RADIANS, 0.0, 1.0) if looming else 0.0,
	}
