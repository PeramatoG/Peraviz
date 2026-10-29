extends RefCounted

# Controlled resource/update comparison. No hardware-dependent timing assertion or FPS claim.
static func run(owner: SceneTree) -> void:
	var count: int = 1000 if "--strobe-stress" in OS.get_cmdline_user_args() else 128
	OS.set_environment("PERAVIZ_NATIVE_EVALUATION","parallel")
	await owner.open_scene([],count)
	var primary: PackedByteArray = owner.packet(); primary[0] = 255; primary[1] = 255
	var packets: Dictionary = {0:primary}
	for index in range(count):
		var universe: int = 2+int(index/500.0)
		if not packets.has(universe): packets[universe] = owner.packet()
		packets[universe][index%500] = 10
	owner.send(packets,0)
	var baseline: Array = preload("res://tests/gdscript/helpers/shutter_output_probe.gd").capture(owner.adapter)
	var before: Dictionary = owner.adapter._native.get_sizes()
	owner.test.check(before.gpu_lens_instances > 0,"Compatible independent shutters retain native GPU-instanced lenses")
	var report: Array = []
	for active in [0,2,count]:
		for index in range(count): packets[2+int(index/500.0)][index%500] = 119 if index<active else 10
		owner.send(packets,0)
		var native = owner.adapter._native
		var start_values: Dictionary = native.get_sizes()
		var evaluations: int = owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated
		var started: int = Time.get_ticks_usec()
		for tick in range(240): native.advance_shutters(owner.adapter._generation,0.001+tick/120.0)
		var elapsed: int = Time.get_ticks_usec()-started
		var end: Dictionary = native.get_sizes()
		native.advance_shutters(owner.adapter._generation,0.08)
		preload("res://tests/gdscript/helpers/shutter_output_probe.gd").check(owner,baseline,0,1.0)
		native.advance_shutters(owner.adapter._generation,0.11)
		preload("res://tests/gdscript/helpers/shutter_output_probe.gd").check(owner,baseline,0,0.0 if active>0 else 1.0)
		owner.test.check(owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated == evaluations,"Stress playback performs no new source evaluation during hold")
		owner.test.check(end.shutter_cpu_bytes_estimate == start_values.shutter_cpu_bytes_estimate,"Temporal buffers do not grow while the effect advances")
		owner.test.check(end.unique_lens_material_rids == before.unique_lens_material_rids,"Temporal work never allocates materials as flashes advance")
		if active == 0: owner.test.check(end.shutter_waveform_evaluations == start_values.shutter_waveform_evaluations,"Stable open outputs add zero numerical waveform work")
		report.append({"outputs":count,"active":active,"samples":240,"boundary_us":elapsed,"native_us":end.shutter_presentation_us-start_values.shutter_presentation_us,"waveforms":end.shutter_waveform_evaluations-start_values.shutter_waveform_evaluations,"beam_writes":end.shutter_beam_writes-start_values.shutter_beam_writes,"material_writes":end.shutter_material_writes-start_values.shutter_material_writes,"lens_submissions":end.shutter_lens_submissions-start_values.shutter_lens_submissions,"cpu_bytes_estimate":end.shutter_cpu_bytes_estimate})
	# Exercise the real native asynchronous handoff after the serial deterministic comparison.
	var runtime: RefCounted = owner.runtime
	var service: RefCounted = owner.app._fixture_light_apply_service
	var frame: Dictionary = service.consume_native_snapshot(runtime._native_visual_runtime,runtime._sectioned_visual_frame_applier.schema_generation())
	var deadline: int = Time.get_ticks_msec()+5000
	while frame.get("pending",false) and Time.get_ticks_msec()<deadline:
		await owner.process_frame
		frame = service.consume_native_snapshot(runtime._native_visual_runtime,runtime._sectioned_visual_frame_applier.schema_generation(),true)
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,owner.app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	owner.test.check(owner.adapter._native.get_sizes().native_async_active,"Shutter parameter snapshots retain supported native async ownership")
	owner.adapter._native.advance_shutters(owner.adapter._generation,0.08)
	owner.test.check_close(owner.adapter._native.shutter_values()[0],1,0.0001,"Async handoff preserves the serial 10 Hz held phase")
	print("SHUTTER_PRESENTATION ",JSON.stringify(report))
	await owner.close_scene()
	OS.unset_environment("PERAVIZ_NATIVE_EVALUATION")
