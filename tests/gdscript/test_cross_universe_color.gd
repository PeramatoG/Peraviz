extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _init() -> void:
	_run.call_deferred()

# Uses the existing packed native setup contract; effective routing is already compiled.
func _scene() -> Dictionary:
	var values := PackedInt32Array([6,1,3,0,1,0,0,0,0,0, 1,0,511,0,0,1])
	for color in range(3):
		values.append_array(PackedInt32Array([color+1,12+color,1,0,255,2,3,0, 1 if color == 2 else 0,0 if color == 2 else 510+color,0]))
	values.append_array(PackedInt32Array([2,1,3,0,1,3]))
	for color in range(3):
		values.append_array(PackedInt32Array([color+1,12+color,2,1,0,0]))
	return {"integers":values,"floats":PackedFloat32Array([10000,25,0,1])}

func _color(frame: Dictionary) -> PackedFloat32Array:
	var descriptors: PackedInt32Array = frame.descriptors
	for d in range(0,descriptors.size(),5):
		if descriptors[d] == 3:
			test.check(descriptors[d+1] == 1,"One cross-universe emitter produces one Color row")
			var values: PackedFloat32Array = frame.floats
			return values.slice(descriptors[d+3],descriptors[d+3]+4)
	return PackedFloat32Array()

func _same(values: PackedFloat32Array, expected: PackedFloat32Array) -> bool:
	if values.size() != expected.size(): return false
	for i in values.size():
		if not is_equal_approx(values[i],expected[i]): return false
	return true

func _run() -> void:
	var runtime := PeravizVisualRuntime.new()
	runtime.install_compiled_scene(_scene())
	var first := PackedByteArray()
	var second := PackedByteArray()
	first.resize(512)
	second.resize(512)
	first[510] = 255
	runtime.submit_universe_frame(1,second)
	runtime.submit_universe_frame(0,first)
	var color := _color(runtime.consume_latest_visual_frame())
	test.check(_same(color,PackedFloat32Array([1,0,0,1])),"Held RGB starts red across the universe boundary")
	second[0] = 255
	runtime.submit_universe_frame(1,second)
	color = _color(runtime.consume_latest_visual_frame())
	test.check(_same(color,PackedFloat32Array([1,0,1,1])),"Blue-only universe update retains red from the previous universe")
	first[510] = 0
	second[0] = 128
	runtime.submit_universe_frame(1,second)
	runtime.submit_universe_frame(0,first)
	color = _color(runtime.consume_latest_visual_frame())
	test.check(_same(color,PackedFloat32Array([0,0,1,128.0/255.0])),"One final renderer-ready blue row includes both latest universes and implicit intensity")
	runtime.submit_universe_frame(1,second)
	test.check(_color(runtime.consume_latest_visual_frame()).is_empty(),"Unchanged held universe does not dirty the renderer")
	test.finish(self)
