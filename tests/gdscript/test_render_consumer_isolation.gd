extends "res://tests/gdscript/test_native_shutter.gd"

func run() -> void:
	if "--consumer-child" not in OS.get_cmdline_user_args():
		var reference: Dictionary = {}
		for isolation in ["none","no-custom-footprints","no-volumetric-shafts"]:
			var output: Array = []
			var args := PackedStringArray(["--headless","--audio-driver","Dummy","--rendering-method","forward_plus","--path",ProjectSettings.globalize_path("res://"),"--script","tests/gdscript/test_render_consumer_isolation.gd","--","--consumer-child","--peraviz-render-isolation=" + isolation])
			test.check(OS.execute(OS.get_executable_path(),args,output,true) == 0, "Consumer isolation child passes: " + isolation)
			for line in str(output[0]).split("\n"):
				if line.begins_with("CONSUMER_CASE "):
					var row: Dictionary = JSON.parse_string(line.trim_prefix("CONSUMER_CASE "))
					if reference.is_empty(): reference = row
					for key in ["physical_digest","pan_tilt_digest","source_evaluations"]: test.check(row[key] == reference[key], "Identical native DMX/transform work across consumers: " + key)
					print(line)
				elif "ERROR:" in line or "SCRIPT ERROR" in line or "TEST FAILURE" in line: test.check(false, line)
		test.finish(self)
		return
	await open_scene(["--shared","--moving"],32)
	runtime.set_performance_trace_enabled(true)
	app._fixture_light_apply_service.set_performance_trace_enabled(true)
	var isolation: String = app._fixture_light_apply_service._render_isolation
	var primary := packet(); primary[0] = 255; primary[1] = 255; primary[4] = 10
	send({0:primary},0)
	var start: Dictionary = adapter.diagnostics()
	var source_count: int = runtime._native_visual_runtime.get_stats().source_programs_evaluated
	var digest: int = 0
	var pan_digest: int = 0
	test.check(not app._native_target_registry._pan_targets.is_empty() and not app._native_target_registry._tilt_targets.is_empty(), "Real native Pan/Tilt targets are present")
	for tick in range(120):
		primary[0] = 128 + tick%127; primary[1] = 100 + tick%127
		primary[7] = 64 + tick; primary[8] = 64 + tick
		send({0:primary}, 1.0 + tick/60.0)
		for index in range(adapter._outputs.size()): digest = (digest*33)^hash(adapter._native.physical_values(index))
		for axis in app._native_target_registry._pan_targets.values() + app._native_target_registry._tilt_targets.values(): pan_digest = (pan_digest*33)^hash(axis.transform)
		check_consumers(isolation)
	var end: Dictionary = adapter.diagnostics()
	for key in ["custom_volumes_created","aggregate_shafts_created","shutter_resource_install_calls","native_beam_binding_passes","shutter_invalidations"]:
		test.check(end.get(key,0) == start.get(key,0), "Consumer suppression creates no live cold operations: " + key)
	for mode in ["no-beams","transforms-only","full"]: app._fixture_light_apply_service.set_render_diagnostic_mode(mode)
	check_consumers(isolation)
	adapter.refresh_renderer()
	check_consumers(isolation)
	test.check(not app._visual_settings.has("render_isolation"), "Diagnostic option never becomes a saved visual setting")
	print("CONSUMER_CASE ",JSON.stringify({"isolation":isolation,"physical_digest":str(digest),"pan_tilt_digest":str(pan_digest),"source_evaluations":runtime._native_visual_runtime.get_stats().source_programs_evaluated-source_count,"active_shafts":end.total_visible_vector_prism_shafts,"active_footprints":end.active_custom_footprints,"allocated_footprints":end.custom_projector_resources,"native_eligible_candidates":end.get("native_beam_eligible_candidates",0)}))
	var retired: RefCounted = adapter._native
	await close_scene()
	test.check(retired.get_sizes().active_custom_footprints == 0 and retired.get_sizes().shutter_layers == 0, "Suppressed consumers retire normally")
	test.finish(self)

func check_consumers(isolation: String) -> void:
	var stats: Dictionary = adapter.diagnostics()
	test.check(stats.active_custom_footprints == (0 if isolation == "no-custom-footprints" else 32 - stats.culled_custom_footprints), "Only requested footprint consumer is disabled: active=%d culled=%d" % [stats.active_custom_footprints,stats.culled_custom_footprints])
	test.check(stats.total_visible_vector_prism_shafts == (0 if isolation == "no-volumetric-shafts" else 1), "Only requested shaft draws are disabled")
	var lens: RefCounted = adapter._outputs[0].materials[0]
	test.check(adapter._native.material_values(lens.rid)[3] > 0, "Lens emission remains active")
