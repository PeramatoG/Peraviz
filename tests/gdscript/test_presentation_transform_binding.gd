extends SceneTree

const Harness = preload("res://tests/gdscript/helpers/dense_mutation_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const Registry = preload("res://scripts/runtime/native_renderer_target_registry.gd")
const Controller = preload("res://scripts/runtime/presentation_transform_controller.gd")
const Applier = preload("res://scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd")
const Projector = preload("res://scripts/fixture_gobo_projector.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

class TransformProbe extends Node3D:
	var changes: int = 0
	func _ready() -> void: set_notify_transform(true)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSFORM_CHANGED: changes += 1

class Bindings extends RefCounted:
	var loader: Node
	func get_dense_presentation_bindings() -> Dictionary: return loader.get_dense_presentation_bindings()
	func install_transform_controller(controller: RefCounted) -> void: loader.install_transform_controller(controller)

class MotionLoader extends Harness:
	var registry: RefCounted = Registry.new()
	var pan: Node3D
	var tilt: Node3D
	var body: MeshInstance3D
	var sources: Array[Node3D] = []
	func _ready() -> void:
		super._ready()
		pan = Node3D.new()
		pan.set_meta("peraviz_fixture_uuid", "fixture-motion")
		add_child(pan)
		tilt = Node3D.new()
		tilt.set_meta("peraviz_fixture_uuid", "fixture-motion")
		pan.add_child(tilt)
		body = MeshInstance3D.new()
		body.mesh = BoxMesh.new()
		tilt.add_child(body)
		for index in range(anchors.size()):
			var source := Node3D.new()
			source.position = Vector3(index * 0.03, 0.12, -0.07)
			source.rotation = Vector3(0.1, index * 0.01, 0.2)
			source.scale = Vector3(1.1, 0.9, 1.2)
			tilt.add_child(source)
			sources.append(source)
			anchors[index].reparent(source, false)
		for record in outputs: registry._beam_output_records_by_id[record.beam_render_target_id] = record
		registry._pan_targets[101] = pan
		registry._tilt_targets[102] = tilt
	func _apply_native_transform_batch(integers: PackedInt32Array, floats: PackedFloat32Array, ib: int, fb: int, rows: int) -> int:
		return registry.apply_transform_batch(integers, floats, ib, fb, rows)
	func get_dense_presentation_bindings() -> Dictionary:
		var result: Dictionary = super.get_dense_presentation_bindings()
		for index in range(output_count): result.routes.append_array(PackedInt32Array([4,30000 + index,index]))
		return result
	func install_transform_controller(controller: RefCounted) -> void:
		registry.install_transform_controller(controller)

func _init() -> void: call_deferred("run")

func scalar_frame(loader: MotionLoader, level: float, active_count: int = 51) -> Dictionary:
	var frame: Dictionary = loader.frame(level, 0.3)
	for index in range(active_count, loader.output_count):
		for field in range(5): frame.floats[index * 5 + field] = 0.0
	return frame

func intensity_frame(loader: MotionLoader, level: float) -> Dictionary:
	var frame: Dictionary = scalar_frame(loader, level)
	frame.descriptors.resize(5)
	frame.integers.resize(loader.output_count * 3)
	frame.floats.resize(loader.output_count * 5)
	return frame

func apply(applier: RefCounted, loader: MotionLoader, service: RefCounted, frame: Dictionary) -> void:
	var result: Dictionary = applier.apply_snapshot(frame, loader, service, 0.016, null, {})
	test.check(result.get("targets_failed", 0) == 0, "Dense frame applies successfully without fixture string lookup")

func move(applier: RefCounted, loader: MotionLoader, service: RefCounted, pan: float, tilt: float) -> void:
	apply(applier, loader, service, {"descriptors": PackedInt32Array([1,1,0,0,0]),
		"integers": PackedInt32Array([1,101,102,1]), "floats": PackedFloat32Array([pan,tilt])})

func trace(service: RefCounted) -> Dictionary:
	return service._dense_adapter.transforms.consume_diagnostics()

func check_current(loader: MotionLoader, count: int) -> void:
	for index in range(count):
		var light: SpotLight3D = loader.anchors[index]
		var expected: Transform3D = loader.sources[index].global_transform * light.transform
		# Light3D disables scale in its global basis in both ownership modes.
		if light.is_scale_disabled(): expected.basis = expected.basis.orthonormalized()
		test.check(light.global_transform.is_equal_approx(expected), "Current mechanical orientation and unchanged local optics compose immediately")
		var beam: MeshInstance3D = loader.renderer.get_beam_resource(light)
		test.check(beam.global_transform.is_equal_approx(expected * beam.transform), "Visible shaft has exact current world transform")

func run() -> void:
	test.check(Controller.from_arguments(PackedStringArray()) == "active-only", "Trace OFF defaults to active-only production path")
	for mode in ["normal", "mechanical-only", "active-only"]:
		test.check(Controller.from_arguments(PackedStringArray([Controller.ARGUMENT + mode])) == mode, "Explicit application diagnostic parses " + mode)
	var loader := MotionLoader.new()
	loader.output_count = 51
	loader.vector_prism = true
	loader._visual_settings = {"enable_realtime_spotlights": false, "beam_presentation": 1, "footprint_multiplier": 1.0}
	root.add_child(loader)
	await process_frame
	var registry := Bindings.new()
	registry.loader = loader
	var service = Service.new()
	loader.dense_service = service
	service.set_performance_trace_enabled(true)
	test.check(service.install_dense_presentation(loader, registry), "Many-output mechanical fixture installs")
	var applier = Applier.new()
	applier.set_performance_trace_enabled(true)
	applier.install_schema({"sections": [{"section_type": 1, "row_stride_ints": 4, "row_stride_floats": 2},
		{"section_type": 2, "row_stride_ints": 3, "row_stride_floats": 5}, {"section_type": 3, "row_stride_ints": 3, "row_stride_floats": 4}, {"section_type": 4, "row_stride_ints": 3, "row_stride_floats": 3}]})
	apply(applier, loader, service, scalar_frame(loader, 0.0))
	var adapter: RefCounted = service._dense_adapter
	var controller: RefCounted = adapter.transforms
	var original: Transform3D = loader.body.global_transform
	var probes: Array[TransformProbe] = []
	for anchor in loader.anchors:
		var probe := TransformProbe.new()
		anchor.add_child(probe)
		probes.append(probe)
	await process_frame
	for probe in probes: probe.changes = 0
	var notifications: int = loader.notification_count()
	trace(service)
	for iteration in range(1, 101):
		move(applier, loader, service, iteration * 1.1, iteration * 0.6)
		await process_frame
	var dark: Dictionary = trace(service)
	for probe in probes: test.check(probe.changes == 0, "Dark presentation does not receive automatic ancestor transform propagation")
	test.check(loader.notification_count() == notifications and adapter._surface_counts.snapshot().surface_light_activations == 0, "Dark motion has no visibility transitions or surface activations")
	test.check(not loader.body.global_transform.is_equal_approx(original) and is_equal_approx(loader.pan.rotation_degrees.y, 110.0), "Dark fixture body still follows authoritative Pan/Tilt")
	test.check(dark.presentation_transforms_written == 0 and dark.active_bindings == 0 and dark.presentation_transforms_skipped_dark == 5100, "51 dark outputs produce zero presentation writes through 100 movements")
	test.check(dark.fixtures_moved == 1 and dark.moved_pan_tilt_axes == 2 and dark.pan_writes == 100 and dark.tilt_writes == 100, "Trace distinguishes unique fixtures/axes from actual writes")
	test.check(dark.spotlight_anchors_under_moved_axes == 51 and dark.dark_beam_meshes_under_moved_axes == 51 and dark.fixture_body_meshes_under_moved_axes == 1, "Static hierarchy audit includes dark shafts and retained body")
	for handle in adapter._outputs:
		test.check(not handle.lights[0].beam.visible and not handle.lights[0].realtime_visible, "Dark motion cannot activate shaft or surface light")
	# Keep latest Zoom/color held while dark, then send intensity alone.
	apply(applier, loader, service, {"descriptors": PackedInt32Array([4,1,0,0,0]), "integers": PackedInt32Array([1,30000,8]), "floats": PackedFloat32Array([14.0,28.0,0.5])})
	# An intensity-only frame reactivates held presentation at the current pose.
	apply(applier, loader, service, intensity_frame(loader, 0.7))
	var held: Dictionary = loader.anchors[0].get_meta("peraviz_beam_last_params")
	test.check(is_equal_approx(held.beam_angle, 28.0) and held.beam_color.is_equal_approx(Color(0.3,0.0,0.7)), "Reactivation restores latest held color/Zoom without fresh color/Zoom DMX")
	check_current(loader, 51)
	test.check(trace(service).presentation_transforms_written == 51, "Reactivation resolves all current transforms without fresh Pan/Tilt")
	# Same final pose, same frame and different camera produce no transform writes.
	move(applier, loader, service, 110.0, 60.0)
	test.check(trace(service).pan_writes == 0, "Effective mechanical writes also skip unchanged values")
	var camera := Camera3D.new()
	loader.add_child(camera)
	for iteration in range(10):
		camera.position.x = iteration * 3.0
		service.synchronize_presentation_transforms()
	test.check(trace(service).presentation_transforms_written == 0, "Camera movement cannot dirty or write presentation transforms")
	apply(applier, loader, service, scalar_frame(loader, 0.6, 3))
	trace(service)
	move(applier, loader, service, -42.0, 31.0)
	var mixed: Dictionary = trace(service)
	test.check(mixed.presentation_transforms_written == 3 and mixed.active_shafts_moved == 3 and mixed.presentation_transforms_skipped_dark == 48, "Only three active outputs synchronize from a 51-output fixture")
	check_current(loader, 3)
	# Genuine gobo projector, roll and Zoom retain the existing shared optical authority.
	var light: SpotLight3D = loader.anchors[0]
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	light.set_meta("peraviz_gobo_texture", texture)
	var projector = Projector.new()
	projector._set_light_projector_texture(light, texture)
	service.rebind_dense_light(light)
	projector.set_presentation_rotation(light, 37.0)
	service.refresh_dense_renderer()
	trace(service)
	move(applier, loader, service, 70.0, -21.0)
	var gobo: Dictionary = trace(service)
	test.check(gobo.active_projectors_moved == 1 and adapter._outputs[0].lights[0].realtime_visible, "Genuine projector follows Pan/Tilt; open outputs stay surface-inactive")
	check_current(loader, 3)
	var projection: RefCounted = light.get_meta("peraviz_optical_projection_state")
	test.check(is_equal_approx(projection.gobo_roll_deg, 37.0) and projection.footprint_revision == projection.shaft_revision, "Gobo roll and Optical Projection State stay synchronized")
	loader._visual_settings.beam_multiplier = 0.0
	service.refresh_dense_renderer()
	trace(service)
	move(applier, loader, service, 71.0, -20.0)
	var projector_only: Dictionary = trace(service)
	test.check(projector_only.presentation_transforms_written == 1 and projector_only.active_projectors_moved == 1 and projector_only.active_shafts_moved == 0, "Only genuine projector pays transform cost when shafts are disabled")
	loader._visual_settings.beam_multiplier = 20.0
	service.refresh_dense_renderer()
	controller.synchronize()
	var audit_builds: int = controller.audit_builds
	for iteration in range(10):
		projector.set_presentation_rotation(light, 37.0 + iteration)
		service.rebind_dense_light(light)
		controller.synchronize()
	test.check(controller.audit_builds == audit_builds, "Continuous gobo/control callbacks never enumerate SceneTree without resource replacement")
	# A console Grand Master sends zero intensity rows; it does not stop Pan/Tilt.
	apply(applier, loader, service, scalar_frame(loader, 0.0))
	trace(service)
	move(applier, loader, service, 100.0, 22.0)
	var blackout: Dictionary = trace(service)
	test.check(blackout.presentation_transforms_written == 0 and blackout.active_bindings == 0 and is_equal_approx(loader.pan.rotation_degrees.y, 100.0), "Grand Master blackout suppresses presentation work and preserves motion")
	apply(applier, loader, service, scalar_frame(loader, 0.6, 3))
	check_current(loader, 3)
	test.check(adapter._outputs[0].lights[0].realtime_visible, "Grand Master restore reactivates held projector without Pan/Tilt DMX")
	# Rebuild retires the entire generation and restores original local hierarchy.
	var old_carrier: Node3D = controller.bindings[0].carrier
	service.reset_scene_state()
	test.check(controller.bindings.is_empty() and not is_instance_valid(old_carrier) and light.get_parent() == loader.sources[0], "Scene reset releases carriers and stale bindings")
	test.check(service.install_dense_presentation(loader, registry), "Fresh generation rebinds original emitter sources")
	apply(applier, loader, service, scalar_frame(loader, 0.4, 3))
	move(applier, loader, service, -12.0, 6.0)
	check_current(loader, 3)
	service.reset_scene_state()
	for anchor in loader.anchors: loader.renderer.cleanup_beam(anchor)
	loader.free()
	await process_frame
	await check_diagnostic_modes()
	test.finish(self)

func check_diagnostic_modes() -> void:
	for mode in ["normal", "mechanical-only"]:
		var source := Node3D.new()
		root.add_child(source)
		var body := MeshInstance3D.new()
		body.mesh = BoxMesh.new()
		source.add_child(body)
		var light := SpotLight3D.new()
		source.add_child(light)
		var controller = Controller.new()
		controller.mode = mode
		var binding: RefCounted = controller.bind(light, 1, 0)
		controller.set_active(binding, true, false, false)
		var before: Transform3D = light.global_transform
		source.rotation.y = 0.7
		controller.synchronize()
		test.check(not body.global_transform.is_equal_approx(Transform3D.IDENTITY), "Diagnostic keeps physical body motion: " + mode)
		test.check(light.global_transform.is_equal_approx(before) == (mode == "mechanical-only"), "Only mechanical-only freezes presentation inheritance")
		controller.clear()
		source.free()
		await process_frame
