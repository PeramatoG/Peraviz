extends RefCounted

# Imported-resource version of the existing footprint presentation experiment.
# Native routes preserve physical composition and actual shaft aggregation. Inputs
# are synthetic resolved presentation rows, not a substitute DMX/GDTF evaluator.
var mechanics: Array[Node3D] = []
var frames: Array[Dictionary] = []
var held: Dictionary
var scope: String

static func run(probe: RefCounted, tree: SceneTree, test: RefCounted, path: String, directory: String) -> void:
	tree.root.disable_3d = false
	test.check(tree.change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "Scene probe loads the normal application")
	await tree.process_frame
	await tree.process_frame
	var app: Node = tree.current_scene
	tree.root.min_size = Vector2i.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--footprint-resolution="):
			var dimensions := arg.trim_prefix("--footprint-resolution=").split("x")
			if dimensions.size() == 2: tree.root.size = Vector2i(maxi(64, int(dimensions[0])), maxi(64, int(dimensions[1])))
	var loaded: Dictionary = await app._load_mvr_scene(path, "mvr", false)
	test.check(bool(loaded.get("ok", false)), "Scene probe imports the supplied MVR")
	if not loaded.get("ok", false):
		app.queue_free()
		await tree.process_frame
		return
	# Pause input/UI ticks for a controlled presentation experiment. No saved setting changes.
	app.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.disable_3d = false
	RenderingServer.viewport_set_measure_render_time(tree.root.get_viewport_rid(), true)
	var registry: RefCounted = app._native_target_registry
	var inputs = load("res://tests/gdscript/helpers/footprint_scene_probe.gd").new()
	# Actual mechanical ancestors, deduplicated once at setup; emitter offsets remain intact.
	for axis in registry._pan_targets.values() + registry._tilt_targets.values():
		if is_instance_valid(axis) and not inputs.mechanics.has(axis): inputs.mechanics.append(axis)
	var bindings: Dictionary = registry.get_dense_presentation_bindings()
	var dimmers: Dictionary = {}
	var colors: Dictionary = {}
	var routes: PackedInt32Array = bindings.routes
	for index in range(0, routes.size(), 3):
		if routes[index] == 2: dimmers[routes[index + 1]] = true
		if routes[index] == 3: colors[routes[index + 1]] = true
	inputs.held = _frame(dimmers.keys(), colors.keys(), 0.8, 0.7)
	for index in range(120):
		var phase := float(index) * TAU / 120.0
		inputs.frames.append(_frame(dimmers.keys(), colors.keys(), 0.8 + 0.15 * sin(phase), 0.7 + 0.25 * cos(phase)))
	inputs.scope = "Production-imported MVR resources sha256=" + FileAccess.get_sha256(path) + "; synthetic resolved Color/Dimmer rows and real mechanical ancestors. Excludes raw DMX/GDTF evaluation, live shutter sampling and externally selected gobo motion. Not an owner-stream replay."
	await preload("res://tests/gdscript/helpers/footprint_live_probe.gd").run(probe, tree, test, tree.root, app, app._fixture_light_apply_service, directory, inputs)
	app._clear_scene()
	app.queue_free()
	await tree.process_frame

static func _frame(dimmers: Array, colors: Array, level: float, red: float) -> Dictionary:
	var integers := PackedInt32Array()
	var floats := PackedFloat32Array()
	for target in dimmers:
		integers.append_array(PackedInt32Array([1, target, 2]))
		floats.append_array(PackedFloat32Array([level, level * 20, level * 16, level * 20, level * 4]))
	var color_integer_offset := integers.size()
	var color_float_offset := floats.size()
	for target in colors:
		integers.append_array(PackedInt32Array([1, target, 4]))
		floats.append_array(PackedFloat32Array([red, 0.8, 0.7, 1.0]))
	return {"descriptors": PackedInt32Array([2, dimmers.size(), 0, 0, 0, 3, colors.size(), color_integer_offset, color_float_offset, 0]), "integers": integers, "floats": floats}
