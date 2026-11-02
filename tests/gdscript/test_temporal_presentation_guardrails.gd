extends "res://tests/gdscript/test_shutter_authority.gd"

# The existing production-import harness also runs against 069ef3b for a like-for-like audit.
func run() -> void:
	for layout in [[32,0,true],[128,0,true],[128,4,false],[128,0,false]]:
		await audit(layout[0],layout[1],layout[2])
	await audit(128,0,true,true)
	if "--temporal-baseline" not in OS.get_cmdline_user_args():
		await transactions()
		await preload("res://tests/gdscript/helpers/temporal_lens_admission_probe.gd").run(self)
	test.finish(self)

func audit(count: int, banks: int, shared: bool, absent: bool = false) -> void:
	var flags: Array = ["--shared"] if shared else ["--banks",str(banks)] if banks else []
	if absent: flags.append("--absent")
	await open_scene(flags,count)
	var packets: Dictionary = values_for(count,banks,shared,10)
	send(packets,0)
	# Opt-in production tracing, including the native presentation owner, without UI timers.
	runtime.set_performance_trace_enabled(true)
	adapter._native.compose(adapter._generation,PackedInt32Array(),PackedInt32Array(),PackedFloat32Array(),true)
	var baseline: Array = Probe.capture(adapter)
	var resources: Dictionary = adapter.diagnostics()
	var revision: int = app._active_beam_renderer._resource_revision
	for scenario in [["open",10],["closed",0],["periodic",119],["random",249],["color_dimmer",10],["identical_packets",119]]:
		if absent and scenario[0] != "open": continue
		packets = values_for(count,banks,shared,scenario[1])
		send(packets,1)
		var native: RefCounted = adapter._native
		var start: Dictionary = native.get_sizes()
		var sources: int = runtime._native_visual_runtime.get_stats().source_programs_evaluated
		var samples: int = 7200 if count == 128 and shared and scenario[0] == "random" else 240
		var submitted_bytes: int = 0
		var footprints: int = 0
		var boundary_us: int = 0
		var digest: int = 0
		for tick in range(samples):
			var tick_start: Dictionary = native.get_sizes()
			var now: float = 1.001+tick/120.0
			if scenario[0] == "color_dimmer":
				packets[0][0] = 64+tick%192
				packets[0][1] = 255-tick%128
				send(packets,now)
			elif scenario[0] == "identical_packets":
				var frame: Dictionary = send(packets,now)
				test.check(frame.get("descriptors",PackedInt32Array()).is_empty(),"Identical packets publish no semantic rows")
			var clock: int = Time.get_ticks_usec()
			var changed: int = native.advance_shutters(adapter._generation,now)
			boundary_us += Time.get_ticks_usec()-clock
			var stats: Dictionary = native.get_sizes()
			if stats.shutter_lens_submissions > tick_start.shutter_lens_submissions:
				submitted_bytes += stats.gpu_lens_transfer_bytes
			if stats.shutter_material_writes > tick_start.shutter_material_writes:
				footprints += stats.custom_footprint_dynamic_writes
			# Numerical digest and cold inspection are outside the measured native boundary.
			digest = (digest*33)^hash(native.shutter_values())
			var before_repeat: Dictionary = native.get_sizes()
			test.check(native.advance_shutters(adapter._generation,now) == 0,"Same envelope nominates no physical mutations")
			var after_repeat: Dictionary = native.get_sizes()
			for key in ["shutter_beam_writes","shutter_material_writes","shutter_lens_submissions"]:
				test.check(before_repeat[key] == after_repeat[key],"Unchanged envelope suppresses actual setters and submissions")
		var end: Dictionary = adapter.diagnostics()
		var calls: int = samples*(3 if scenario[0] == "identical_packets" else 2)
		var active: int = (1 if shared else banks if banks else count) if scenario[0] in ["periodic","random","identical_packets"] and not absent else 0
		test.check(end.shutter_waveform_evaluations-start.shutter_waveform_evaluations == active*calls,"One waveform per active authority and presentation call")
		test.check(app._active_beam_renderer._resource_revision == revision,"No flash rebuilds renderer resources")
		if end.has("shutter_lens_transfer_bytes"):
			test.check(end.shutter_lens_transfer_bytes-start.shutter_lens_transfer_bytes == submitted_bytes,"Lifetime submitted bytes agree with observed temporal transactions")
			test.check(end.shutter_material_writes == end.shutter_lens_material_writes+end.shutter_footprint_material_writes,"Combined material counter contains only actual consumer setters")
		var source_delta: int = runtime._native_visual_runtime.get_stats().source_programs_evaluated-sources
		if scenario[0] != "color_dimmer": test.check(source_delta == 0,"Held/identical DMX performs zero source evaluations")
		test.check(end.shutter_cpu_bytes_estimate == start.shutter_cpu_bytes_estimate,"Long playback retains bounded temporal capacity")
		for key in ["aggregate_shaft_resources","allocated_member_shafts","allocated_lens_gpu_instances","custom_volumes_created","unique_lens_material_rids","unique_shaft_materials"]:
			test.check(end[key] == resources[key],"Playback preserves installed resources and batching admission")
		var report: Dictionary = {"scenario":"absent" if absent else scenario[0],"outputs":count,"banks":banks,"shared":shared,"samples":samples,"authorities":end.shutter_temporal_authorities,"active_authorities":end.shutter_active_authorities,"waveforms":end.shutter_waveform_evaluations-start.shutter_waveform_evaluations,"envelope_changes":end.shutter_envelope_changes-start.shutter_envelope_changes,"beam_writes":end.shutter_beam_writes-start.shutter_beam_writes,"material_writes":end.shutter_material_writes-start.shutter_material_writes,"footprint_writes_observed":footprints,"lens_submissions":end.shutter_lens_submissions-start.shutter_lens_submissions,"submitted_bytes_observed":submitted_bytes,"native_us":end.shutter_presentation_us-start.shutter_presentation_us,"boundary_us":boundary_us,"source_evaluations":source_delta,"digest":digest,"aggregate_shafts":end.aggregate_shaft_resources,"individual_shafts":end.allocated_member_shafts,"gpu_lenses":end.allocated_lens_gpu_instances,"gpu_batches":end.gpu_lens_batches,"cpu_bytes_estimate":end.shutter_cpu_bytes_estimate}
		for key in ["shutter_lens_material_writes","shutter_footprint_material_writes","shutter_projector_writes","shutter_lens_transfer_bytes","shutter_evaluation_us","shutter_mutation_us"]:
			if end.has(key): report[key] = end[key]-start[key]
		print("TEMPORAL_AUDIT ",JSON.stringify(report))
		if scenario[0] != "color_dimmer" and scenario[0] != "identical_packets":
			for cell in range(count): Probe.check(self,baseline,cell,native.shutter_values()[cell_index(cell)])
	Probe.resources(self,baseline)
	var retired: RefCounted = adapter._native
	await close_scene()
	test.check(retired.get_sizes().shutter_temporal_authorities == 0 and retired.get_sizes().gpu_lens_batches == 0,"Scene retirement releases authorities and borrowed MultiMesh routes")

