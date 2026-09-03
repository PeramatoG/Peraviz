extends SceneTree

const SectionedVisualFrameApplierScript = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")
const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const DmxFixtureRuntimeScript = preload("res://scripts/dmx_fixture_runtime.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class NativePumpGuardReceiver:
	extends RefCounted
	var pump_calls: int = 0
	var forbidden_calls: int = 0
	func is_running() -> bool: return true
	func configure_visual_runtime(_runtime) -> bool: return true
	func pump_visual_runtime(_runtime) -> int:
		pump_calls += 1
		return 0
	func get_dirty_universes() -> PackedInt32Array:
		forbidden_calls += 1
		return PackedInt32Array()
	func consume_universe(_universe: int) -> PackedByteArray:
		forbidden_calls += 1
		return PackedByteArray()
	func get_universe_data(_universe: int) -> PackedByteArray:
		forbidden_calls += 1
		return PackedByteArray()

class FakeLoader:
	extends Node
	const DEFAULT_EMITTER_PHOTOMETRICS: Dictionary = {"luminous_flux": 10000.0, "beam_angle": 25.0, "field_angle": 25.0, "beam_radius": 0.05}
	var pan_node := Node3D.new()
	var tilt_node := Node3D.new()
	var dimmer_node := Node3D.new()
	var dimmer_valid: bool = true
	var dimmer_has_resources: bool = true
	var last_dimmer_light := SpotLight3D.new()
	var last_gobo_rotation: Dictionary = {}

	func _ready() -> void:
		add_child(pan_node)
		add_child(tilt_node)
		add_child(dimmer_node)
		add_child(last_dimmer_light)

	func _apply_native_transform_targets(pan_component_id: int, tilt_component_id: int, pan_degrees: float, tilt_degrees: float) -> Dictionary:
		var result: Dictionary = {"pan_requested": pan_component_id > 0, "pan_applied": false, "tilt_requested": tilt_component_id > 0, "tilt_applied": false, "failed": 0}
		if pan_component_id == 101:
			pan_node.rotation_degrees.y = pan_degrees
			result["pan_applied"] = true
		elif pan_component_id > 0:
			result["failed"] = int(result["failed"]) + 1
		if tilt_component_id == 102:
			tilt_node.rotation_degrees.x = tilt_degrees
			result["tilt_applied"] = true
		elif tilt_component_id > 0:
			result["failed"] = int(result["failed"]) + 1
		return result

	func _apply_native_gobo_rotation_state(beam_target_id: int, wheel_id: int, wheel_instance_index: int, rotation_mode: int, revision: int, phase_degrees: float, angular_velocity_dps: float, reference_seconds: float, native_now_seconds: float) -> Dictionary:
		last_gobo_rotation = {"beam_target_id": beam_target_id, "wheel_id": wheel_id, "wheel_instance_index": wheel_instance_index, "rotation_mode": rotation_mode, "revision": revision, "phase_degrees": phase_degrees, "angular_velocity_dps": angular_velocity_dps, "reference_seconds": reference_seconds, "native_now_seconds": native_now_seconds}
		return {"applied": true}

	func _has_native_dimmer_target(dimmer_target_id: int) -> bool:
		return dimmer_valid and dimmer_target_id == 201

	func _get_native_dimmer_target_record(dimmer_target_id: int) -> Dictionary:
		if not dimmer_valid or dimmer_target_id != 201:
			return {}
		if not dimmer_has_resources:
			return {
				"geometry_nodes": [dimmer_node],
				"emitter_nodes": [],
				"emitter_anchors": [],
				"beam_instances": [],
				"lens_material_targets": [],
				"emitter_photometrics": [],
			}
		return {
			"geometry_nodes": [dimmer_node],
			"emitter_nodes": [dimmer_node],
			"emitter_anchors": [last_dimmer_light],
			"beam_instances": [last_dimmer_light],
			"lens_material_targets": [],
			"emitter_photometrics": [],
		}

	func _get_fixture_geometry_nodes(_fixture_uuid: String) -> Array:
		return [Node3D.new()]

	func _get_fixture_emitter_nodes(_fixture_uuid: String) -> Array:
		return [Node3D.new()]

	func _get_fixture_emitter_photometrics(_fixture_uuid: String) -> Array:
		return []

	func _collect_fixture_emitter_lights(_fixture_uuid: String, _emitter_nodes: Array) -> Array:
		var light := SpotLight3D.new()
		return [light]

	func _collect_fixture_emissive_materials(_fixture_uuid: String, _geometry_nodes: Array) -> Array:
		return []

	func _apply_emitter_light_state(light: SpotLight3D, _photometric: Dictionary, _normalized_dimmer: float, controls: Dictionary = {}) -> void:
		var values: PackedFloat32Array = controls.get("render_ready_values", PackedFloat32Array())
		light.light_energy = values[1] if values.size() >= 2 else 0.0

class FakeNativeSceneLoader:
	extends Node

	func compile_visual_runtime_scene(_universe_offset: int) -> Dictionary:
		return {"renderer_manifest": [], "property_count": 0, "setup_summary": {}}

class FakeRendererTargetRegistry:
	extends Node
	var install_calls: int = 0

	func _register_native_runtime_targets(_renderer_manifest: Array) -> void:
		install_calls += 1

	func _get_native_target_registry_summary() -> Dictionary:
		return {"registry_summary": {}}

	func _apply_native_transform_targets(_pan_component_id: int, _tilt_component_id: int, _pan_degrees: float, _tilt_degrees: float) -> Dictionary:
		return {}

	func _has_native_dimmer_target(_dimmer_target_id: int) -> bool:
		return false

	func _get_native_dimmer_target_record(_dimmer_target_id: int) -> Dictionary:
		return {}

	func _has_native_optics_target(_optics_target_id: int) -> bool:
		return false

	func _get_native_optics_target_record(_optics_target_id: int) -> Dictionary:
		return {}

	func _get_native_target_failure(_target_id: int) -> Variant:
		return null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var applier = SectionedVisualFrameApplierScript.new()
	applier.set_performance_trace_enabled(true)
	applier.install_schema({"sections": [
		{"section_type": 1, "row_stride_ints": 4, "row_stride_floats": 2},
		{"section_type": 2, "row_stride_ints": 3, "row_stride_floats": 5},
		{"section_type": 15, "row_stride_ints": 7, "row_stride_floats": 3},
	]})
	var loader := FakeLoader.new()
	get_root().add_child(loader)
	await process_frame
	var light_apply_service = FixtureLightApplyServiceScript.new()
	var snapshot: Dictionary = {
		"descriptors": PackedInt32Array([1, 1, 0, 0, 0, 2, 1, 4, 2, 0]),
		"integers": PackedInt32Array([1, 101, 102, 1, 1, 201, 2]),
		"floats": PackedFloat32Array([45.0, -30.0, 1.0, 20.0, 20.0, 1.0, 4.0]),
	}
	var result: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	test.check(int(result.get("updated", 0)) == 1, "Native snapshot should update one fixture")
	test.check(is_equal_approx(loader.pan_node.rotation_degrees.y, 45.0), "Native pan should reach the registered component")
	test.check(is_equal_approx(loader.tilt_node.rotation_degrees.x, -30.0), "Native tilt should reach the registered component")
	test.check(loader.last_dimmer_light.light_energy > 0.0, "Native dimmer should update light energy")
	var diagnostics: Dictionary = result.get("skip_diagnostics", {})
	test.check(int(diagnostics.get("dimmer_requested", 0)) == 1, "Dimmer diagnostics should count the request")
	test.check(int(diagnostics.get("dimmer_mutated", 0)) == 1, "Dimmer diagnostics should count the mutation")
	test.check(int(diagnostics.get("dimmer_lights_mutated", 0)) >= 1, "Dimmer diagnostics should count mutated lights")
	var unchanged_result: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	var unchanged_diagnostics: Dictionary = unchanged_result.get("skip_diagnostics", {})
	test.check(int(unchanged_diagnostics.get("dimmer_failed", 0)) == 0, "A resolved Dimmer target already at the requested state must not fail")
	test.check(int(unchanged_diagnostics.get("dimmer_unchanged", 0)) == 0, "A deferred Dimmer row must remain applied until the final output signature guard runs")
	test.check(int(light_apply_service.get_visual_apply_counters().get("emitter_output_commits_signature_skipped", 0)) == 1, "The final output signature guard must record the unchanged renderer commit")
	var energy_before_transforms_only: float = loader.last_dimmer_light.light_energy
	applier.set_render_diagnostic_mode("transforms-only")
	var transforms_only: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	test.check(int(transforms_only.get("skip_diagnostics", {}).get("rows_diagnostic_suppressed", 0)) == 1, "Transforms-only must suppress the intensity row")
	test.check(is_equal_approx(loader.pan_node.rotation_degrees.y, 45.0), "Transforms-only must continue applying Pan")
	test.check(is_equal_approx(loader.last_dimmer_light.light_energy, energy_before_transforms_only), "Transforms-only must not mutate Dimmer renderer state")
	applier.set_render_diagnostic_mode("full")
	var rotation_result: Dictionary = applier.apply_snapshot({"runtime_now_seconds": 12.5, "descriptors": PackedInt32Array([15, 1, 0, 0, 0]), "integers": PackedInt32Array([1, 201, 7001, 1, 2, 32, 9]), "floats": PackedFloat32Array([45.0, -30.0, 12.0])}, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	test.check(int(rotation_result.get("visual_mask_counts", {}).get("changed_gobo_rotation_count", 0)) == 1, "GoboRotation must decode changed mask from integer field 5")
	test.check(loader.last_gobo_rotation == {"beam_target_id": 201, "wheel_id": 7001, "wheel_instance_index": 1, "rotation_mode": 2, "revision": 9, "phase_degrees": 45.0, "angular_velocity_dps": -30.0, "reference_seconds": 12.0, "native_now_seconds": 12.5}, "GoboRotation should decode the exact protocol 2.3 renderer state")
	loader.dimmer_has_resources = false
	var no_resource: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	test.check(int(no_resource.get("skipped", 0)) > 0, "A target without mutable resources should be skipped")
	var no_resource_diagnostics: Dictionary = no_resource.get("skip_diagnostics", {})
	test.check(int(no_resource_diagnostics.get("dimmer_failed", 0)) == 1, "Missing resources should produce a dimmer failure diagnostic")
	loader.dimmer_has_resources = true
	loader.dimmer_valid = false
	var failed: Dictionary = applier.apply_snapshot(snapshot, loader, light_apply_service, 0.016, null, {1: "fixture-a"})
	test.check(int(failed.get("skipped", 0)) > 0, "An unresolved dimmer target should be skipped")
	var runtime = DmxFixtureRuntimeScript.new()
	var native_loader := FakeNativeSceneLoader.new()
	var renderer_registry := FakeRendererTargetRegistry.new()
	runtime.configure(native_loader, null, renderer_registry, null)
	var pump_guard := NativePumpGuardReceiver.new()
	runtime._native_visual_runtime_available = true
	runtime._collect_dmx(pump_guard, Callable())
	test.check(pump_guard.pump_calls == 1 and pump_guard.forbidden_calls == 0, "Production playback must use only the native realtime pump, never raw universe compatibility APIs")
	var required_registry_methods := ["_register_native_runtime_targets", "_get_native_target_registry_summary", "_apply_native_transform_targets", "_has_native_dimmer_target", "_get_native_dimmer_target_record", "_has_native_optics_target", "_get_native_optics_target_record", "_get_native_target_failure"]
	for method_name in required_registry_methods:
		test.check(renderer_registry.has_method(method_name), "Fake renderer registry is missing current contract method: %s" % method_name)
	test.check(runtime._install_renderer_manifest([]), "An empty manifest should install when the complete registry contract is available")
	test.check(renderer_registry.install_calls == 1, "Renderer manifest installation should invoke the registry once")
	loader.free()
	runtime = null
	native_loader.free()
	renderer_registry.free()
	await process_frame
	await process_frame
	test.finish(self)
