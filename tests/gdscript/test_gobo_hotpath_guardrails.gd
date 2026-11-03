extends "res://tests/gdscript/test_native_shutter.gd"

const COLD = ["dense_light_rebind_calls", "dense_renderer_refreshes", "render_group_binding_installs", "native_beam_binding_passes", "shutter_resource_install_calls", "shutter_invalidations"]

func run() -> void:
	for scenario in [[false,"custom"],[true,"custom"],[false,"native"],[true,"native"]]:
		var mixed: bool = scenario[0]
		var flags: Array = ["--gobo", "--shared", "--random-modes"]
		if mixed: flags.append_array(["--fixtures", "2", "--mixed-gobo"])
		await open_scene(flags, 32 if mixed else 1)
		app._apply_visual_settings({"footprint_backend":scenario[1]})
		runtime.set_performance_trace_enabled(true)
		app._fixture_light_apply_service.set_performance_trace_enabled(true)
		var primary := packet(); primary[0] = 255; primary[1] = 255; primary[6] = 249
		primary[0] = 0
		send({0:primary}, 0)
		primary[0] = 255
		send({0:primary}, 0)
		var registry: RefCounted = app._native_target_registry._gobo_resources
		var targets: Dictionary = app._native_target_registry._beam_output_records_by_id
		# Replace local clock references with deterministic timestamps; held raw DMX is unchanged.
		for key in registry._rotation_states:
			var motion: Dictionary = registry._rotation_states[key]
			registry.apply_rotation_state(motion.beam_target_id,motion.wheel_id,motion.wheel_instance_index,2,1000,10,30,0,0,targets[motion.beam_target_id],1000000)
		flush()
		var resources: Dictionary = adapter.diagnostics()
		test.check(resources.aggregate_shaft_resources == (1 if mixed else 0), "Mixed scene retains its separate shared Wash Render Group")
		for changing in [false, true]:
			var start: Dictionary = adapter.diagnostics()
			var sources: int = runtime._native_visual_runtime.get_stats().source_programs_evaluated
			var digest: int = 0
			for tick in range(320):
				var now: float = 1.0 + tick / 60.0
				if changing:
					primary[0] = 128 + tick % 127; primary[1] = 128 + tick % 127
					send({0:primary}, now)
				adapter._native.advance_shutters(adapter._generation, now)
				var native_energies: Array = []
				for motion_key in registry._rotation_states:
					var motion: Dictionary = registry._rotation_states[motion_key]
					native_energies.append(targets[motion.beam_target_id].emitter_anchors[0].light_energy)
				registry.advance_motion_at_usec(1000000 + int(tick * 1000000.0 / 60.0), targets)
				flush()
				var envelopes: PackedFloat32Array = adapter._native.shutter_values()
				digest = (digest * 33) ^ hash(envelopes)
				var output_index: int = 0
				for key in registry._rotation_states:
					var motion: Dictionary = registry._rotation_states[key]
					var expected: float = wrapf(10 + 30 * tick / 60.0, 0, 360)
					var light: SpotLight3D = targets[motion.beam_target_id].emitter_anchors[0]
					if "--gobo-hotpath-baseline" not in OS.get_cmdline_user_args(): test.check(light.light_energy == native_energies[output_index], "Angle updates preserve shutter-modulated Native projector energy")
					if scenario[1] == "native":
						var physical_index: int = adapter._lights_by_id[light.get_instance_id()].output_index
						var values: PackedFloat32Array = adapter._native.physical_values(physical_index)
						var energy: float = (values[5] if values[5] > 0 else values[4]) * adapter._surface_multiplier * envelopes[physical_index]
						test.check_close(light.light_energy,energy,0.0001,"Native ownership acquired after initial blackout retains Random modulation")
					output_index += 1
					if light.has_meta(&"peraviz_custom_footprint"):
						var volume: MeshInstance3D = light.get_meta(&"peraviz_custom_footprint")
						var inverse: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
						test.check((inverse * light.global_transform).is_equal_approx(Transform3D.IDENTITY), "Projected artwork retains the actual rolled physical inverse")
					test.check_close(light.get_meta(&"peraviz_optical_projection_state").gobo_roll_deg, expected, 0.002, "Physical roll and Custom Footprint optics follow held native phase")
			var end: Dictionary = adapter.diagnostics()
			var report := {"backend":scenario[1],"mixed":mixed,"changing_dimmer_color":changing,"frames":320,"shutter_digest":digest,"source_evaluations":runtime._native_visual_runtime.get_stats().source_programs_evaluated-sources}
			for key in COLD:
				report[key] = int(end.get(key,0)) - int(start.get(key,0))
				if "--gobo-hotpath-baseline" not in OS.get_cmdline_user_args(): test.check(report[key] == 0, "Pure angles never enter cold operations: " + key)
			if not changing: test.check(report.source_evaluations == 0, "Held DMX evaluates no native sources")
			for key in ["aggregate_shaft_resources", "custom_volumes_created", "custom_binding_installs", "unique_shaft_materials"]: test.check(end[key] == resources[key], "Rotation keeps resources: " + key)
			print("GOBO_HOTPATH ", JSON.stringify(report))
		if "--gobo-hotpath-baseline" not in OS.get_cmdline_user_args(): await lifecycle(registry, targets)
		var retired: RefCounted = adapter._native
		await close_scene()
		test.check(retired.get_sizes().shutter_layers == 0, "Unload revokes shutter and gobo resources")
	test.finish(self)