# Focused transactions check API work separately from physical envelope fan-out.
func transactions() -> void:
	await open_scene(["--shared"],128)
	var native: RefCounted = adapter._native
	var packets: Dictionary = values_for(128,0,true,119)
	send(packets,1)
	for now in [1.08,1.11,1.18,1.21]:
		var buffers: Array = []
		for batch in range(native.get_sizes().gpu_lens_batches): buffers.append(native.lens_buffer(batch))
		var before: Dictionary = native.get_sizes()
		native.advance_shutters(adapter._generation,now)
		var after: Dictionary = native.get_sizes()
		var dirty: int = 0
		var bytes: int = 0
		var instances: int = 0
		for batch in range(buffers.size()):
			var current: PackedFloat32Array = native.lens_buffer(batch)
			if buffers[batch] != current:
				dirty += 1; bytes += current.size()*4
			for slot in range(current.size()/16):
				if current[slot*16+15] != buffers[batch][slot*16+15]: instances += 1
		test.check(after.shutter_lens_submissions-before.shutter_lens_submissions == dirty,"Each changed MultiMesh submits exactly once per temporal transaction")
		test.check(after.shutter_lens_transfer_bytes-before.shutter_lens_transfer_bytes == bytes,"Submitted bytes count full buffers independently of changed alpha slots")
		test.check(after.shutter_lens_instance_writes-before.shutter_lens_instance_writes == instances,"Logical instance mutations count only changed custom alpha values")
	# Trace-off retains exact numerical work but performs no diagnostic clock accumulation.
	native.compose(adapter._generation,PackedInt32Array(),PackedInt32Array(),PackedFloat32Array(),false)
	var off: Dictionary = native.get_sizes()
	for tick in range(120): native.advance_shutters(adapter._generation,2.001+tick/120.0)
	var end: Dictionary = native.get_sizes()
	test.check(end.shutter_waveform_evaluations-off.shutter_waveform_evaluations == 120,"Trace-off still samples one shared authority per call")
	for key in ["shutter_presentation_us","shutter_evaluation_us","shutter_mutation_us"]:
		test.check(end[key] == off[key],"Trace-off collects no temporal diagnostic timing")
	native.set_materials_enabled(false)
	native.set_footprints_enabled(false)
	var suppressed: Dictionary = native.get_sizes()
	for now in [4.08,4.11,4.18]: native.advance_shutters(adapter._generation,now)
	var hidden: Dictionary = native.get_sizes()
	for key in ["shutter_lens_material_writes","shutter_footprint_material_writes","shutter_lens_submissions"]:
		test.check(hidden[key] == suppressed[key],"Disabled consumers add zero temporal mutations or buffer submissions")
	await close_scene()
	# Native projectors store float energy. Replay compares at that precision before issuing setters.
	await open_scene(["--gobo"],8)
	app._apply_visual_settings({"footprint_backend":"native"})
	send(values_for(8,0,false,10),0)
	native = adapter._native
	native.set_shutter_policy(true,1.0,0.123456789)
	native.advance_shutters(adapter._generation,0)
	var held: Dictionary = native.get_sizes()
	native.invalidate_renderer()
	native.advance_shutters(adapter._generation,0)
	test.check(held.shutter_projector_writes > 0,"Native reference projector route is exercised")
	test.check(native.get_sizes().shutter_projector_writes == held.shutter_projector_writes,"Held float projector energy requires zero duplicate replay setters")
	await close_scene()
