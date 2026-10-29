extends "res://tests/gdscript/test_native_shutter.gd"

# Reuses the production import/playback harness and generated assets; the baseline flag records the prior implementation.
func run() -> void:
	for scenario in [[32,0,true],[32,0,false],[128,0,true],[128,4,false]]:
		await measure(scenario[0],scenario[1],scenario[2])
	if "--authority-baseline" not in OS.get_cmdline_user_args():
		await measure(32,4,false)
		await effects()
		await colored_shared()
		await fallback_lenses()
		await multiple_fixtures()
		await mode_reload()
	test.finish(self)

func flags_for(banks: int, shared: bool) -> Array:
	var flags: Array = ["--random-modes"]
	if shared: flags.append("--shared")
	if banks: flags.append_array(["--banks",str(banks)])
	return flags

func values_for(count: int, banks: int, shared: bool, value: int) -> Dictionary:
	var primary := packet(); primary[0] = 255; primary[1] = 255
	var packets: Dictionary = {0:primary}
	if shared: primary[4] = value
	elif banks:
		for bank in range(banks): primary[4+bank] = value
	else:
		for cell in range(count):
			var universe: int = 2+int(cell/500.0)
			if not packets.has(universe): packets[universe] = packet()
			packets[universe][cell%500] = value
	return packets

func measure(count: int, banks: int, shared: bool) -> void:
	await open_scene(flags_for(banks,shared),count)
	send(values_for(count,banks,shared,10),0)
	var before: Dictionary = adapter.diagnostics()
	var revision: int = app._active_beam_renderer._resource_revision
	send(values_for(count,banks,shared,119),1)
	var start: Dictionary = adapter._native.get_sizes()
	var source_count: int = runtime._native_visual_runtime.get_stats().source_programs_evaluated
	var clock: int = Time.get_ticks_usec()
	for tick in range(240): adapter._native.advance_shutters(adapter._generation,1.001+tick/120.0)
	var boundary: int = Time.get_ticks_usec()-clock
	var end: Dictionary = adapter.diagnostics()
	var report: Dictionary = {"outputs":count,"banks":banks,"shared":shared,"authorities":end.get("shutter_temporal_authorities",end.shutter_layers),"aggregate_shafts":end.aggregate_shaft_resources,"individual_shafts":end.allocated_member_shafts,"gpu_lenses":end.allocated_lens_gpu_instances,"waveforms":end.shutter_waveform_evaluations-start.shutter_waveform_evaluations,"beam_writes":end.shutter_beam_writes-start.shutter_beam_writes,"material_writes":end.shutter_material_writes-start.shutter_material_writes,"lens_submissions":end.shutter_lens_submissions-start.shutter_lens_submissions,"native_us":end.shutter_presentation_us-start.shutter_presentation_us,"boundary_us":boundary,"rebuilds":app._active_beam_renderer._resource_revision-revision,"shaft_material_growth":end.unique_shaft_materials-before.unique_shaft_materials,"source_evaluations":runtime._native_visual_runtime.get_stats().source_programs_evaluated-source_count}
	print("SHUTTER_AUTHORITY_MEASUREMENT ",JSON.stringify(report))
	if "--authority-baseline" not in OS.get_cmdline_user_args():
		var expected: int = 1 if shared else banks if banks else count
		test.check(end.shutter_temporal_authorities == expected,"Temporal instance count follows actual GDTF control authority")
		test.check(report.waveforms == expected*240,"Exactly one waveform evaluation per active authority and sample")
		test.check(report.aggregate_shafts == (expected if shared or banks else 0),"Compatible common/bank controls preserve actual aggregated shafts")
		test.check(report.individual_shafts == (0 if shared or banks else count),"No unnecessary member shafts survive compatible aggregation")
		# Four eight-cell banks cross spatial batch buckets; preserve the existing minimum-batch fallback.
		if count != 32 or banks != 4: test.check(report.gpu_lenses > 0,"Compatible shared and independent lenses retain GPU instancing")
		test.check(end.allocated_lens_gpu_instances == before.allocated_lens_gpu_instances,"Random does not disable or recreate eligible instanced lenses")
		test.check(report.rebuilds == 0 and report.shaft_material_growth == 0 and report.source_evaluations == 0,"Hold creates no structural renderer resources or source evaluations")
		await coherent(count,banks,shared)
	await close_scene()

