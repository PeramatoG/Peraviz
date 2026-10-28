extends RefCounted

# Opt-in production-import workload; timings are CPU settings work, never GPU claims.
static func run(owner: SceneTree) -> void:
	await owner._load(owner._generate(false, true))
	owner.dmx.resize(512)
	owner.dmx.fill(0)
	for fixture in range(20):
		owner.dmx[fixture * 16] = 200
		owner.dmx[fixture * 16 + 3] = 160
		owner.dmx[fixture * 16 + 4] = 255
	await owner._apply()
	for entry in [
		["beam_hold", {"beam_multiplier": 19.5}],
		["beam_active", {"beam_multiplier": 19.0}],
		["footprint_gain", {"footprint_multiplier": 0.55}],
		["footprint_softness", {"footprint_softness": 0.12}],
		["native_backend", {"footprint_backend": "native"}],
		["custom_backend", {"footprint_backend": "custom"}],
	]:
		if entry[0] == "beam_active":
			owner.dmx[4] = 230
			owner.runtime._native_visual_runtime.submit_universe_frame(0, owner.dmx)
			var active_frame: Dictionary = owner.service.consume_native_snapshot(owner.runtime._native_visual_runtime, owner.runtime._sectioned_visual_frame_applier.schema_generation())
			if not active_frame.get("pending", false): owner.runtime._sectioned_visual_frame_applier.apply_snapshot(active_frame, owner.app, owner.service, 0.016, owner.runtime, owner.runtime._native_fixture_uuids_by_id, owner.runtime._fixture_nodes)
		var before: Dictionary = owner.adapter.diagnostics()
		var start := Time.get_ticks_usec()
		owner.app._apply_visual_settings(entry[1])
		var elapsed := Time.get_ticks_usec() - start
		var after: Dictionary = owner.adapter.diagnostics()
		var report := {"case": entry[0], "settings_apply_us": elapsed, "physical_outputs": after.physical_outputs}
		for key in ["aggregate_shafts_created", "aggregate_shafts_retired", "member_shafts_created", "member_shafts_retired", "gpu_lens_created_batches", "gpu_lens_retired_batches", "custom_volumes_created", "custom_volumes_retired", "custom_binding_installs", "custom_projector_resources", "forced_replays", "beam_topology_rebuilt", "shaft_resource_binding_us", "beam_shader_parameter_writes"]:
			report[key] = [before.get(key, 0), after.get(key, 0)]
		if owner.app.get("_live_settings_trace") != null: report.merge(owner.app._live_settings_trace)
		print("LIVE_SETTINGS_COST ", JSON.stringify(report))
		if entry[0] == "beam_active":
			var completed: Dictionary = await owner._completed()
			owner.runtime._sectioned_visual_frame_applier.apply_snapshot(completed, owner.app, owner.service, 0.016, owner.runtime, owner.runtime._native_fixture_uuids_by_id, owner.runtime._fixture_nodes)
	owner.app._clear_scene()
	owner.app.queue_free()
	await owner.process_frame
	owner.quit(0 if owner.test.failures.is_empty() else 1)

