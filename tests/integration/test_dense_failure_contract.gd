extends SceneTree

# Deliberate negative cases. The Python startup checker requires exactly the
# expected diagnostic and marker, and rejects any parse/compile/runtime errors.
const Harness = preload("res://tests/gdscript/helpers/dense_mutation_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const Legacy = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")

class Bindings extends RefCounted:
	var loader: Node
	var invalid: bool = false
	func get_dense_presentation_bindings() -> Dictionary:
		if invalid:
			return {"ids":PackedInt32Array([1,1]),"scales":PackedFloat32Array([1,1]),"routes":PackedInt32Array(),"outputs":[]}
		return loader.get_dense_presentation_bindings()

class BrokenRenderer extends Legacy:
	var initialization_requests: int = 0
	func update_beam(_light: SpotLight3D, _params: Dictionary) -> void:
		initialization_requests += 1 # Intentionally leave mesh null.
	func apply_beam_optics(_light: SpotLight3D, _params: Dictionary) -> Dictionary:
		return {"applied":false}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var loader := Harness.new()
	loader.output_count = 1
	get_root().add_child(loader)
	await process_frame
	var service = Service.new()
	loader.dense_service = service
	service.set_performance_trace_enabled(true)
	var bindings := Bindings.new()
	bindings.loader = loader
	var passed: bool = true
	if OS.get_cmdline_user_args().has("--installation"):
		bindings.invalid = true
		passed = not await service.install_dense_presentation(loader,bindings)
		passed = passed and not await service.install_dense_presentation(loader,bindings)
		passed = passed and not service.is_dense_presentation_active()
		passed = passed and service.compose_dense_snapshot(PackedInt32Array(),PackedInt32Array(),PackedFloat32Array()) == -1
		passed = passed and service._target_states.is_empty() and service._snapshot_output_commits.is_empty()
	else:
		loader.renderer.cleanup_beam(loader.anchors[0])
		await process_frame
		var broken := BrokenRenderer.new()
		loader.renderer = broken
		loader._active_beam_renderer = broken
		broken.ensure_beam(loader.anchors[0])
		passed = await service.install_dense_presentation(loader,bindings)
		broken.initialization_requests = 0
		service._dense_adapter.consume_diagnostics()
		for i in range(30):
			var frame: Dictionary = loader.frame(0.5+float(i)/100.0,0.2)
			service.begin_visual_snapshot()
			service.compose_dense_snapshot(frame["descriptors"],frame["integers"],frame["floats"])
			service.end_visual_snapshot()
		var diagnostics: Dictionary = service._dense_adapter.consume_diagnostics()
		passed = passed and broken.initialization_requests == 1
		passed = passed and diagnostics["beam_initializations"] == 1 and diagnostics["beam_initialization_failed"] == 1 and diagnostics["beam_initialization_succeeded"] == 0
	service.reset_scene_state()
	loader.renderer.cleanup_beam(loader.anchors[0])
	loader.free()
	service = null
	await process_frame
	if passed: print("EXPECTED_FAILURE_CONTRACT_PASSED")
	quit(0 if passed else 1)