# Physical members keep their own identities/colors but consume one cached envelope per native temporal authority.
func coherent(count: int, banks: int, shared: bool) -> void:
	var ids: PackedInt32Array = adapter._native.shutter_authority_ids()
	var unique: Dictionary = {}
	for cell in range(count):
		var owner: int = cell_index(cell)
		var bank: int = int(cell/(float(count)/banks)) if banks else 0 if shared else cell
		if unique.has(bank): test.check(ids[owner] == unique[bank],"Members of the same real GDTF control share one authority ID")
		else: unique[bank] = ids[owner]
	var distinct: Dictionary = {}
	for id in unique.values(): distinct[id] = true
	test.check(distinct.size() == unique.size(),"Independent controls never merge merely because input values coincide")
	# Capture canonical/open energies without changing the authority's resource/geometry installation.
	send(values_for(count,banks,shared,10),4)
	var baseline: Array = Probe.capture(adapter)
	var resources: Dictionary = adapter.diagnostics()
	send(values_for(count,banks,shared,119),5)
	var differs: bool = false
	for tick in range(64):
		adapter._native.advance_shutters(adapter._generation,5.001+tick*0.037)
		var values: PackedFloat32Array = adapter._native.shutter_values()
		var seen: Dictionary = {}
		for cell in range(count):
			var owner: int = cell_index(cell)
			var authority: int = ids[owner]
			if seen.has(authority): test.check(values[owner] == seen[authority],"A shared envelope is bitwise identical at deterministic timestamps")
			else: seen[authority] = values[owner]
			if tick%8 == 0: Probe.check(self,baseline,cell,values[owner])
		for value in seen.values(): differs = differs or value != values[cell_index(0)]
	if unique.size()>1: test.check(differs,"Independent authorities evolve independently under identical held input")
	adapter._native.advance_shutters(adapter._generation,5.183)
	var held: PackedFloat32Array = adapter._native.shutter_values()
	var frame: Dictionary = send(values_for(count,banks,shared,119),8)
	test.check(frame.get("descriptors",PackedInt32Array()).is_empty(),"Identical publication does not restart any authority")
	adapter._native.advance_shutters(adapter._generation,5.183)
	test.check(adapter._native.shutter_values() == held,"Shared/independent held sequences survive identical publication")
	if not shared:
		var packets: Dictionary = values_for(count,banks,shared,119)
		if banks: packets[0][4] = 10
		else: packets[2][0] = 10
		send(packets,9)
		adapter._native.advance_shutters(adapter._generation,5.183)
		var current: PackedFloat32Array = adapter._native.shutter_values()
		for cell in range(int(count/float(banks)) if banks else 1,count): test.check(current[cell_index(cell)] == held[cell_index(cell)],"One cell/bank changing mode never resets another authority's random sequence")
	Probe.resources(self,baseline)
	var after: Dictionary = adapter.diagnostics()
	test.check(after.allocated_shaft_nodes == resources.allocated_shaft_nodes and after.unique_shaft_materials == resources.unique_shaft_materials,"Open/Random transitions never add shafts or duplicate materials")