# Reuse both production-imported group layouts. Assert identity and values, not
# an arbitrary timing threshold; this runs in normal CI as part of the group test.
static func exercise(owner: SceneTree) -> void:
	var loader: Node = owner.app
	var adapter: RefCounted = owner.adapter
	var updates = preload("res://scripts/runtime/visual_settings_update.gd")
	var before: Dictionary = updates.counters(loader)
	var physical: Array = []
	for index in range(adapter._outputs.size()): physical.append(adapter._native.physical_values(index))
	var resources: Array = []
	for row in adapter._render_bindings.rows:
		for handle in row.output.lights:
			if is_instance_valid(handle.beam): resources.append([handle.beam, handle.beam.mesh, handle.beam.material_override, handle.beam.transform])
	var volumes: Array = adapter._footprints.volumes.duplicate()
	var geometry_revisions: Array = []
	for volume in volumes: geometry_revisions.append(volume.projection.geometry_revision)
	var revision: int = loader._active_beam_renderer._resource_revision
	for gain in [19.9, 19.8, 0.0, 13.0, 20.0]:
		loader._apply_visual_settings({"beam_multiplier": gain})
		for row in adapter._render_bindings.rows:
			var base: float = 0.0
			if row.presentation_class == 1:
				for index in row.members: base += physical[index][6]
				base = clampf(base, 0.0, 50.0)
			else: base = physical[row.output.index][6]
			for handle in row.output.lights:
				if not is_instance_valid(handle.beam): continue
				var intensity: float = clampf(base * gain / 20.0, 0.0, 50.0)
				owner.test.check(handle.beam.visible == (intensity > 0.015), "Live shaft gain updates actual visibility during hold, including zero recovery")
				if intensity > 0.015:
					var dynamic: Color = handle.beam.get_instance_shader_parameter("beam_dynamic_state")
					owner.test.check(is_equal_approx(dynamic.a, intensity), "Held renderer value receives gain exactly once for aggregate and independent shafts")
	for gain in [0.0, 0.35, 0.6]:
		loader._apply_visual_settings({"footprint_multiplier": gain})
		for index in range(volumes.size()):
			var volume: MeshInstance3D = volumes[index]
			var values: PackedFloat32Array = adapter._native.footprint_values(volume.material_override.get_rid())
			var held: PackedFloat32Array = physical[adapter._outputs[index].index]
			var energy: float = (held[5] if held[5] > 0 else held[4]) * gain if held[11] > 0 else 0.0
			owner.test.check(is_equal_approx(values[3], energy), "Footprint gain replays original physical energy through zero without rebuilding volumes")
	for gain in [0.0, 0.25, 2.0, 1.0]:
		loader._apply_visual_settings({"lens_emission_multiplier": gain})
		check_lenses(owner, gain)
	# One global field reaches independent, shared-material and aggregate shafts.
	# Preserve actual native physical values and all cold renderer identities.
	for smoke in [{"fake_smoke_enabled":true},{"fake_smoke_density":0.8,"fake_smoke_variation":0.5},{"fake_smoke_scale_m":8.0,"fake_smoke_animation_speed":0.1},{"fake_smoke_wind_direction_deg":120.0,"fake_smoke_wind_speed":0.2},{"fake_smoke_enabled":false}]:
		loader._apply_visual_settings(smoke)
		check_lenses(owner,1.0)
	loader._apply_visual_settings({"wash_intersection_width_m": 0.25})
	loader._apply_visual_settings({"wash_intersection_width_m": 0.0})
	loader._apply_visual_settings({"beam_softness": 0.4})
	loader._apply_visual_settings({"beam_softness": 0.32})
	loader._apply_visual_settings({"beam_radial_falloff": 1.1})
	loader._apply_visual_settings({"beam_radial_falloff": 1.0})
	loader._apply_visual_settings({"beam_longitudinal_falloff": 1.1})
	loader._apply_visual_settings({"beam_longitudinal_falloff": 1.0})
	loader._apply_visual_settings({"footprint_softness": 0.12})
	for volume in volumes:
		owner.test.check(is_equal_approx(float(volume.material_override.get_shader_parameter("edge_softness")), 0.12), "Softness reaches the existing footprint material")
	loader._apply_visual_settings({"footprint_softness": 0.10})
	loader._apply_visual_settings({"footprint_max_range": 30.0})
	for volume in volumes: owner.test.check(volume.max_range == 30.0, "Range updates existing projection bounds")
	loader._apply_visual_settings({"footprint_max_range": 40.0})
	loader._apply_visual_settings({"ambient_multiplier": 0.09})
	loader._apply_visual_settings({"ambient_multiplier": 0.08})
	for index in range(volumes.size()): owner.test.check(volumes[index].projection.geometry_revision == geometry_revisions[index], "Softness/falloff uniforms preserve projection geometry revision")
	var after: Dictionary = updates.counters(loader)
	for key in before:
		if key != "script_beam_parameter_writes": owner.test.check(before[key] == after[key], "Value edits preserve structural ownership: " + key)
	for item in resources:
		owner.test.check(is_instance_valid(item[0]) and item[0].mesh == item[1] and item[0].material_override == item[2] and item[0].transform == item[3], "Live values retain mesh, material and optical transform identities")
	owner.test.check(loader._active_beam_renderer._resource_revision == revision and adapter._footprints.volumes == volumes, "Values retain renderer compatibility and footprint ownership")
	loader._active_beam_renderer.configure(loader.camera, loader._visual_settings)
	owner.test.check(loader._active_beam_renderer._resource_revision == revision, "Repeated configure preserves compatibility revision")
	for index in range(physical.size()): owner.test.check(physical[index] == adapter._native.physical_values(index), "Visual gains never modify native held DMX values")
	var noop: Dictionary = updates.counters(loader)
	loader._apply_visual_settings(loader._visual_settings)
	owner.test.check(updates.counters(loader) == noop, "A no-op settings transaction does no renderer work")

	# Start real native work before the UI edit. Only the test polls to completion;
	# production gain replay itself performs no wait or session retirement.
	owner.dmx[4] = 111
	owner.runtime._native_visual_runtime.submit_universe_frame(0, owner.dmx)
	var frame: Dictionary = owner.service.consume_native_snapshot(owner.runtime._native_visual_runtime, owner.runtime._sectioned_visual_frame_applier.schema_generation())
	if not frame.get("pending", false): owner.runtime._sectioned_visual_frame_applier.apply_snapshot(frame, loader, owner.service, 0.016, owner.runtime, owner.runtime._native_fixture_uuids_by_id, owner.runtime._fixture_nodes)
	loader._apply_visual_settings({"beam_multiplier": 13.0, "footprint_multiplier": 0.35, "lens_emission_multiplier": 0.4})
	frame = await owner._completed()
	owner.runtime._sectioned_visual_frame_applier.apply_snapshot(frame, loader, owner.service, 0.016, owner.runtime, owner.runtime._native_fixture_uuids_by_id, owner.runtime._fixture_nodes)
	for row in adapter._render_bindings.rows:
		if row.presentation_class != 0: continue
		var v: PackedFloat32Array = adapter._native.physical_values(row.output.index)
		for handle in row.output.lights:
			if not is_instance_valid(handle.beam) or not handle.beam.visible: continue
			var dynamic: Color = handle.beam.get_instance_shader_parameter("beam_dynamic_state")
			owner.test.check(is_equal_approx(dynamic.a, clampf(v[6] * 13.0 / 20.0, 0, 50)), "Newly completed snapshot uses latest gain without losing physical updates")
	for index in range(volumes.size()):
		var held: PackedFloat32Array = adapter._native.physical_values(adapter._outputs[index].index)
		var expected: float = (held[5] if held[5] > 0 else held[4]) * 0.35 if held[11] > 0 else 0.0
		owner.test.check(is_equal_approx(adapter._native.footprint_values(volumes[index].material_override.get_rid())[3], expected), "Completed physical surface update retains the newest visual gain")
	check_lenses(owner, 0.4)
	loader._apply_visual_settings({"beam_multiplier": 20.0, "footprint_multiplier": 0.6, "lens_emission_multiplier": 1.0})

