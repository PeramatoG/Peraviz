extends SceneTree

const RegistryScript = preload("res://scripts/runtime/native_renderer_target_registry.gd")
const RendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class Harness:
	extends Node
	var renderer = RendererScript.new()
	var base := Node3D.new()
	var emitter := Node3D.new()
	var light := SpotLight3D.new()

	func _ready() -> void:
		base.set_meta("peraviz_gdtf_geometry_key", "fixture/Base")
		base.set_meta("peraviz_fixture_uuid", "fixture")
		emitter.set_meta("peraviz_gdtf_geometry_key", "fixture/Base/Beam")
		emitter.set_meta("peraviz_fixture_uuid", "fixture")
		emitter.set_meta("peraviz_is_emitter", true)
		add_child(base)
		base.add_child(emitter)
		emitter.add_child(light)
		renderer.configure(null, {"beam_presentation": 1})

	func collect_emitter_lights(_key: String, _nodes: Array) -> Array:
		return [light]

	func ensure_beam_runtime(spot: SpotLight3D) -> void:
		renderer.ensure_beam(spot)

	func get_beam_resource(spot: SpotLight3D) -> MeshInstance3D:
		return renderer.get_beam_resource(spot)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var harness := Harness.new()
	get_root().add_child(harness)
	await process_frame
	var registry = RegistryScript.new()
	registry.configure({"node_index": {"base": harness.base, "beam": harness.emitter}, "callbacks": {"collect_emitter_lights": Callable(harness, "collect_emitter_lights"), "ensure_beam_runtime": Callable(harness, "ensure_beam_runtime"), "get_beam_resource": Callable(harness, "get_beam_resource")}})
	registry.install_manifest([{"fixture_uuid": "fixture", "targets": [{"semantic": "beam_profile", "geometry_key": "fixture/Base/Beam", "render_target_id": 201, "beam_optical_profile": {"beam_type": "Spot", "has_projected_beam": true}}, {"semantic": "dimmer", "geometry_key": "fixture/Base", "render_target_id": 201}]}])
	var record: Dictionary = registry.get_dimmer_target_record(201)
	var previous: MeshInstance3D = record.get("beam_instances", [])[0] as MeshInstance3D
	harness.renderer.cleanup_beam(harness.light)
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	harness.light.set_meta("peraviz_gobo_texture", ImageTexture.create_from_image(image))
	harness.renderer.update_beam(harness.light, {"beam_type": "Spot", "beam_range": 8.0, "beam_angle": 20.0, "lens_radius": 0.03, "scaled_intensity": 10.0, "intensity_max": 50.0, "beam_color": Color.WHITE})
	var current: MeshInstance3D = harness.renderer.get_beam_resource(harness.light)
	registry.rebind_beam_resource(harness.light, current)
	test.check(current != previous and current.visible and current.mesh != null, "Gobo topology replacement must create a ready current Vector Prism")
	test.check(registry.get_dimmer_target_record(201).get("beam_instances", [])[0] == current, "Native target records must rebind away from the stale beam resource")
	harness.renderer.update_beam_intensity(harness.light, {"beam_type": "Spot", "scaled_intensity": 6.0, "intensity_max": 50.0, "beam_color": Color.RED})
	test.check(current.get_instance_shader_parameter("beam_dynamic_state") == Color(1.0, 0.0, 0.0, 6.0), "Dynamic updates must mutate the rebound current resource")
	var texture: Texture2D = harness.light.get_meta("peraviz_gobo_texture") as Texture2D
	for selected_texture in [null, texture, null, texture]:
		harness.renderer.cleanup_beam(harness.light)
		harness.light.set_meta("peraviz_gobo_texture", selected_texture)
		harness.renderer.update_beam(harness.light, {"beam_type": "Spot", "beam_range": 8.0, "beam_angle": 20.0, "lens_radius": 0.03, "scaled_intensity": 8.0, "intensity_max": 50.0, "beam_color": Color.BLUE})
		current = harness.renderer.get_beam_resource(harness.light)
		registry.rebind_beam_resource(harness.light, current)
		test.check(registry.get_dimmer_target_record(201).get("beam_instances", [])[0] == current and current.visible, "Repeated open and gobo topology replacement must keep the native target current")
	harness.queue_free()
	await process_frame
	test.finish(self)
