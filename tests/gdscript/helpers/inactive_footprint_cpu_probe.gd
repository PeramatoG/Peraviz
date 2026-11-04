extends RefCounted

# Opt-in generated raw-DMX workload. Diagnostic reads and PNGs stay outside timers.

static func run(owner: SceneTree) -> void:
	var count := 128
	var samples := 240
	var directory := "user://inactive-footprint-cpu"
	var selected := PackedStringArray()
	var trace_modes: Array = [false, true]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--footprint-count="): count = maxi(1, int(arg.trim_prefix("--footprint-count=")))
		if arg.begins_with("--footprint-samples="): samples = maxi(120, int(arg.trim_prefix("--footprint-samples=")))
		if arg.begins_with("--footprint-output="): directory = arg.trim_prefix("--footprint-output=")
		if arg.begins_with("--footprint-cases="): selected = arg.trim_prefix("--footprint-cases=").split(",")
		if arg == "--footprint-trace-off-only": trace_modes = [false]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results: Array = []
	var report := {"engine": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name(), "rendering_method": RenderingServer.get_current_rendering_method(), "samples": samples, "outputs": count, "cases": results, "clock_pair_mean_us":_clock_pair_mean(),
		"scope": "Generated GDTF through production import, native raw DMX, Pan/Tilt and autonomous ShutterPlayback. Baseline production scheduling; no deferred candidate. Fine scopes overlap and include clock overhead. Batch flush is wall CPU including notification dispatch; frame wall overlaps CPU/GPU and scheduling. Software render times are not hardware evidence."}
	for shared in [false, true]:
		var flags: Array = ["--moving", "--gobo", "--strobe-low", "1", "--strobe-high", "20"]
		if shared: flags.append("--shared")
		for tracing in trace_modes:
			await owner.open_scene(flags, count)
			owner.root.min_size = Vector2i(64, 64)
			owner.root.size = Vector2i(320, 240)
			RenderingServer.viewport_set_measure_render_time(owner.root.get_viewport_rid(), true)
			var service: RefCounted = owner.app._fixture_light_apply_service
			var adapter: RefCounted = owner.adapter
			owner.test.check(adapter._footprints.volumes.size() == count, "Forward+ creates every independent physical footprint")
			if adapter._footprints.volumes.size() != count:
				await owner.close_scene()
				continue
			# Avoid background application/DMX processing; every timestamp is deterministic.
			service.set_performance_trace_enabled(tracing)
			owner.runtime.set_performance_trace_enabled(tracing)
			for volume in adapter._footprints.volumes:
				if volume.get("profile_enabled") != null: volume.profile_enabled = tracing
			var case_index := 0
			for mode in ["blackout_motion", "lit_motion", "static_color_dimmer", "held_1hz", "held_20hz", "held_random", "motion_1hz", "motion_20hz", "motion_random", "no_custom_motion"]:
				if not selected.is_empty() and mode not in selected: continue
				var primary: PackedByteArray = owner.packet()
				primary.fill(255)
				primary[6] = 10
				primary[0] = 0 if mode == "blackout_motion" else 255
				var cells: PackedByteArray = owner.packet()
				var shutter: int = 20 if mode.ends_with("1hz") else 119 if mode.ends_with("20hz") else 249 if mode.ends_with("random") else 10
				cells.fill(shutter)
				if shared: primary[6] = shutter
				var packets: Dictionary = {0:primary}
				if not shared:
					for bank in range(ceili(float(count) / 500.0)): packets[2 + bank] = cells
				adapter._render_isolation = "no-custom-footprints" if mode == "no_custom_motion" else "none"
				adapter._sync_presentation_policy()
				var case_start: float = 1.0 + case_index * 10.0
				case_index += 1
				owner.send(packets, case_start)
				var resources: Array = []
				for volume in adapter._footprints.volumes: resources.append([volume, volume.mesh, volume.material_override])
				var before: Dictionary = _snapshot(adapter)
				var evaluations: int = owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated
				var install_count: int = adapter._footprints.installs
				var flush_times: Array = []
				var callback_times: Array = []
				var frame_times: Array = []
				var render_cpu_ms := 0.0
				var render_gpu_ms := 0.0
				var draw_total := 0
				var physical_writes := 0
				var output_digest := HashingContext.new()
				output_digest.start(HashingContext.HASH_SHA256)
				var digest := HashingContext.new()
				digest.start(HashingContext.HASH_SHA256)
				# Warmup precedes a fixed 120 Hz sample sequence on a monotonic test clock.
				for tick in range(-30, samples):
					var frame_start := Time.get_ticks_usec()
					var now: float = case_start + float(tick + 30) / 120.0
					var callback_start := Time.get_ticks_usec()
					if mode.contains("motion") or mode == "static_color_dimmer":
						if mode.contains("motion"):
							primary[7] = 112 + posmod(tick, 32)
							primary[8] = 112 + posmod(tick * 3, 32)
						else:
							primary[0] = 128 + posmod(tick, 128)
							primary[1] = 128 + posmod(tick * 3, 128)
						owner.send({0:primary}, now)
					else: adapter._native.advance_shutters(adapter._generation, now)
					var callback_us: int = Time.get_ticks_usec() - callback_start
					# Force the real pending volume notification, including ancestor reads,
					# within one batch clock. No per-output clocks in trace-off samples.
					var flush_start := Time.get_ticks_usec()
					for volume in adapter._footprints.volumes: volume.force_update_transform()
					var flush_us: int = Time.get_ticks_usec() - flush_start
					await owner.process_frame
					if RenderingServer.get_rendering_device() != null: await RenderingServer.frame_post_draw
					if tick == -1:
						before = _snapshot(adapter)
						evaluations = owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated
					if tick >= 0:
						frame_times.append(Time.get_ticks_usec() - frame_start)
						flush_times.append(flush_us)
						callback_times.append(callback_us)
						if RenderingServer.get_rendering_device() != null:
							render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(owner.root.get_viewport_rid())
							render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(owner.root.get_viewport_rid())
							draw_total += owner.root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
						# Outside all measured scopes. Digest physical envelopes, not metadata.
						digest.update(adapter._native.shutter_values().to_byte_array())
						if mode.contains("motion") or mode == "static_color_dimmer": physical_writes += int(adapter._native.get_sizes().custom_footprint_dynamic_writes)
						for output in adapter._outputs: output_digest.update(adapter._native.physical_values(output.index).to_byte_array())
						for axis in owner.app._native_target_registry._pan_targets.values() + owner.app._native_target_registry._tilt_targets.values(): output_digest.update(var_to_bytes(axis.transform))
				var after: Dictionary = _snapshot(adapter)
				var delta: Dictionary = {}
				for key in after: delta[key] = int(after[key]) - int(before[key])
				var held: bool = mode.begins_with("held_")
				var evaluation_delta: int = owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated - evaluations
				if held: owner.test.check(evaluation_delta == 0, "Held shutter produces no new source evaluations")
				owner.test.check(adapter._footprints.installs == install_count, "Continuous shutter/motion never reinstalls footprint resources")
				for entry in resources: owner.test.check(is_instance_valid(entry[0]) and entry[0].mesh == entry[1] and entry[0].material_override == entry[2], "Physical mesh/material identity survives every workload")
				var viewport: Viewport = owner.root
				results.append({"case":mode, "shared":shared, "tracing_and_fine_clocks":tracing, "delta":delta, "batch_notification_cpu_us":_distribution(flush_times), "callback_cpu_us":_distribution(callback_times), "frame_wall_us":_distribution(frame_times), "shutter_digest":digest.finish().hex_encode(), "physical_and_mechanical_digest":output_digest.finish().hex_encode(), "physical_footprint_material_writes":physical_writes, "source_evaluations":evaluation_delta if tracing else null, "footprint_resources":adapter._footprints.volumes.size(), "binding_installs":adapter._footprints.installs - install_count, "render_cpu_ms":render_cpu_ms / samples if RenderingServer.get_rendering_device() != null else null, "render_gpu_ms":render_gpu_ms / samples if RenderingServer.get_rendering_device() != null else null, "mean_draws":float(draw_total) / samples if RenderingServer.get_rendering_device() != null else null, "active_footprints":adapter._native.get_sizes().active_custom_footprints, "draws":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) if RenderingServer.get_rendering_device() != null else null})
				print("INACTIVE_FOOTPRINT_CASE ", JSON.stringify(results.back()))
				if tracing and RenderingServer.get_rendering_device() != null: viewport.get_texture().get_image().save_png(directory.path_join(("shared_" if shared else "cells_") + mode + ".png"))
			adapter._render_isolation = "none"
			adapter._sync_presentation_policy()
			await owner.close_scene()
	var file := FileAccess.open(directory.path_join("inactive-footprint-cpu.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))

static func _snapshot(adapter: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for volume in adapter._footprints.volumes:
		for sample in [volume.work_counts(), volume.cpu_times() if volume.has_method("cpu_times") else {}]:
			for key in sample: result[key] = int(result.get(key, 0)) + int(sample[key])
	var native: Dictionary = adapter._native.get_sizes()
	for key in ["shutter_footprint_material_us", "shutter_footprint_material_writes", "shutter_waveform_evaluations"]: result[key] = native.get(key, 0)
	var presentation: Dictionary = adapter.diagnostics()
	result["native_footprint_material_us"] = presentation.get("native_footprint_material_us", 0)
	return result

static func _distribution(values: Array) -> Dictionary:
	var ordered := values.duplicate()
	ordered.sort()
	var total: float = 0.0
	for value in values: total += value
	return {"mean":total / values.size(), "p50":ordered[values.size() / 2], "p95":ordered[mini(values.size() - 1, int(values.size() * 0.95))]}

static func _clock_pair_mean() -> float:
	var elapsed: int = 0
	for iteration in range(10000):
		var started := Time.get_ticks_usec()
		elapsed += Time.get_ticks_usec() - started
	return float(elapsed) / 10000.0