# Compare actual native renderer caches with exact per-output physical Color/Dimmer.
static func check_lenses(owner: SceneTree, gain: float) -> void:
	var adapter: RefCounted = owner.adapter
	var checked: int = 0
	for output in adapter._outputs:
		var held: PackedFloat32Array = adapter._native.physical_values(output.index)
		if adapter._lens_batches.members.has(output.index):
			var location: Vector2i = adapter._lens_batches.members[output.index]
			var buffer: PackedFloat32Array = adapter._native.lens_buffer(location.x)
			var scale: float = output.materials[0].scale
			owner.test.check(is_equal_approx(buffer[location.y * 16 + 15], held[7] * scale * gain), "Instanced lens gain replays held physical energy through zero")
			for channel in range(3): owner.test.check(is_equal_approx(buffer[location.y * 16 + 12 + channel], held[channel + 1]), "Instanced lens retains independent native RGB")
			checked += 1
		else:
			for material in output.materials:
				var values: PackedFloat32Array = adapter._native.material_values(material.rid)
				owner.test.check(values.size() == 4 and is_equal_approx(values[3], held[7] * material.scale * gain), "Individual/shared lens gain follows exact native energy during hold and playback")
				for channel in range(3): owner.test.check(is_equal_approx(values[channel], held[channel + 1]), "Lens emission color remains owned by its physical output")
				checked += 1
	owner.test.check(checked > 0, "Imported Beam models expose real lens materials")
