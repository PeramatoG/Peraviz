extends RefCounted
class_name BeamAppearanceProfile

const SURFACE_FALLOFF_BALANCED := 0
const SURFACE_FALLOFF_PHYSICAL := 1
const BALANCED_SURFACE_ATTENUATION_EXPONENT: float = 1.0
const PHYSICAL_SURFACE_ATTENUATION_EXPONENT: float = 2.0

const _BASE_PROFILES := {
	"spot": {"beam_type": "Spot", "projected": true, "shape": "circle", "profile_source": "gdtf_type_default", "core_radius_ratio": 0.78, "field_radius_ratio": 1.0, "edge_softness": 0.06, "radial_exponent": 0.85, "center_intensity_gain": 1.15, "edge_intensity_floor": 0.08, "extinction_coefficient": 0.010, "longitudinal_exponent": 1.0, "near_visibility": 1.0, "far_visibility_floor": 0.12},
	"rectangle": {"beam_type": "Rectangle", "projected": true, "shape": "rectangle", "profile_source": "gdtf_type_default", "core_radius_ratio": 0.82, "field_radius_ratio": 1.0, "edge_softness": 0.04, "radial_exponent": 0.8, "center_intensity_gain": 1.12, "edge_intensity_floor": 0.08, "extinction_coefficient": 0.010, "longitudinal_exponent": 1.0, "near_visibility": 1.0, "far_visibility_floor": 0.12},
	"pc": {"beam_type": "PC", "projected": true, "shape": "circle", "profile_source": "gdtf_type_default", "core_radius_ratio": 0.56, "field_radius_ratio": 1.0, "edge_softness": 0.28, "radial_exponent": 1.35, "center_intensity_gain": 1.35, "edge_intensity_floor": 0.07, "extinction_coefficient": 0.009, "longitudinal_exponent": 1.0, "near_visibility": 1.0, "far_visibility_floor": 0.14},
	"fresnel": {"beam_type": "Fresnel", "projected": true, "shape": "circle", "profile_source": "gdtf_type_default", "core_radius_ratio": 0.50, "field_radius_ratio": 1.0, "edge_softness": 0.36, "radial_exponent": 1.55, "center_intensity_gain": 1.42, "edge_intensity_floor": 0.08, "extinction_coefficient": 0.0085, "longitudinal_exponent": 1.0, "near_visibility": 1.0, "far_visibility_floor": 0.15},
	"wash": {"beam_type": "Wash", "projected": true, "shape": "circle", "profile_source": "gdtf_type_default", "core_radius_ratio": 0.42, "field_radius_ratio": 1.0, "edge_softness": 0.46, "radial_exponent": 1.75, "center_intensity_gain": 1.55, "edge_intensity_floor": 0.10, "extinction_coefficient": 0.008, "longitudinal_exponent": 1.0, "near_visibility": 1.0, "far_visibility_floor": 0.16},
	"none": {"beam_type": "None", "projected": false, "shape": "no_projected_beam", "profile_source": "gdtf_type_default"},
	"glow": {"beam_type": "Glow", "projected": false, "shape": "no_projected_beam", "profile_source": "gdtf_type_default"},
}

static func resolve(params: Dictionary, visual_settings: Dictionary = {}) -> Dictionary:
	var key: String = str(params.get("beam_type", "Wash")).strip_edges().to_lower()
	var profile: Dictionary = (_BASE_PROFILES.get(key, _BASE_PROFILES["spot"]) as Dictionary).duplicate(true)
	if not _BASE_PROFILES.has(key):
		profile["beam_type"] = "Spot"
		profile["profile_source"] = "unknown_beam_type_conservative_spot_fallback"
		profile["diagnostic"] = "Unknown BeamType uses the hard-edge Spot appearance fallback."
	if not bool(profile.get("projected", true)):
		return profile
	var beam_angle: float = _safe_positive(float(params.get("beam_angle", params.get("beam_angle_deg", 0.0))), 0.0)
	var field_angle: float = _safe_positive(float(params.get("field_angle", params.get("field_angle_deg", 0.0))), 0.0)
	if profile.get("shape", "circle") == "circle" and key in ["wash", "pc", "fresnel"] and field_angle > beam_angle and beam_angle > 0.0:
		var ratio: float = clamp(tan(deg_to_rad(field_angle * 0.5)) / max(tan(deg_to_rad(beam_angle * 0.5)), 0.0001), 1.0, 3.0)
		profile["field_radius_ratio"] = clamp(1.0 / ratio, 0.62, 1.0)
		profile["edge_softness"] = clamp(float(profile["edge_softness"]) * (1.0 + min(ratio - 1.0, 1.0) * 0.35), 0.02, 0.85)
		profile["profile_source"] = str(profile["profile_source"]) + "+field_angle_visual_envelope"
	var extinction_multiplier: float = max(float(visual_settings.get("beam_extinction_multiplier", params.get("beam_extinction_multiplier", 1.0))), 0.0)
	var far_multiplier: float = max(float(visual_settings.get("beam_far_visibility_multiplier", params.get("beam_far_visibility_multiplier", 1.0))), 0.0)
	profile["extinction_coefficient"] = max(float(profile.get("extinction_coefficient", 0.0)) * extinction_multiplier, 0.0)
	profile["far_visibility_floor"] = clamp(float(profile.get("far_visibility_floor", 0.12)) * far_multiplier, 0.0, 0.45)
	var mode: int = int(visual_settings.get("surface_light_falloff_mode", params.get("surface_light_falloff_mode", SURFACE_FALLOFF_BALANCED)))
	profile["surface_attenuation_mode"] = mode
	profile["surface_attenuation_exponent"] = PHYSICAL_SURFACE_ATTENUATION_EXPONENT if mode == SURFACE_FALLOFF_PHYSICAL else BALANCED_SURFACE_ATTENUATION_EXPONENT
	return sanitize(profile)

