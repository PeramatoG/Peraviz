extends "res://tests/gdscript/test_native_shutter.gd"

func run() -> void:
	for shared in [false, true]:
		var flags: Array = ["--moving", "--gobo", "--strobe-low", "1", "--strobe-high", "20"]
		if shared:
			flags.erase("--gobo")
			flags.append("--shared")
		await open_scene(flags, 32)
		runtime.set_performance_trace_enabled(true)
		app._fixture_light_apply_service.set_performance_trace_enabled(true)
		var gate_offset: int = 4 if shared else 6
		var primary := packet(); primary.fill(255); primary[gate_offset] = 10
		var cells := packet(); cells.fill(10)
		var packets: Dictionary = {0:primary}
		if not shared: packets[2] = cells
		send(packets, 0.0)
		if shared: test.check(adapter._render_bindings.rows.size() < adapter._outputs.size(), "Shared Wash shafts retain aggregation with independent physical footprints")
		var resources: Array = []
		for volume in adapter._footprints.volumes: resources.append([volume, volume.mesh, volume.material_override])
		var installs: int = adapter._footprints.installs
		primary[0] = 0
		send({0:primary}, 0.1)
		var before: Dictionary = adapter.diagnostics()
		for tick in range(32):
			primary[7] = 80 + tick; primary[8] = 100 + tick
			send({0:primary}, 0.2 + tick / 120.0)
			for volume in adapter._footprints.volumes: volume.force_update_transform()
		var after: Dictionary = adapter.diagnostics()
		test.check(after.custom_inverse_writes == before.custom_inverse_writes and after.custom_bounds_recomputations == before.custom_bounds_recomputations, "Blackout motion defers projection and bounds without changing Pan/Tilt")
		test.check(after.custom_deferred_notifications > before.custom_deferred_notifications, "Dark physical projectors retain notification invalidation")
		# Optical evaluation continues while dark; only its renderer commit is pending.
		for output in adapter._outputs:
			for handle in output.lights:
				handle.params.beam_angle = 18.0
				handle.params.lens_shift_x = 0.013
				handle.params.beam_gobo_mirror_x = false
				handle.projection.configure(handle.params, handle.projection.pattern_texture)
				handle.projection.set_roll(37.0)
				handle.projection.apply_footprint(handle.light)
		# Native admission precedes script Pan/Tilt application. Flush its normal
		# queued notifications in this same frame, without advancing the frame.
		primary[0] = 255; primary[7] = 150; primary[8] = 130
		send({0:primary}, 1.0)
		for projector in adapter._footprints.volumes: projector.force_update_transform()
		check_projection("Simultaneous DMX restores current ancestry in the same render frame")
		# Existing visibility and receiver culling must not suspend energized optics.
		var volume = adapter._footprints.volumes[0]
		volume.set_receiver_bounds(AABB(Vector3.ONE * 1000, Vector3.ONE), true)
		test.check(volume.culled and volume._projection_active, "Receiver rejection is distinct from native energy admission")
		volume.get_parent().position += Vector3(0.1, 0.2, 0.3)
		volume.force_update_transform()
		check_projection("Culled energized projectors still follow mechanical ancestry")
		volume.set_receiver_bounds(AABB(), false)
		var camera := root.get_camera_3d()
		if camera != null:
			camera.position += Vector3(1, 0, 0)
			check_projection("Camera movement needs no projection invalidation or DMX")
		# A receiver edit while dark is stored, then resolved on synchronous admission.
		primary[0] = 0; send({0:primary}, 1.1)
		volume.set_receiver_bounds(AABB(Vector3.ONE * -100, Vector3.ONE * 200), true)
		primary[0] = 255; send({0:primary}, 1.2)
		test.check(not volume.culled, "Activation refreshes receiver bounds stored during blackout")
		check_projection("Receiver edits restore exact projection before admission")
		# Activation uses exact equality even below the ordinary active-world guard.
		adapter._native.replay_presentation_gains(false,true,0.0,false)
		volume.get_parent().position.x += 0.000001
		adapter._native.replay_presentation_gains(false,true,app._visual_settings.footprint_multiplier,false)
		var exact: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
		test.check(exact == volume.get_parent().global_transform.affine_inverse(), "Held gain restores sub-epsilon motion exactly without a new DMX packet")
		# Stable Closed is safe to defer independently of physical Dimmer/Color.
		if shared: primary[gate_offset] = 0
		else: cells.fill(0)
		packets[0] = primary
		if not shared: packets[2] = cells
		send(packets, 1.3)
		var closed_before: Dictionary = adapter.diagnostics()
		for axis in app._native_target_registry._pan_targets.values(): axis.rotation.y += 0.1
		for projector in adapter._footprints.volumes: projector.force_update_transform()
		test.check(adapter.diagnostics().custom_inverse_writes == closed_before.custom_inverse_writes, "Stable closed shutter defers physical projection commits")
		for shutter in [20, 119, 249]:
			if shared: primary[gate_offset] = shutter
			else:
				cells.fill(shutter)
				# Half the cells stay open to exercise independent physical admission.
				for cell in range(16, 32): cells[cell] = 10
			packets[0] = primary
			if not shared: packets[2] = cells
			send(packets, 2.0 + shutter)
			var evaluations: int = runtime._native_visual_runtime.get_stats().source_programs_evaluated
			var stable: Dictionary = adapter.diagnostics()
			for tick in range(240):
				var now: float = 2.0 + shutter + tick / 120.0
				# Mechanical edits without source packets: held autonomous shutter must
				# restore even a not-yet-delivered inherited transform notification.
				var previous: Array = []
				for projector in adapter._footprints.volumes: previous.append(projector._projection_active)
				for axis in app._native_target_registry._pan_targets.values(): axis.rotation.y += 0.001
				adapter._native.advance_shutters(adapter._generation, now)
				for index in range(adapter._footprints.volumes.size()):
					var projector = adapter._footprints.volumes[index]
					if projector._projection_active and not previous[index]: check_volume(projector, "Held strobe admission synchronizes pending mechanics before notification")
				for projector in adapter._footprints.volumes: projector.force_update_transform()
				check_projection("Continuously active projectors follow normal notification propagation")
			for projector in adapter._footprints.volumes: test.check(projector._projection_active, "Continuous shutter stays ready after first activation")
			test.check(runtime._native_visual_runtime.get_stats().source_programs_evaluated == evaluations, "1/20 Hz and Random hold perform no source evaluation")
			# Static continuous shutters perform no per-flash projection checks or commits.
			for tick in range(240): adapter._native.advance_shutters(adapter._generation, 4.0 + shutter + tick / 120.0)
			var static_before: Dictionary = adapter.diagnostics()
			for tick in range(240): adapter._native.advance_shutters(adapter._generation, 6.0 + shutter + tick / 120.0)
			var static_after: Dictionary = adapter.diagnostics()
			test.check(static_after.custom_inverse_writes == static_before.custom_inverse_writes and static_after.custom_bounds_recomputations == static_before.custom_bounds_recomputations and static_after.custom_activation_checks == static_before.custom_activation_checks, "Static high-frequency shutter does not flush unchanged projection/bounds")
			test.check(adapter._footprints.installs == installs and stable.shutter_resource_install_calls == static_after.shutter_resource_install_calls, "High-frequency activation never reinstalls resources")
		for entry in resources: test.check(is_instance_valid(entry[0]) and entry[0].mesh == entry[1] and entry[0].material_override == entry[2], "Deferral retains each independent physical resource")
		# Cold renderer replacement while held dark must rebind admission before replay.
		primary[0] = 0; send({0:primary}, 300.0)
		var old_renderer: BeamRendererBase = app._active_beam_renderer
		var replacement: BeamRendererBase = load("res://scripts/beam_renderers/volumetric_beam_renderer.gd").new()
		replacement.configure(app.camera, app._visual_settings)
		for output in adapter._outputs:
			for handle in output.lights:
				old_renderer.cleanup_beam(handle.light)
				replacement.ensure_beam(handle.light)
		app._beam_renderers[app._active_beam_mode] = replacement
		app._active_beam_renderer = replacement
		adapter.refresh_renderer()
		for entry in resources: test.check(is_instance_valid(entry[0]) and entry[0].material_override == entry[2], "Renderer replacement while dark retains physical footprint resources")
		for axis in app._native_target_registry._pan_targets.values(): axis.rotation.y += 0.2
		app._fixture_light_apply_service.set_render_diagnostic_mode("no-beams")
		app._fixture_light_apply_service.set_render_diagnostic_mode("full")
		primary[0] = 255; primary[gate_offset] = 10; cells.fill(10)
		packets[0] = primary
		if not shared: packets[2] = cells
		send(packets, 301.0)
		check_projection("Renderer rebind and held policy replay restore exact physical projections")
		var retired: RefCounted = adapter._native
		await app._load_mvr_scene(source, "mvr", false)
		adapter = app._fixture_light_apply_service._dense_adapter
		test.check(retired.get_sizes().active_custom_footprints == 0, "Reload revokes retired indexed callbacks")
		send(packets, 302.0)
		check_projection("Reloaded generation restores current optics")
		await close_scene()
	test.finish(self)

func check_projection(message: String) -> void:
	for volume in adapter._footprints.volumes:
		var energy: PackedFloat32Array = adapter._native.footprint_values(volume.material_override.get_rid())
		if energy.size() != 4 or energy[3] <= 0: continue
		check_volume(volume, message)

func check_volume(volume: MeshInstance3D, message: String) -> void:
	var inverse: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
	var origin: Vector3 = volume.material_override.get_shader_parameter("projector_origin")
	var world: Transform3D = volume.get_parent().global_transform
	test.check((inverse * world).is_equal_approx(Transform3D.IDENTITY) and origin == world.origin, message)
	test.check(is_equal_approx(float(volume.material_override.get_shader_parameter("aperture_tangent")),tan(deg_to_rad(volume.projection.half_angle_deg))), "Admission restores current optical aperture")
