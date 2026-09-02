extends SceneTree

const ControllerScript = preload("res://scripts/shared_haze_controller.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var owner := Node3D.new()
	get_root().add_child(owner)
	var controller = ControllerScript.new()
	var bounds := AABB(Vector3(-10.0, -2.0, -8.0), Vector3(20.0, 12.0, 16.0))
	var settings := {"shared_haze_density": 0.015, "shared_haze_margin": 5.0}
	for _index in range(100):
		controller.update(owner, bounds, true, settings)
	var volume: FogVolume = controller.get_volume()
	test.check(volume != null and owner.get_child_count() == 1, "Shared Haze must own exactly one scene-level FogVolume")
	test.check(volume.shape == RenderingServer.FOG_VOLUME_SHAPE_BOX and volume.size == bounds.size + Vector3.ONE * 10.0, "Shared Haze must auto-size from scene bounds plus margin")
	test.check(volume.material is FogMaterial and is_equal_approx((volume.material as FogMaterial).density, 0.015), "Shared Haze must use a neutral FogMaterial density")
	controller.update(owner, bounds, false, settings)
	test.check(not volume.visible and controller.get_volume() == volume, "Vector mode must hide rather than recreate the shared haze")
	controller.update(owner, bounds, true, settings)
	test.check(controller.get_volume() == volume and volume.visible, "Both Shared Haze modes must reuse the same volume")
	controller.clear()
	owner.queue_free()
	await process_frame
	test.finish(self)
