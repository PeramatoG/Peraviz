extends RefCounted

# Generated GDTF → native selected-mode Zoom → shared state. The audited receiver
# is defined 10 m from the lens, perpendicular to the resolved optical centerline.
static func run(owner: SceneTree) -> void:
	await owner._load(owner._generate(false, true, false, true))
	owner.dmx.resize(512)
	owner.dmx.fill(0)
	for level in [64, 128, 255]:
		for fixture in range(20):
			owner.dmx[fixture * 16] = 200
			owner.dmx[fixture * 16 + 3] = level
			owner.dmx[fixture * 16 + 4] = 255
		await owner._apply()
		var handle = owner.adapter._outputs[0].lights[0]
		var profile: Dictionary = owner.adapter._binding_records[0].beam_optical_profile
		var state: RefCounted = handle.projection
		owner.test.check(profile.beam_angle_explicit and profile.field_angle_explicit and state.radial_profile.anchored, "Independent authored pair survives native compilation")
		var current: float = owner.adapter._native.physical_values(0)[9]
		owner.test.check(is_equal_approx(state.source_full_angle_deg, current), "Physical projector consumes grouped native Zoom without stale optics")
		var expected: float = float(level) / 255.0 * 40.0
		owner.test.check(is_equal_approx(current, expected), "Selected-mode native Zoom preserves PhysicalFrom/To mapping")
		var ratio: float = tan(deg_to_rad(float(profile.field_angle) * 0.5)) / tan(deg_to_rad(float(profile.beam_angle) * 0.5))
		var beam_diameter: float = 20.0 * tan(deg_to_rad(current * 0.5))
		var field_diameter: float = 20.0 * tan(deg_to_rad(state.resolved_field_angle_deg * 0.5))
		var support: float = 20.0 * tan(deg_to_rad(state.half_angle_deg))
		owner.test.check(is_equal_approx(field_diameter, beam_diameter * ratio), "Native Zoom retains authored field tangent ratio")
		owner.test.check(is_equal_approx(support, field_diameter * 1.5), "Soft visual support is a 1.5 field-tangent approximation, independent of source angles")
		print("OPTICAL_SCALE_AUDIT ", JSON.stringify({"canonical_output": owner.adapter._outputs[0].canonical_id,
			"beam_type":profile.beam_type,"beam_type_explicit":profile.beam_type_explicit,
			"base_beam_angle":profile.beam_angle,"current_beam_angle":current,
			"authored_field_angle":profile.field_angle,"field_explicit":profile.field_angle_explicit,
			"dynamic_field_angle":state.resolved_field_angle_deg,"lens_world_origin":handle.light.global_position,
			"perpendicular_distance_m":10.0,"gobo_scale":state.gobo_scale,"beam_50_diameter_m":beam_diameter,
			"field_10_diameter_m":field_diameter,"support_diameter_m":support,"guard":"none for these cases",
			"range_m":owner.app._visual_settings.footprint_max_range}))
	owner.app._clear_scene()
	owner.app.queue_free()
	await owner.process_frame
	owner.quit(0 if owner.test.failures.is_empty() else 1)