# Existing deterministic waveforms share exactly the same authority/physical fan-out as random modes.
func effects() -> void:
	OS.set_environment("PERAVIZ_NATIVE_EVALUATION","parallel")
	OS.set_environment("PERAVIZ_SHUTTER_TRACE","50000000-0000-0000-0000-000000000001")
	await open_scene(["--shared"],32)
	var packets: Dictionary = values_for(32,0,true,10)
	send(packets,0)
	var baseline: Array = Probe.capture(adapter)
	for raw in [119,120,160,200,249]:
		packets[0][4] = raw; send(packets,float(raw))
		var ids: PackedInt32Array = adapter._native.shutter_authority_ids()
		for step in range(24):
			adapter._native.advance_shutters(adapter._generation,raw+step*0.031)
			var values: PackedFloat32Array = adapter._native.shutter_values()
			for cell in range(32):
				test.check(ids[cell_index(cell)] == ids[0] and values[cell_index(cell)] == values[0],"All supported shapes follow common control")
				if step%8 == 0: Probe.check(self,baseline,cell,values[0])
	var trace: Dictionary = runtime._native_visual_runtime.get_shutter_trace("50000000-0000-0000-0000-000000000001")
	test.check(trace.available,"Existing selected-fixture diagnostics remain available")
	for row in trace.rows:
		test.check(row.authority_members == 32 and row.native_aggregate_eligible and row.aggregate_rejection_reason.is_empty(),"Diagnostics reveal shared physical ownership and exact native aggregation eligibility")
	adapter._native.advance_shutters(adapter._generation,249.183)
	var expected: PackedFloat32Array = adapter._native.shutter_values()
	app._visual_settings["beam_render_mode"] = 1
	app._update_beam_renderer_mode(false); adapter.refresh_renderer()
	adapter._native.advance_shutters(adapter._generation,249.183)
	test.check(adapter._native.shutter_values() == expected,"Renderer replacement preserves the common random sequence")
	app._fixture_light_apply_service.set_render_diagnostic_mode("no-beams")
	adapter._native.advance_shutters(adapter._generation,250)
	app._fixture_light_apply_service.set_render_diagnostic_mode("full")
	adapter._native.advance_shutters(adapter._generation,249.183)
	test.check(adapter._native.shutter_values() == expected,"Diagnostic suppression never resets the common authority")
	var service: RefCounted = app._fixture_light_apply_service
	var frame: Dictionary = service.consume_native_snapshot(runtime._native_visual_runtime,runtime._sectioned_visual_frame_applier.schema_generation())
	var deadline: int = Time.get_ticks_msec()+5000
	while frame.get("pending",false) and Time.get_ticks_msec()<deadline:
		await process_frame
		frame = service.consume_native_snapshot(runtime._native_visual_runtime,runtime._sectioned_visual_frame_applier.schema_generation(),true)
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	adapter._native.advance_shutters(adapter._generation,249.183)
	test.check(adapter._native.get_sizes().native_async_active and adapter._native.get_sizes().shutter_temporal_authorities == 1,"Async handoff retains one shared temporal instance")
	test.check(adapter._native.shutter_values() == expected,"Shared random phase is identical through serial/async handoff")
	await close_scene()
	OS.unset_environment("PERAVIZ_SHUTTER_TRACE")
	OS.unset_environment("PERAVIZ_NATIVE_EVALUATION")

# Co-patching two fixture instances never merges fixture-local temporal effects or immutable asset ownership.
func multiple_fixtures() -> void:
	await open_scene(["--shared","--fixtures","2"],32)
	send(values_for(32,0,true,10),0)
	var packets: Dictionary = values_for(32,0,true,249)
	send(packets,1)
	var ids: PackedInt32Array = adapter._native.shutter_authority_ids()
	var by_fixture: Dictionary = {}
	for index in range(adapter._binding_records.size()):
		var uuid: String = str(adapter._binding_records[index].fixture_uuid)
		if by_fixture.has(uuid): test.check(ids[index] == by_fixture[uuid],"All shared members of one fixture retain one authority")
		else: by_fixture[uuid] = ids[index]
	test.check(by_fixture.size() == 2 and by_fixture.values()[0] != by_fixture.values()[1],"Co-patched fixtures keep independent authority identities")
	var different: bool = false
	for tick in range(64):
		adapter._native.advance_shutters(adapter._generation,1.001+tick*0.037)
		var values: PackedFloat32Array = adapter._native.shutter_values()
		var representatives: Dictionary = {}
		for index in range(ids.size()):
			if representatives.has(ids[index]): test.check(representatives[ids[index]] == values[index],"Fixture-local random synchronization is exact")
			else: representatives[ids[index]] = values[index]
		different = different or representatives.values()[0] != representatives.values()[1]
	test.check(different,"Independent fixtures do not inherit each other's random timing")
	await close_scene()

