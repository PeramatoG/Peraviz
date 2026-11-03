extends SceneTree

# Same existing generated presentation harness for native/script application only.
# Forced subthreshold bindings belong to this test; production admission stays unchanged.
const Harness = preload("res://tests/gdscript/helpers/footprint_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const Case = preload("res://tests/gdscript/headless_test_case.gd")
var test = Case.new()
class Bindings extends RefCounted:
	var loader: Node
	func get_dense_presentation_bindings() -> Dictionary: return loader.get_dense_presentation_bindings()
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for count in [31,32,64,115,128]:
		var loader := Harness.new()
		loader.output_count = count; loader.vector_prism = true
		loader._visual_settings = {"beam_presentation":1,"footprint_backend":"custom","enable_realtime_spotlights":false,"beam_multiplier":20.0,"footprint_multiplier":0.6}
		root.add_child(loader)
		await process_frame
		var service := Service.new()
		loader.dense_service = service; loader._fixture_light_apply_service = service
		var bindings := Bindings.new(); bindings.loader = loader
		service.set_performance_trace_enabled(true)
		test.check(await service.install_dense_presentation(loader,bindings), "Admission fixture installs")
		var frames: Array[Dictionary] = []
		for tick in range(16): frames.append(loader.frame(0.7 + tick*0.01,0.5 + tick*0.01))
		apply(service,frames[0])
		var adapter: RefCounted = service._dense_adapter
		test.check(adapter.diagnostics().native_beam_eligible_candidates == count, "Count actual eligible resources, not physical rows")
		test.check(adapter._native.get_sizes().native_beam_bindings == (count if count >= 32 else 0), "Production admission retains its threshold")
		if count == 32:
			var initial: Array = []
			for output in adapter._outputs: initial.append(output.lights[0].beam.get_instance_shader_parameter("beam_dynamic_state"))
			apply(service,frames[1])
			adapter._outputs[0].lights[0].has_gobo = true # Test-only admission exclusion, no semantic mutation.
			preload("res://scripts/runtime/native_beam_bindings.gd").install(adapter)
			test.check(adapter._native.get_sizes().native_beam_bindings == 0, "31 remaining candidates revoke native bindings")
			apply(service,frames[0])
			for index in range(count): test.check(adapter._outputs[index].lights[0].beam.get_instance_shader_parameter("beam_dynamic_state") == initial[index], "Native-to-script fallback cannot reuse an obsolete script signature")
			adapter._outputs[0].lights[0].has_gobo = false
			preload("res://scripts/runtime/native_beam_bindings.gd").install(adapter)
		var reference: Array = []
		var report := {"candidates":count,"samples":240,"rounds":3,"native_us":[],"script_us":[]}
		for round in range(3):
			for native in ([false,true] if round%2 == 0 else [true,false]):
				adapter._native.clear_beams()
				var objects := PackedInt64Array(); var thresholds := PackedFloat64Array()
				for row in adapter._render_bindings.rows:
					var handle = row.output.lights[0]
					objects.append(handle.beam.get_instance_id()); thresholds.append(0.015)
					handle.native_candidate = native; handle.bound_state.invalidate()
				if native: test.check(adapter._native.install_beams(adapter._generation,objects,thresholds), "Test-only native admission succeeds")
				service.set_performance_trace_enabled(false)
				for tick in range(32): apply(service,frames[tick%16])
				var start := Time.get_ticks_usec()
				for tick in range(240): apply(service,frames[tick%16])
				report["native_us" if native else "script_us"].append(float(Time.get_ticks_usec()-start)/240.0)
				var actual: Array = []
				for output in adapter._outputs:
					var handle = output.lights[0]
					actual.append([handle.beam.visible,handle.beam.get_instance_shader_parameter("beam_dynamic_state"),adapter._native.physical_values(output.index),adapter._native.footprint_values(adapter._footprints.volumes[output.index].material_override.get_rid())])
				if reference.is_empty(): reference = actual
				else: test.check(actual == reference, "Native/script paths preserve exact final physical, beam and footprint values")
		print("BEAM_ADMISSION ",JSON.stringify(report))
		var retired: RefCounted = adapter._native
		service.reset_scene_state()
		for anchor in loader.anchors: loader.renderer.cleanup_beam(anchor)
		loader.free()
		test.check(retired.get_sizes().native_beam_bindings == 0 and retired.get_sizes().shutter_layers == 0, "Admission routes retire safely")
		await process_frame
	test.finish(self)
func apply(service: RefCounted, frame: Dictionary) -> void:
	service.compose_dense_snapshot(frame.descriptors,frame.integers,frame.floats)
	service.end_visual_snapshot()
