extends RefCounted
class_name BeamGeometryCalculator

const DEFAULT_VISUAL_LENGTH_M: float = 75.0
const MIN_VISUAL_LENGTH_M: float = 1.0
const MAX_VISUAL_LENGTH_M: float = 150.0
const SAFE_MAX_ANGLE_DEG: float = 179.0
const RESOURCE_GUARD_RADIUS_M: float = 250.0
const SAFE_FALLBACK_RADIUS_M: float = 0.03
const CONTRADICTION_RATIO: float = 20.0

static func clamp_visual_length(length_m: float) -> float:
	if not is_finite(length_m):
		return DEFAULT_VISUAL_LENGTH_M
	return clamp(length_m, MIN_VISUAL_LENGTH_M, MAX_VISUAL_LENGTH_M)

static func far_radius_for_full_angle(near_radius_m: float, full_angle_deg: float, visual_length_m: float) -> Dictionary:
	var near_radius: float = max(near_radius_m, 0.001)
	var length_m: float = clamp_visual_length(visual_length_m)
	var angle_deg: float = full_angle_deg
	var safety_guard_reached: bool = false
	if not is_finite(angle_deg) or angle_deg < 0.0 or angle_deg >= 180.0:
		angle_deg = clamp(angle_deg if is_finite(angle_deg) else 0.0, 0.0, SAFE_MAX_ANGLE_DEG)
		safety_guard_reached = true
	var far_radius: float = near_radius + tan(deg_to_rad(angle_deg * 0.5)) * length_m
	if not is_finite(far_radius) or far_radius < near_radius:
		far_radius = near_radius
		safety_guard_reached = true
	if far_radius > RESOURCE_GUARD_RADIUS_M:
		far_radius = RESOURCE_GUARD_RADIUS_M
		safety_guard_reached = true
	return {"near_radius_m": near_radius, "near_diameter_m": near_radius * 2.0, "full_angle_deg": angle_deg, "visual_length_m": length_m, "far_radius_m": far_radius, "safety_guard_reached": safety_guard_reached}

static func select_render_near_radius(photometric: Dictionary, measured_radius_m: float) -> Dictionary:
	var official_raw: float = float(photometric.get("official_beam_radius_m", photometric.get("beam_radius", 0.0)))
	var official_valid: bool = is_finite(official_raw) and official_raw > 0.0
	var official_explicit: bool = bool(photometric.get("beam_radius_from_gdtf", false)) and official_valid
	var measured: float = measured_radius_m if is_finite(measured_radius_m) and measured_radius_m > 0.0 else 0.0
	var mismatch_ratio: float = 1.0
	if official_valid and measured > 0.0:
		mismatch_ratio = max(official_raw, measured) / max(min(official_raw, measured), 0.000001)
	var selected: float = SAFE_FALLBACK_RADIUS_M
	var source: String = "safe_fallback"
	var diagnostic: String = ""
	if official_explicit and mismatch_ratio < CONTRADICTION_RATIO:
		selected = official_raw
		source = "official_beam_radius"
	elif measured > 0.0:
		selected = measured
		source = "measured_model_aperture"
		if official_explicit:
			diagnostic = "Explicit GDTF BeamRadius contradicts exact Beam-owned model aperture; preserving official value and rendering measured aperture."
	elif official_explicit:
		selected = official_raw
		source = "official_beam_radius_no_model"
	return {"official_beam_radius_m": official_raw if official_valid else 0.0, "official_beam_radius_explicit": official_explicit, "official_beam_radius_valid": official_valid, "measured_model_aperture_radius_m": measured, "render_near_radius_m": max(selected, 0.001), "render_near_diameter_m": max(selected, 0.001) * 2.0, "render_near_radius_source": source, "radius_mismatch_ratio": mismatch_ratio, "diagnostic": diagnostic, "likely_1000x_mismatch": mismatch_ratio >= 900.0 and mismatch_ratio <= 1100.0}
