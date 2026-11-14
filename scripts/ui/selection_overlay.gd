extends Control

var camera: Camera3D
var selection: SceneSelection
var _points := PackedVector3Array()
var _edges := PackedInt32Array()
var _previous_camera := Transform3D()

func configure(view_camera: Camera3D, state: SceneSelection) -> void:
	camera = view_camera
	selection = state
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points.resize(8)
	selection.changed.connect(_selection_changed)
	set_process(false)

func _selection_changed() -> void:
	var bounds := selection.bounds()
	_edges.clear()
	for i in range(8): _points[i] = bounds.get_endpoint(i)
	for i in range(8):
		for j in range(i + 1, 8):
			var delta := _points[i] - _points[j]
			var axes: int = int(not is_zero_approx(delta.x)) + int(not is_zero_approx(delta.y)) + int(not is_zero_approx(delta.z))
			if axes == 1:
				_edges.append(i)
				_edges.append(j)
	set_process(not selection.ids.is_empty())
	queue_redraw()

func _process(_delta: float) -> void:
	if camera.global_transform != _previous_camera:
		_previous_camera = camera.global_transform
		queue_redraw()

func _draw() -> void:
	if selection == null or selection.ids.is_empty(): return
	for edge in range(0, _edges.size(), 2):
		var start: Vector3 = _points[_edges[edge]]
		var end: Vector3 = _points[_edges[edge + 1]]
		if camera.is_position_behind(start) or camera.is_position_behind(end): continue
		draw_line(camera.unproject_position(start) - global_position, camera.unproject_position(end) - global_position, Color(0.36, 0.75, 1.0), 1.5, true)