static func sanitize(profile: Dictionary) -> Dictionary:
	var sanitized: Dictionary = profile.duplicate(true)
	for key in ["core_radius_ratio", "field_radius_ratio", "edge_softness", "radial_exponent", "center_intensity_gain", "edge_intensity_floor", "extinction_coefficient", "longitudinal_exponent", "near_visibility", "far_visibility_floor"]:
		sanitized[key] = _safe_positive(float(sanitized.get(key, 0.0)), 0.0)
	sanitized["core_radius_ratio"] = clamp(float(sanitized["core_radius_ratio"]), 0.0, 0.98)
	sanitized["field_radius_ratio"] = clamp(float(sanitized["field_radius_ratio"]), float(sanitized["core_radius_ratio"]) + 0.01, 1.0)
	sanitized["edge_softness"] = clamp(float(sanitized["edge_softness"]), 0.01, 0.9)
	sanitized["radial_exponent"] = max(float(sanitized["radial_exponent"]), 0.05)
	sanitized["center_intensity_gain"] = max(float(sanitized["center_intensity_gain"]), 1.0)
	sanitized["edge_intensity_floor"] = clamp(float(sanitized["edge_intensity_floor"]), 0.0, 0.5)
	sanitized["far_visibility_floor"] = clamp(float(sanitized["far_visibility_floor"]), 0.0, 0.5)
	return sanitized

static func circular_normalized_radius(local_x: float, local_z: float, local_radius: float) -> float:
	return length(Vector2(local_x, local_z)) / max(local_radius, 0.0001)

static func rectangular_normalized_radius(local_x: float, local_z: float, half_width: float, half_height: float) -> float:
	return max(abs(local_x) / max(half_width, 0.0001), abs(local_z) / max(half_height, 0.0001))

static func radial_energy(profile: Dictionary, normalized_radius: float) -> float:
	var p: Dictionary = sanitize(profile)
	var r: float = clamp(normalized_radius, 0.0, 1.0)
	var core: float = float(p["core_radius_ratio"])
	var field: float = max(float(p["field_radius_ratio"]), core + 0.01)
	var t: float = smoothstep(core, field, r)
	var envelope: float = mix(1.0, float(p["edge_intensity_floor"]), t)
	if r > field:
		envelope *= 1.0 - smoothstep(field, 1.0, r)
	return max(pow(clamp(envelope, 0.0, 1.0), float(p["radial_exponent"])) * float(p["center_intensity_gain"]), 0.0)

static func longitudinal_visibility(profile: Dictionary, distance_m: float) -> float:
	var p: Dictionary = sanitize(profile)
	var d: float = max(distance_m, 0.0)
	var transmittance: float = exp(-max(float(p["extinction_coefficient"]), 0.0) * d)
	var shaped: float = pow(clamp(transmittance, 0.0, 1.0), max(float(p["longitudinal_exponent"]), 0.05))
	return clamp(max(shaped * float(p["near_visibility"]), float(p["far_visibility_floor"])), 0.0, 1.0)

static func surface_attenuation_exponent(mode: int) -> float:
	return PHYSICAL_SURFACE_ATTENUATION_EXPONENT if mode == SURFACE_FALLOFF_PHYSICAL else BALANCED_SURFACE_ATTENUATION_EXPONENT

static func _safe_positive(value: float, fallback: float) -> float:
	return value if is_finite(value) and value >= 0.0 else fallback
