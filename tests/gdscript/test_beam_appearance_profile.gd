extends SceneTree

const BeamAppearanceProfileScript = preload("res://scripts/beam_appearance_profile.gd")
const BeamGeometryCalculatorScript = preload("res://scripts/beam_geometry_calculator.gd")

var failures := 0

func _init() -> void:
	_run()
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	_check(abs(actual - expected) <= tolerance, "%s (actual %.6f expected %.6f)" % [message, actual, expected])

func _run() -> void:
	var spot: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "Spot", "beam_angle": 25.0}, {})
	var rectangle: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "Rectangle", "beam_angle": 25.0, "field_angle": 60.0}, {})
	var wash: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "Wash", "beam_angle": 25.0}, {})
	var pc: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "PC", "beam_angle": 25.0}, {})
	var fresnel: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "Fresnel", "beam_angle": 25.0}, {})
	_check(bool(spot.get("projected", false)), "Spot should project a beam")
	_check(str(rectangle.get("shape", "")) == "rectangle", "Rectangle should use rectangular profile")
	_check(float(spot.get("edge_softness", 1.0)) < float(pc.get("edge_softness", 0.0)), "PC should be softer than Spot")
	_check(float(spot.get("edge_softness", 1.0)) < float(fresnel.get("edge_softness", 0.0)), "Fresnel should be softer than Spot")
	_check(float(spot.get("edge_softness", 1.0)) < float(wash.get("edge_softness", 0.0)), "Wash should be softer than Spot")
	_check(not bool(BeamAppearanceProfileScript.resolve({"beam_type": "None"}, {}).get("projected", true)), "None should not project a beam")
	_check(not bool(BeamAppearanceProfileScript.resolve({"beam_type": "Glow"}, {}).get("projected", true)), "Glow should not project a beam")
	var unknown: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "FixtureNameDoesNotMatter"}, {})
	_check(str(unknown.get("profile_source", "")).contains("fallback"), "Unknown BeamType should use documented fallback")
	_check_close(BeamAppearanceProfileScript.circular_normalized_radius(0.0, 0.0, 2.0), 0.0, 0.0001, "Circular axis normalization should be zero")
	_check_close(BeamAppearanceProfileScript.circular_normalized_radius(2.0, 0.0, 2.0), 1.0, 0.0001, "Circular edge normalization should be one")
	_check_close(BeamAppearanceProfileScript.rectangular_normalized_radius(2.0, 0.0, 2.0, 1.0), 1.0, 0.0001, "Rectangle X edge should normalize to one")
	_check_close(BeamAppearanceProfileScript.rectangular_normalized_radius(0.0, 1.0, 2.0, 1.0), 1.0, 0.0001, "Rectangle Z edge should normalize to one")
	for profile in [spot, rectangle, wash, pc, fresnel]:
		var previous := INF
		for step in range(0, 21):
			var energy: float = BeamAppearanceProfileScript.radial_energy(profile, float(step) / 20.0)
			_check(is_finite(energy) and energy >= 0.0, "Radial energy should be finite and non-negative")
			_check(energy <= previous + 0.0001, "Radial energy should be monotonic")
			previous = energy
		_check(BeamAppearanceProfileScript.radial_energy(profile, 0.0) > BeamAppearanceProfileScript.radial_energy(profile, 1.0), "Center should be brighter than margin")
	var soft_field: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "Wash", "beam_angle": 20.0, "field_angle": 40.0}, {})
	_check(float(soft_field.get("field_radius_ratio", 1.0)) < float(wash.get("field_radius_ratio", 1.0)), "Larger FieldAngle may widen soft envelope without geometry changes")
	_check_close(float(BeamGeometryCalculatorScript.far_radius_for_full_angle(0.05, 25.0, 75.0).get("far_radius_m", 0.0)), 16.6770997, 0.0001, "Appearance must not alter 75 m geometry")
	_check_close(float(BeamGeometryCalculatorScript.far_radius_for_full_angle(0.05, 25.0, 100.0).get("far_radius_m", 0.0)), 22.2194663, 0.0001, "Appearance must not alter 100 m geometry")
	_check(str(BeamAppearanceProfileScript.resolve({"beam_type": "Spot", "beam_angle": 20.0, "field_angle": 60.0}, {}).get("profile_source", "")) == "gdtf_type_default", "Spot should ignore FieldAngle for appearance baseline")
	for invalid in [NAN, INF, -1.0]:
		var safe: Dictionary = BeamAppearanceProfileScript.resolve({"beam_type": "Wash", "beam_angle": 20.0, "field_angle": invalid}, {})
		_check(is_finite(float(safe.get("edge_softness", 0.0))), "Invalid FieldAngle should not create NaN")
	var zero_extinction := {"extinction_coefficient": 0.0, "longitudinal_exponent": 1.0, "near_visibility": 1.0, "far_visibility_floor": 0.0, "core_radius_ratio": 0.5, "field_radius_ratio": 1.0, "edge_softness": 0.2, "radial_exponent": 1.0, "center_intensity_gain": 1.0, "edge_intensity_floor": 0.1}
	_check_close(BeamAppearanceProfileScript.longitudinal_visibility(zero_extinction, 100.0), 1.0, 0.0001, "Zero extinction should produce no exponential loss")
	_check_close(BeamAppearanceProfileScript.longitudinal_visibility(wash, 0.0), 1.0, 0.0001, "Near visibility should start at one")
	_check(BeamAppearanceProfileScript.longitudinal_visibility(wash, 75.0) >= float(wash.get("far_visibility_floor", 0.0)), "75 m beam should remain readable")
	_check(BeamAppearanceProfileScript.longitudinal_visibility(wash, 100.0) >= float(wash.get("far_visibility_floor", 0.0)), "100 m beam should remain readable")
	_check(BeamAppearanceProfileScript.longitudinal_visibility(wash, 100.0) <= BeamAppearanceProfileScript.longitudinal_visibility(wash, 50.0) + 0.0001, "Far end should not brighten")
	var hard_edge: Dictionary = spot.duplicate(true)
	var soft_edge: Dictionary = spot.duplicate(true)
	hard_edge["edge_softness"] = 0.04
	soft_edge["edge_softness"] = 0.46
	_check(abs(BeamAppearanceProfileScript.radial_energy(hard_edge, 0.70) - BeamAppearanceProfileScript.radial_energy(soft_edge, 0.70)) > 0.01, "Changing only edge_softness should change sampled radial output")
	_check(BeamAppearanceProfileScript.radial_energy(spot, 0.96) != BeamAppearanceProfileScript.radial_energy(wash, 0.96), "Visibility floors should not alias Spot and Wash edge samples")
	_check_close(BeamAppearanceProfileScript.surface_attenuation_exponent(0), 1.0, 0.0001, "Balanced surface falloff should use practical exponent")
	_check_close(BeamAppearanceProfileScript.surface_attenuation_exponent(1), 2.0, 0.0001, "Physical surface falloff should use inverse-square exponent")
