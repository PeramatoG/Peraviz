extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const LoaderBase = preload("res://tests/gdscript/helpers/coalescing_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const Applier = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")

class DenseLoader extends LoaderBase:
	var _active_beam_renderer: BeamRendererBase
	var dense_service: RefCounted
	var use_vector_prism: bool = false
	var target_record_reads: int = 0
	func _ready() -> void:
		if use_vector_prism:
			renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd").new()
		super._ready()
		_active_beam_renderer = renderer
	func _refresh_native_gobo_presentation(light: SpotLight3D) -> void:
		var active: bool = bool(dense_service._light_desired_for(light).get("visible", false))
		light.light_projector = light.get_meta("peraviz_gobo_texture") if active else null
	func _get_native_dimmer_target_record(target: int) -> Dictionary:
		target_record_reads += 1
		return super._get_native_dimmer_target_record(target)
	func _get_native_color_target_record(target: int) -> Dictionary:
		target_record_reads += 1
		return super._get_native_color_target_record(target)

class Bindings extends RefCounted:
	var outputs: Array
	func get_dense_presentation_bindings() -> Dictionary:
		var ids := PackedInt32Array()
		var scales := PackedFloat32Array()
		var routes := PackedInt32Array()
		for i in range(outputs.size()):
			ids.append(int(outputs[i]["beam_render_target_id"]))
			scales.append(float(outputs[i]["beam_optical_profile"]["projected_lumen_scale"]))
			routes.append_array(PackedInt32Array([2, 201, i, 3, 301, i, 4, 401, i]))
		return {"ids": ids, "scales": scales, "routes": routes, "outputs": outputs}

