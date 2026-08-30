extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const RegistryScript = preload("res://scripts/runtime/native_gobo_resource_registry.gd")
const FrameApplierScript = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")
const RotationPresentationScript = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	var failures := PackedStringArray()
	_test_protocol_mask(failures)
	_test_rotation_lifecycle(failures)
	if failures.is_empty():
		print("Gobo PosRotate lifecycle checks passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_protocol_mask(failures: PackedStringArray) -> void:
	var applier: RefCounted = FrameApplierScript.new()
	var integers := PackedInt32Array()
	for row in range(30):
		integers.append_array(PackedInt32Array([1000 + row, 2000 + row, 0x40 + row, 1 + (row % 2), 2, 0x20, 700 + row]))
	for row in range(30):
		var mask: int = applier._changed_mask_for_row(15, row * 7, integers)
		_check(mask == 0x20, "Protocol 2.3 GoboRotation must read changed_mask from integer field 5 for every row.", failures)

func _test_rotation_lifecycle(failures: PackedStringArray) -> void:
	var registry: RefCounted = RegistryScript.new()
	var path: String = _write_mask()
	var assets := [{"gobo_asset_id": 101, "wheel_id": 11, "slot_index": 1, "extracted_media_path": path, "media_valid": true}]
	registry.install_or_update_assets(assets)
	var beam := MeshInstance3D.new()
	var light := SpotLight3D.new()
	var target := {"beam_instances": [beam], "emitter_anchors": [light]}
	var targets := {77: target}
	registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	registry.apply_rotation_state(77, 11, 1, 2, 1, 45.0, 30.0, 5.0, 5.0, target, 1000000)
	var mesh_before: Mesh = beam.mesh
	registry.advance_motion_at_usec(3000000, targets)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 105.0), "Continuous presentation should use its local monotonic reference.", failures)
	registry.clear_renderer_targets()
	registry.rehydrate_renderer_state(targets, 4000000)
	_check(beam.mesh == mesh_before, "Renderer rehydration must reuse the selected gobo mesh.", failures)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 135.0), "Renderer rehydration must apply the current continuous phase without new DMX.", failures)
	registry.install_or_update_assets(assets)
	registry.rehydrate_renderer_state(targets, 5000000)
	_check(beam.mesh == mesh_before and is_equal_approx(RotationPresentationScript.physical_angle(beam), 165.0), "Unchanged asset reinstall must preserve cached resources and motion state.", failures)
	registry.apply_rotation_state(77, 11, 1, 2, 1, 0.0, 30.0, 0.0, 0.0, target, 6000000)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 195.0), "A bootstrapped native runtime generation must preserve the renderer-local continuous phase.", failures)
	registry.apply_selection(77, 11, 1, 2, 0, 0, target)
	registry.advance_motion_at_usec(7000000, targets)
	registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	registry.rehydrate_renderer_state(targets, 7000000)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 225.0), "Open-slot motion must resume at the current phase.", failures)
	registry.apply_selection(77, 12, 2, 1, 101, 0, target)
	registry.apply_rotation_state(77, 12, 2, 2, 1, 10.0, -20.0, 5.0, 5.0, target, 1000000)
	var deferred: Dictionary = registry.apply_rotation_state(77, 11, 1, 2, 2, 225.0, 30.0, 5.0, 5.0, target, 7000000)
	_check(bool(deferred.get("unsupported_moving_composition", false)), "Independent motion with two visible layers must remain explicitly deferred.", failures)
	var counters: Dictionary = registry.counters()
	_check(int(counters.get("active_continuous_layers", 0)) == 2 and int(counters.get("deferred_multi_wheel_warnings", 0)) > 0, "Motion diagnostics must expose active and deferred multi-layer state.", failures)
	registry.reset_scene_state()
	_check(int(registry.counters().get("active_continuous_layers", -1)) == 0, "A true new-scene reset must clear obsolete motion state.", failures)
	beam.free()
	light.free()
	DirAccess.remove_absolute(path)

func _write_mask() -> String:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var value: float = 1.0 if x >= 3 and x <= 6 and y >= 2 and y <= 13 else 0.0
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	var path: String = ProjectSettings.globalize_path("user://gobo_posrotate_lifecycle.png")
	image.save_png(path)
	return path

func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
