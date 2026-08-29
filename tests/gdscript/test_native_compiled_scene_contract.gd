extends SceneTree

const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _program(program_id: int, semantic: int, offsets: Array[int], physical_from_index: int, physical_to_index: int) -> Array[int]:
	var row: Array[int] = [program_id, semantic, offsets.size(), 0, 65535 if offsets.size() == 2 else 255, physical_from_index, physical_to_index, 0]
	for byte_order in offsets.size():
		row.append_array([0, offsets[byte_order], byte_order])
	return row

func _program_v7(program_id: int, semantic: int, offsets: Array[int], physical_from_index: int, physical_to_index: int) -> Array[int]:
	var row: Array[int] = [program_id, semantic, offsets.size(), 0, 65535 if offsets.size() == 2 else 255, physical_from_index, physical_to_index, 0, 0, 0, 0, 1, 0, 0]
	for byte_order in offsets.size():
		row.append_array([0, offsets[byte_order], byte_order])
	return row

func _property(property_id: int, component_id: int, target_id: int, semantic: int, program_id: int, weight_index: int) -> Array[int]:
	return [property_id, 1, component_id, target_id, semantic, 1, program_id, weight_index, 0]

func _run() -> void:
	var runtime := PeravizVisualRuntime.new()
	var floats := PackedFloat32Array([10000.0, 25.0, -270.0, 270.0, -135.0, 135.0, 0.0, 1.0, 1.0])
	var values: Array[int] = [6, 1, 3, 3, 0, 0, 0, 0, 0, 0]
	values.append_array([1, 0, 1, 0, 0, 1])
	values.append_array(_program(10, 1, [0, 1], 2, 3))
	values.append_array(_program(11, 2, [2, 3], 4, 5))
	values.append_array(_program(12, 3, [4], 6, 7))
	values.append_array(_property(100, 101, 101, 1, 10, 8))
	values.append_array(_property(101, 102, 102, 2, 11, 8))
	values.append_array(_property(102, 103, 201, 3, 12, 8))
	runtime.install_compiled_scene({"integers": PackedInt32Array(values), "floats": floats})
	var schema: Dictionary = runtime.get_visual_frame_schema()
	var section_types: Array[int] = []
	for section: Dictionary in schema.get("sections", []):
		section_types.append(int(section.get("section_type", 0)))
	test.check(section_types.has(1), "Contract v6 should install GeometryTransform")
	test.check(section_types.has(2), "Contract v6 should install EmitterIntensity")
	var dmx := PackedByteArray([0, 0, 0, 0, 0])
	runtime.submit_universe_frame(0, dmx)
	runtime.consume_latest_visual_frame()
	dmx = PackedByteArray([255, 255, 128, 0, 255])
	runtime.submit_universe_frame(0, dmx)
	var frame: Dictionary = runtime.consume_latest_visual_frame()
	var descriptors: PackedInt32Array = frame.get("descriptors", PackedInt32Array())
	var emitted_types: Array[int] = []
	for index in range(0, descriptors.size(), 5):
		emitted_types.append(descriptors[index])
	test.check(emitted_types.has(1), "Contract v6 DMX should emit GeometryTransform")
	test.check(emitted_types.has(2), "Contract v6 DMX should emit EmitterIntensity")
	var stats: Dictionary = runtime.get_stats()
	test.check(int(stats.get("packets_submitted", 0)) == 2, "Native runtime should accept both universe frames")
	test.check(int(stats.get("changed_transform", 0)) > 0, "Native runtime should dirty transform state")
	test.check(int(stats.get("changed_dimmer", 0)) > 0, "Native runtime should dirty dimmer state")
	_test_v7_contract()
	test.finish(self)

func _test_v7_contract() -> void:
	var runtime := PeravizVisualRuntime.new()
	var floats := PackedFloat32Array([10000.0, 25.0, -270.0, 270.0, -135.0, 135.0, 0.0, 1.0, 10.0, 50.0, -180.0, 180.0, 1.0])
	var values: Array[int] = [7, 1, 6, 4, 0, 0, 0, 1, 1, 1, 0]
	values.append_array([1, 0, 1, 0, 0, 1])
	values.append_array(_program_v7(10, 1, [0, 1], 2, 3))
	values.append_array(_program_v7(11, 2, [2, 3], 4, 5))
	values.append_array(_program_v7(12, 3, [4], 6, 7))
	values.append_array(_program_v7(13, 4, [5], 8, 9))
	values.append_array(_program_v7(14, 0, [6], 6, 7))
	values.append_array(_program_v7(15, 0, [7], 10, 11))
	values.append_array(_property(100, 101, 101, 1, 10, 12))
	values.append_array(_property(101, 102, 102, 2, 11, 12))
	values.append_array(_property(102, 103, 201, 3, 12, 12))
	values.append_array(_property(103, 104, 201, 4, 13, 12))
	values.append_array([5001, 7001, 1, 0, 1])
	values.append_array([9001, 1, 201, 7001, 1, 14, 0, 1, 0, 255, 1])
	values.append_array([9101, 1, 201, 7001, 1, 15, 10, 3, 10, 11, 1, 0, 1])
	runtime.install_compiled_scene({"integers": PackedInt32Array(values), "floats": floats})
	var section_types: Array[int] = []
	for section: Dictionary in runtime.get_visual_frame_schema().get("sections", []):
		section_types.append(int(section.get("section_type", 0)))
	for expected in [1, 2, 4, 14, 15]:
		test.check(section_types.has(expected), "Contract v7 should install section %d" % expected)
	var dmx := PackedByteArray()
	dmx.resize(8)
	dmx[6] = 255
	runtime.submit_universe_frame(0, dmx)
	runtime.consume_latest_visual_frame()
	dmx[0] = 255
	dmx[1] = 255
	dmx[2] = 128
	dmx[4] = 255
	dmx[5] = 255
	dmx[7] = 255
	runtime.submit_universe_frame(0, dmx)
	var frame: Dictionary = runtime.consume_latest_visual_frame()
	var emitted: Array[int] = []
	var descriptors: PackedInt32Array = frame.get("descriptors", PackedInt32Array())
	for index in range(0, descriptors.size(), 5):
		emitted.append(descriptors[index])
	for expected in [1, 2, 4, 15]:
		test.check(emitted.has(expected), "Contract v7 DMX should emit section %d" % expected)