var test = TestCase.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var loader := DenseLoader.new()
	get_root().add_child(loader)
	await process_frame
	var service = Service.new()
	loader.dense_service = service
	var registry := Bindings.new()
	registry.outputs = loader.outputs
	var lens := StandardMaterial3D.new()
	lens.emission_enabled = true
	loader.outputs[0]["lens_material_targets"] = [{"material": lens, "beam_optical_profile": {"emission_lumen_scale": 1.5}}]
	service.install_dense_presentation(loader, registry)
	var applier = Applier.new()
	applier.install_schema({"schema_generation": 7, "sections": [
		{"section_type": 2, "row_stride_ints": 3, "row_stride_floats": 5},
		{"section_type": 3, "row_stride_ints": 3, "row_stride_floats": 4},
		{"section_type": 4, "row_stride_ints": 3, "row_stride_floats": 3}]})
	var frame: Dictionary = {
		"schema_generation": 7,
		"descriptors": PackedInt32Array([2,1,0,0,0, 3,1,3,5,0, 4,1,6,9,0]),
		"integers": PackedInt32Array([1,201,2, 1,301,4, 1,401,8]),
		"floats": PackedFloat32Array([0.5,10,8,10,2, 0.2,0.4,0.8,1, 10,20,0.5]),
	}
	# Empty UUID dictionaries prove the dense lighting path needs no fixture lookup.
	var result: Dictionary = applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	test.check(int(result.get("targets_applied", 0)) == 3, "Native dense snapshot accepts all three lighting domains")
	test.check(loader.target_record_reads == 0, "Dense snapshots never retrieve output-record dictionaries")
	test.check(service._snapshot_output_commits.is_empty() and service._target_states.is_empty() and service._committed_output_states.is_empty(), "Normal dense playback creates no legacy state or commit dictionaries")
	for i in range(2):
		var params: Dictionary = loader.anchors[i].get_meta("peraviz_beam_last_params", {})
		test.check(params.get("beam_color") == Color(0.2,0.4,0.8) and is_equal_approx(float(params["beam_intensity"]), 10.0), "Renderer receives final held color and intensity")
		test.check(is_equal_approx(float(params["beam_angle"]),20), "Zoom uses the same final dense state")
		test.check(loader.renderer.get_beam_resource(loader.anchors[i]).visible, "Dark-start projected output activates")
	test.check(not loader.renderer.get_beam_resource(loader.anchors[2]).visible, "Emission-only output never becomes a projected beam")
	test.check(is_equal_approx(loader.anchors[0].light_energy,8.0) and is_equal_approx(loader.anchors[0].spot_angle,10.0), "SpotLight energy and half-angle retain canonical values")
	test.check(is_equal_approx(service._dense_adapter._outputs[0].materials[0].energy,3.0), "Pre-bound material RID receives scaled emission energy")
	var sizes_before: Dictionary = service._dense_adapter.diagnostics()
	for iteration in range(100):
		frame["floats"][0] = float(iteration % 10) / 10.0
		applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	var sizes_after: Dictionary = service._dense_adapter.diagnostics()
	for key in ["state_capacity", "dirty_capacity", "native_buffer_bytes", "packed_buffer_bytes"]:
		test.check(sizes_before[key] == sizes_after[key], "Dense bridge buffers remain bounded: " + key)
	test.check(sizes_after["physical_outputs"] == 3 and sizes_after["dirty_high_water"] == 0, "Trace OFF retains all outputs without sampling dirty high-water")
	test.check(int(service.get_visual_apply_counters()["emitter_output_commit_candidates"]) == 0, "Trace OFF skips diagnostic counters")
	applier.set_performance_trace_enabled(true)
	frame["semantic_payload_conversion_us"] = 7
	frame["floats"][0] = 0.33
	applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	var diagnostics: Dictionary = service._dense_adapter.consume_diagnostics()
	for key in ["native_compose_us", "payload_conversion_us", "compatibility_adapter_us", "renderer_mutation_us"]:
		test.check(int(diagnostics[key]) >= 0, "Trace stage is exposed: " + key)
	test.check(diagnostics["dirty_high_water"] == 3 and diagnostics["last_dirty_outputs"] == 3, "Trace samples native dirty outputs")
	test.check(diagnostics["semantic_payload_conversion_us"] == 7, "Trace keeps the semantic packed conversion boundary separate")
	test.check(service._dense_adapter.consume_diagnostics()["native_dirty_outputs"] == 0, "Trace stage intervals reset without retaining history")
	test.check(service._snapshot_output_commits.is_empty() and service._target_states.is_empty(), "Trace ON also bypasses legacy composition")
	applier.set_render_diagnostic_mode("no-beams")
	frame["floats"][0] = 0.44
	applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	test.check(not loader.renderer.get_beam_resource(loader.anchors[0]).visible, "No-beams suppresses existing beam nodes")
	applier.set_render_diagnostic_mode("full")
	applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	test.check(loader.renderer.get_beam_resource(loader.anchors[0]).visible, "Returning to full replays held state even for equal semantic values")
	var texture := GradientTexture2D.new()
	loader.anchors[0].set_meta("peraviz_gobo_texture", texture)
	service.rebind_dense_light(loader.anchors[0])
	frame["floats"][0] = 0.0
	applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	test.check(loader.anchors[0].light_projector == null, "Dense blackout suppresses held gobo projection")
	frame["floats"][0] = 0.5
	applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	test.check(loader.anchors[0].light_projector == texture, "Dense activation restores held gobo projection")
	# Renderer-only replay keeps held native state and resolves replacement resources once.
	service.refresh_dense_renderer()
	test.check(loader.target_record_reads == 0, "Renderer replay does not rediscover semantic targets")
	frame["schema_generation"] = 6
	var previous: Color = loader.anchors[0].get_meta("peraviz_beam_last_params", {})["beam_color"]
	frame["floats"][5] = 1.0
	result = applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	test.check(int(result["updated"]) == 0 and loader.anchors[0].get_meta("peraviz_beam_last_params", {})["beam_color"] == previous, "Stale native schema snapshots cannot mutate current renderer")
	var vector_loader := DenseLoader.new()
	vector_loader.use_vector_prism = true
	get_root().add_child(vector_loader)
	await process_frame
	var vector_service = Service.new()
	vector_loader.dense_service = vector_service
	var vector_bindings := Bindings.new()
	vector_bindings.outputs = vector_loader.outputs
	vector_service.install_dense_presentation(vector_loader, vector_bindings)
	frame["schema_generation"] = 7
	applier.set_performance_trace_enabled(false)
	applier.apply_snapshot(frame, vector_loader, vector_service, 0.016, null, {})
	var vector_beam: MeshInstance3D = vector_loader.renderer.get_beam_resource(vector_loader.anchors[0])
	var dynamic: Color = vector_beam.get_instance_shader_parameter("beam_dynamic_state")
	test.check(vector_beam.visible and is_equal_approx(dynamic.a,10.0) and is_equal_approx(dynamic.r,1.0), "Vector Gobo Prism retains independent render-ready color/intensity")
	# Optical state is shared through actual packed dense Zoom/mode replay.
	var projection = vector_loader.anchors[0].get_meta(&"peraviz_optical_projection_state")
	var vector_mesh: Mesh = vector_beam.mesh
	for zoom in [8.0, 55.0, 20.0]:
		var before_revision: int = projection.revision
		frame["floats"][9] = zoom * 0.5
		frame["floats"][10] = zoom
		applier.apply_snapshot(frame, vector_loader, vector_service, 0.016, null, {})
		test.check(projection.revision == before_revision + 1, "Dense Zoom resolves one shared revision")
		test.check(projection.shaft_revision == projection.revision and projection.footprint_revision == projection.revision, "Packed dense Zoom synchronizes both consumers")
		test.check(is_equal_approx(vector_loader.anchors[0].spot_angle, zoom * 0.5) and vector_beam.mesh == vector_mesh, "Dense Zoom shares aperture without replacing topology")
	var optical_revision: int = projection.revision
	frame["floats"][5] = 0.37
	applier.apply_snapshot(frame, vector_loader, vector_service, 0.016, null, {})
	test.check(projection.revision == optical_revision, "Dense color-only update leaves optical revision unchanged")
	vector_service.set_render_diagnostic_mode("no-beams")
	frame["floats"][9] = 17.0
	frame["floats"][10] = 34.0
	applier.set_render_diagnostic_mode("no-beams")
	applier.apply_snapshot(frame, vector_loader, vector_service, 0.016, null, {})
	test.check(not vector_beam.visible, "Suppressed optical updates retain hidden shaft")
	vector_service.set_render_diagnostic_mode("full")
	test.check(vector_beam.visible and projection.shaft_revision == projection.revision and projection.footprint_revision == projection.revision and is_equal_approx(vector_loader.anchors[0].spot_angle, 17.0), "Full resumes latest shared Zoom without a fresh DMX packet")
	vector_service.reset_scene_state()
	for anchor in vector_loader.anchors: vector_loader.renderer.cleanup_beam(anchor)
	vector_loader.free()
	vector_service = null
	service.reset_scene_state()
	test.check(service._dense_adapter == null, "Scene reset retires native state and bound handles")
	for anchor in loader.anchors: loader.renderer.cleanup_beam(anchor)
	loader.free()
	service = null
	await process_frame
	test.finish(self)