func flush() -> void:
	app._fixture_light_apply_service.compose_dense_snapshot(PackedInt32Array(),PackedInt32Array(),PackedFloat32Array())
	app._fixture_light_apply_service.end_visual_snapshot()

func lifecycle(registry: RefCounted, targets: Dictionary) -> void:
	var key: String = registry._rotation_states.keys()[0]
	var motion: Dictionary = registry._rotation_states[key]
	var target: Dictionary = targets[motion.beam_target_id]
	var light: SpotLight3D = target.emitter_anchors[0]
	var before: Dictionary = adapter.diagnostics()
	var selected: Dictionary = registry._selections_by_target[motion.beam_target_id][motion.wheel_instance_index].duplicate()
	registry.apply_selection(motion.beam_target_id,motion.wheel_id,motion.wheel_instance_index,2,0,0,target)
	flush()
	test.check(adapter.diagnostics().shutter_resource_install_calls > before.shutter_resource_install_calls, "Real selection changes retain resource installation")
	registry.apply_selection(motion.beam_target_id,motion.wheel_id,motion.wheel_instance_index,selected.slot_index,selected.asset_id,0,target)
	flush()
	var texture: Texture2D = light.get_meta("peraviz_gobo_texture")
	adapter._native.advance_shutters(adapter._generation,7.0)
	var envelope: PackedFloat32Array = adapter._native.shutter_values()
	app._active_beam_renderer.cleanup_beam(light)
	app._active_beam_renderer.ensure_beam(light)
	adapter.refresh_renderer()
	registry.rehydrate_renderer_state(app._native_target_registry._beam_output_records_by_id,7000000)
	for mode in [1,0]:
		app._visual_settings.beam_render_mode = mode
		app._update_beam_renderer_mode(false)
		adapter.refresh_renderer()
		registry.rehydrate_renderer_state(app._native_target_registry._beam_output_records_by_id,7000000)
		adapter._native.advance_shutters(adapter._generation,7.0)
		test.check(adapter._native.shutter_values() == envelope, "Renderer replacement retains deterministic Random authority")
		test.check(light.get_meta("peraviz_gobo_texture") == texture, "Renderer replacement retains selected original artwork")
		test.check_close(light.get_meta(&"peraviz_optical_projection_state").gobo_roll_deg,190.0,0.001,"Held rotation rehydrates into replacement renderer")
	flush()
