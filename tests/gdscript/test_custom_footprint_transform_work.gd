extends SceneTree

const Volume = preload("res://scripts/beam_renderers/custom_footprint_volume.gd")
const Optical = preload("res://scripts/runtime/optical_projection_state.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var mechanical := Node3D.new()
	root.add_child(mechanical)
	var volumes: Array = []
	for index in range(128):
		var anchor := Node3D.new()
		mechanical.add_child(anchor)
		# Half the physical emitters move about a common origin; half retain offsets.
		if index >= 64: anchor.position = Vector3(float(index) * 0.02, 0.1, -0.2)
		var state := Optical.new()
		state.configure({"beam_angle":25.0}, null)
		var volume := Volume.new()
		anchor.add_child(volume)
		volume.configure(state, 20.0)
		test.check(volume.work_counts().custom_uniform_writes == 0, "Tracing is opt-in")
		for elapsed in volume.cpu_times().values(): test.check(elapsed == 0, "Fine clocks are opt-in independently of tracing")
		volume.trace_enabled = true
		volumes.append(volume)
	await process_frame
	for tick in range(60):
		mechanical.rotation.y = float(tick + 1) * 0.01
		for volume in volumes:
			var before: Dictionary = volume.work_counts()
			# Optical refresh can precede the queued ancestor notification.
			volume.sync()
			volume.force_update_transform()
			var after: Dictionary = volume.work_counts()
			var anchor: Node3D = volume.get_parent()
			var inverse: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
			var origin: Vector3 = volume.material_override.get_shader_parameter("projector_origin")
			test.check((inverse * anchor.global_transform).is_equal_approx(Transform3D.IDENTITY) and origin == anchor.global_position, "Every physical emitter keeps its inverse and exact origin")
			test.check(after.custom_world_changes - before.custom_world_changes == 1 and after.custom_inverse_writes - before.custom_inverse_writes == 1, "Shared ancestry still updates every distinct physical projector")
			test.check(after.custom_origin_writes - before.custom_origin_writes == (0 if anchor.position == Vector3.ZERO else 1), "Only exactly changed origins submit")
			test.check(after.custom_bounds_recomputations - before.custom_bounds_recomputations == 1, "Explicit sync and queued notification do not repeat bounds work")
		await process_frame
	# Translation and a tiny representable displacement retain immediate updates.
	for displacement in [Vector3(1,2,3), Vector3(0.0001,0,0)]:
		mechanical.position += displacement
		for volume in volumes:
			var before: int = volume.work_counts().custom_origin_writes
			volume.force_update_transform()
			test.check(volume.work_counts().custom_origin_writes == before + 1, "Necessary translated origins are never throttled")
	# Local Zoom/raster edits must still recompute bounds when world is unchanged.
	var volume: MeshInstance3D = volumes[0]
	volume.set_receiver_bounds(AABB(Vector3(-10,-10,-10), Vector3.ONE * 20), true)
	var before: int = volume.work_counts().custom_bounds_recomputations
	volume.projection.configure({"beam_angle":12.0}, null)
	volume.sync()
	test.check(volume.work_counts().custom_bounds_recomputations == before + 1, "Unchanged world still refreshes changed aperture bounds")
	volume.force_update_transform()
	var writes: int = volume.work_counts().custom_uniform_writes
	volume.sync()
	volume.force_update_transform()
	test.check(volume.work_counts().custom_uniform_writes == writes, "Held matrices and origins submit nothing")
	# Fine profiling must observe the same real operations, without changing them.
	var before_cpu: Dictionary = volume.cpu_times()
	volume.profile_enabled = true
	for tick in range(128):
		mechanical.rotation.x += 0.001
		volume.force_update_transform()
	var after_cpu: Dictionary = volume.cpu_times()
	test.check(after_cpu.notification_us > before_cpu.notification_us and after_cpu.world_check_us > before_cpu.world_check_us, "Fine clocks measure actual notifications and world work")
	var profiled: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
	test.check((profiled * volume.get_parent().global_transform).is_equal_approx(Transform3D.IDENTITY), "Profiling preserves the exact current projection")
	volume.profile_enabled = false
	mechanical.rotation.x += 0.001
	volume.force_update_transform()
	test.check(volume.cpu_times() == after_cpu, "Disabling profiling stops all fine clock accumulation")
	mechanical.free()
	await process_frame
	test.finish(self)
