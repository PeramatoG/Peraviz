extends SceneTree

const RegistryScript = preload("res://scripts/runtime/native_gobo_resource_registry.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")
const RotationPresentationScript = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")

var test = HeadlessTestCaseScript.new()

class PresentationSink:
	extends RefCounted
	var texture: Texture2D
	var rotation_degrees: float = NAN
	var calls: int = 0

	func present(_light: SpotLight3D, resolved_texture: Texture2D, resolved_rotation_degrees: float) -> void:
		texture = resolved_texture
		rotation_degrees = resolved_rotation_degrees
		calls += 1

func _init() -> void:
	var failures := PackedStringArray()
	var registry: RefCounted = RegistryScript.new()
	var presentation_sink := PresentationSink.new()
	registry.set_presentation_callback(Callable(presentation_sink, "present"))
	var paths := [_write_mask("gobo_a.png", false), _write_mask("gobo_b.png", true)]
	registry.install_assets([
		{"gobo_asset_id": 101, "wheel_id": 11, "slot_index": 1, "extracted_media_path": paths[0], "media_valid": true},
		{"gobo_asset_id": 102, "wheel_id": 12, "slot_index": 1, "extracted_media_path": paths[1], "media_valid": true},
	])
	var beam := MeshInstance3D.new()
	var light := SpotLight3D.new()
	var target := {"beam_instances": [beam], "emitter_anchors": [light]}
	var first: Dictionary = registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	var first_mesh: Mesh = beam.mesh
	_check(bool(first.get("applied", false)) and first_mesh != null, "One native asset should install a normalized prism.", failures)
	_check(presentation_sink.texture == light.get_meta("peraviz_gobo_texture", null), "Native selection must bridge the authoritative texture to presentation.", failures)
	var light_basis: Basis = light.transform.basis
	var topology_before_pos: int = int(registry.counters().get("topology_resource_updates", 0))
	registry.apply_indexed_rotation(77, 11, 1, 45.0, target)
	_check(is_equal_approx(presentation_sink.rotation_degrees, 45.0), "Native indexed rotation must bridge the authoritative physical angle.", failures)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), 45.0), "+45 degrees should remain an unoffset physical Pos value.", failures)
	_check(beam.mesh == first_mesh and light.transform.basis == light_basis, "Pos must reuse the mesh and leave SpotLight orientation unchanged.", failures)
	registry.apply_indexed_rotation(77, 11, 1, -45.0, target)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), -45.0), "Negative Pos should preserve the opposite physical angle.", failures)
	RotationPresentationScript.reapply_after_base_alignment(beam)
	_check(is_equal_approx(RotationPresentationScript.physical_angle(beam), -45.0), "Renderer refresh should preserve indexed Pos.", failures)
	_check(int(registry.counters().get("topology_resource_updates", 0)) == topology_before_pos, "Pos-only changes must not update topology.", failures)
	var shader_beam := MeshInstance3D.new()
	var shader_material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; instance uniform float gobo_rotation_deg = 0.0; void fragment() { ALBEDO = vec3(gobo_rotation_deg / 360.0); }"
	shader_material.shader = shader
	shader_beam.material_override = shader_material
	var shader_light := SpotLight3D.new()
	shader_light.set_meta("peraviz_last_beam_renderer_mode", "volumetric_cone")
	var shader_target := {"beam_instances": [shader_beam], "emitter_anchors": [shader_light]}
	registry.apply_selection(99, 11, 1, 1, 101, 0, shader_target)
	registry.apply_indexed_rotation(99, 11, 1, 30.0, shader_target)
	RotationPresentationScript.reapply_after_base_alignment(shader_beam, 180.0)
	_check(is_equal_approx(float(shader_beam.get_instance_shader_parameter("gobo_rotation_deg")), 210.0), "Volumetric shader path should combine base alignment with positive source-oriented Pos exactly once.", failures)
	var unchanged: Dictionary = registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	_check(bool(unchanged.get("unchanged", false)) and beam.mesh == first_mesh, "Unchanged selection should preserve topology identity.", failures)
	registry.apply_selection(77, 12, 2, 1, 102, 0, target)
	var composed_mesh: Mesh = beam.mesh
	_check(composed_mesh != null and composed_mesh != first_mesh, "Two static wheels should create one composed topology.", failures)
	registry.apply_selection(88, 11, 1, 1, 101, 0, target)
	registry.apply_selection(88, 12, 2, 1, 102, 0, target)
	_check(beam.mesh == composed_mesh, "Equivalent fixtures should reuse composed topology.", failures)
	var counters: Dictionary = registry.counters()
	_check(int(counters.get("composed_png_generations", 0)) == 1 and int(counters.get("composed_vectorizations", 0)) == 1 and int(counters.get("composed_mesh_creations", 0)) == 1, "A unique composition should generate, vectorize, and mesh exactly once.", failures)
	_check(int(counters.get("composition_cache_hits", 0)) == 1 and int(counters.get("composed_topology_reuse", 0)) == 1, "Equivalent composition should hit both resource and topology caches.", failures)
	registry.apply_selection(77, 11, 1, 2, 0, 0, target)
	var other_wheel_basis: Basis = beam.transform.basis
	registry.apply_indexed_rotation(77, 11, 1, 90.0, target)
	_check(beam.transform.basis == other_wheel_basis, "An open Gobo1 Pos must not rotate the visible Gobo2 layer.", failures)
	registry.apply_selection(77, 12, 2, 2, 0, 0, target)
	_check(beam.mesh == null, "Open slots should deterministically clear the prism.", failures)
	_check(not light.has_meta("peraviz_gobo_texture") and presentation_sink.texture == null, "Open slots must clear native gobo presentation state.", failures)
	beam.free()
	light.free()
	shader_beam.free()
	shader_light.free()
	for path in paths:
		DirAccess.remove_absolute(path)
	if failures.is_empty():
		print("Native gobo resource registry checks passed: ", counters)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _write_mask(file_name: String, invert: bool) -> String:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			# Asymmetric masks make presentation rotation observable instead of hiding axis errors behind circles.
			var inside: bool = (x >= 3 and x <= 5 and y >= 2 and y <= 13) or (x >= 3 and x <= 12 and y >= 11 and y <= 13)
			if invert:
				inside = y >= 3 and y <= 12 and x >= 3 and x <= y - 1
			var value: float = 1.0 if inside else 0.0
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	var path: String = ProjectSettings.globalize_path("user://" + file_name)
	image.save_png(path)
	return path

func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