# Reloads two real MVR selections of the same GDTF archive/personality through normal scene preparation.
func mode_reload() -> void:
	await open_scene(["--dual-mode","--shared-mode","--random-modes"],32)
	send(values_for(32,0,true,119),0)
	test.check(adapter._native.get_sizes().shutter_temporal_authorities == 1,"Authored common-shutter DMX mode installs one control")
	var common_source: String = source
	var common_hash: String = source_hash
	var independent_source: String = source.replace(".mvr","_independent.mvr")
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_shutter_fixture.py"),independent_source,"--outputs","32","--dual-mode","--random-modes"])) == 0,"Generate independent selection without editing the loaded archive")
	var independent_hash: String = FileAccess.get_sha256(independent_source)
	for selection in [independent_source,common_source]:
		var retired: RefCounted = adapter._native
		await app._load_mvr_scene(selection,"mvr",false)
		adapter = app._fixture_light_apply_service._dense_adapter
		runtime = app._dmx_controller._dmx_fixture_runtime
		runtime._native_visual_runtime.set_runtime_now_seconds_for_testing(0)
		send(values_for(32,0,selection == common_source,119),0)
		test.check(retired.get_sizes().shutter_temporal_authorities == 0,"Retired mode clears authority state and memberships")
		test.check(adapter._native.get_sizes().shutter_temporal_authorities == (1 if selection == common_source else 32),"Normal mode preparation installs the selected control graph without stale authority")
		test.check(adapter.diagnostics().aggregate_shaft_resources == (1 if selection == common_source else 0),"Mode selection restores correct actual aggregate resources")
	test.check(FileAccess.get_sha256(common_source) == common_hash and FileAccess.get_sha256(independent_source) == independent_hash,"Mode switching preserves both original source archives byte-for-byte")
	await close_scene()

# Common temporal authority must not merge independently controlled per-instance lens colors.
func colored_shared() -> void:
	await open_scene(["--shared","--random-modes","--cell-colors"],32)
	var packets: Dictionary = values_for(32,0,true,10)
	var colors := packet()
	for cell in range(32):
		colors[cell*4] = 64+(cell*37)%192
		colors[cell*4+1+cell%3] = 255
	packets[2] = colors; send(packets,0)
	var baseline: Array = Probe.capture(adapter)
	test.check(baseline[cell_index(0)].physical.slice(1,4) != baseline[cell_index(1)].physical.slice(1,4),"Generated fixture has actual independent native colors")
	test.check(baseline[cell_index(0)].physical[7] != baseline[cell_index(1)].physical[7],"Generated fixture has actual independent lens intensities")
	test.check(adapter.diagnostics().allocated_lens_gpu_instances > 0,"Independent colors retain compatible GPU lens instancing")
	packets[0][4] = 119; send(packets,1)
	for tick in range(32):
		adapter._native.advance_shutters(adapter._generation,1.001+tick*0.037)
		var values: PackedFloat32Array = adapter._native.shutter_values()
		for cell in range(32):
			test.check(values[cell_index(cell)] == values[0],"Independent colors consume the same shared shutter envelope")
			Probe.check(self,baseline,cell,values[0])
	await close_scene()

# Unsupported/disabled batching keeps the established shared material fallback, with the same temporal authority.
func fallback_lenses() -> void:
	OS.set_environment("PERAVIZ_GPU_LENSES","0")
	await open_scene(["--shared","--random-modes"],32)
	send(values_for(32,0,true,10),0)
	var baseline: Array = Probe.capture(adapter)
	test.check(adapter.diagnostics().allocated_lens_gpu_instances == 0,"Explicit reference lens fallback remains selectable")
	send(values_for(32,0,true,119),1)
	for tick in range(16):
		adapter._native.advance_shutters(adapter._generation,1.001+tick*0.037)
		var values: PackedFloat32Array = adapter._native.shutter_values()
		for cell in range(32): Probe.check(self,baseline,cell,values[0])
	await close_scene()
	OS.unset_environment("PERAVIZ_GPU_LENSES")
