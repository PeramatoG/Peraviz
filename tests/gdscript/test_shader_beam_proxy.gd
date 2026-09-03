extends SceneTree

const ControllerScript = preload("res://scripts/beam_renderers/shader_beam_proxy_controller.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var controller = ControllerScript.new()
	var first := SpotLight3D.new()
	var second := SpotLight3D.new()
	get_root().add_child(first)
	get_root().add_child(second)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var params := {"beam_type": "Spot", "beam_range": 12.0, "beam_angle": 8.0, "scaled_intensity": 10.0, "intensity_max": 50.0, "beam_color": Color.RED, "gobo_rotation_deg": 0.0}
	controller.update_for_light(first, params, texture)
	controller.update_for_light(second, params, null)
	var first_proxy := controller.get_proxy(first)
	var second_proxy := controller.get_proxy(second)
	test.check(first_proxy != null and first_proxy.visible, "Active output must create a visible shader proxy")
	test.check(first_proxy.mesh == second_proxy.mesh, "All shader proxies must share one normalized mesh")
	var mesh_identity := first_proxy.mesh
	var material_identity := first_proxy.material_override
	var stable_counters: Dictionary = controller.counters()
	var repeated_result: Dictionary = controller.update_for_light(first, params, texture)
	test.check(not bool(repeated_result.get("changed", true)), "Repeated identical proxy state must perform no writes")
	test.check(int(controller.counters().get("proxy_visibility_transitions", -1)) == int(stable_counters.get("proxy_visibility_transitions", -2)), "Repeated visible proxy state must not toggle visibility")
	for angle in [90.0, 180.0, 270.0]:
		params["gobo_rotation_deg"] = angle
		controller.update_for_light(first, params, texture)
	test.check(first_proxy.mesh == mesh_identity and first_proxy.material_override == material_identity, "Gobo rotation must be uniform-only")
	test.check(int(first_proxy.get_meta("peraviz_shader_beam_proxy_state").get("quality_tier")) == 12, "Narrow beams must select the bounded high sample tier")
	params["beam_angle"] = 40.0
	controller.update_for_light(first, params, texture)
	test.check(int(first_proxy.get_meta("peraviz_shader_beam_proxy_state").get("quality_tier")) == 4, "Wide beams must select the bounded low sample tier")
	params["scaled_intensity"] = 0.0
	controller.update_for_light(first, params, texture)
	test.check(not first_proxy.visible and controller.get_proxy(first) == first_proxy, "Inactive proxies must be hidden and retained")
	var hidden_transitions: int = int(controller.counters().get("proxy_visibility_transitions", 0))
	controller.update_for_light(first, params, texture)
	test.check(int(controller.counters().get("proxy_visibility_transitions", 0)) == hidden_transitions, "Repeated inactive proxy state must remain hidden without a transition")
	first.queue_free()
	second.queue_free()
	await process_frame
	test.finish(self)
