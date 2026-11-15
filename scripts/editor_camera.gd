extends Camera3D

signal fit_scene_requested

@export var orbit_sensitivity: float = 0.01
@export var pan_sensitivity: float = 0.01
@export var zoom_step_factor: float = 1.1
@export var min_distance: float = 0.5
@export var max_distance: float = 500.0
@export var smoothing_speed: float = 12.0

var _default_min_distance: float = 0.5
var _default_max_distance: float = 500.0
var _default_near: float = 0.05
var _default_far: float = 4000.0

var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var target_pitch: float = -0.3
var target_distance: float = 8.0

var target_roll: float = 0.0
var current_roll: float = 0.0

var current_yaw: float = 0.0
var current_pitch: float = -0.3
var current_distance: float = 8.0

enum DragMode {
	NONE,
	ORBIT,
	PAN,
}

var selection_enabled: bool = true
var navigation_area: Control
var scene_view_rect := Rect2()

var _left_down: bool = false
var _right_down: bool = false
var _middle_down: bool = false
var _drag_mode: DragMode = DragMode.NONE

func focus_on_aabb(bounds: AABB) -> void:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.length_squared() <= 0.0: return
	target_position = bounds.get_center()
	var radius: float = bounds.size.length() * 0.5
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y,1.0)
	var half_fov: float = deg_to_rad(fov) * 0.5
	var other_half: float = atan(tan(half_fov) * aspect) if keep_aspect == KEEP_HEIGHT else atan(tan(half_fov) / maxf(aspect,0.001))
	var visible_fraction: float = 1.0
	if scene_view_rect.has_area():
		visible_fraction = minf(scene_view_rect.size.x / viewport_size.x, scene_view_rect.size.y / viewport_size.y)
	var fit_distance: float = radius / maxf(sin(minf(half_fov,other_half)),0.001) * 1.15 / maxf(visible_fraction, 0.05)
	# Navigation limits and clipping must permit both millimetre-scale details
	# and venues larger than the default 500 m orbit range.
	min_distance = minf(_default_min_distance,maxf(radius * 0.05,0.00001))
	max_distance = maxf(_default_max_distance,fit_distance * 4.0)
	far = maxf(_default_far,fit_distance + radius * 2.0)
	# An enormous far/near ratio degenerates Forward+'s frustum planes for
	# tiny scenes. Retain the far range for optics and move the camera back
	# enough to fit the model beyond a numerically usable near plane.
	near = maxf(minf(_default_near,maxf(radius * 0.01,0.000001)),far / 1000000.0)
	min_distance = maxf(min_distance,near * 1.1)
	fit_distance = maxf(fit_distance,near + radius * 1.2)
	target_distance = clampf(fit_distance,min_distance,max_distance)
	# Publication must start with the scene framed, including the first draw.
	if projection == PROJECTION_ORTHOGONAL: size = 2.0 * fit_distance * tan(deg_to_rad(fov) * 0.5)
	current_distance = target_distance
	current_yaw = target_yaw
	current_pitch = target_pitch
	_update_camera_transform()

func _ready() -> void:
	_default_min_distance = min_distance
	_default_max_distance = max_distance
	_default_near = near
	_default_far = far
	_initialize_from_transform()
	_set_mouse_mode(false)

func _input(event: InputEvent) -> void:
	# A captured navigation drag must end even when release falls over a dock.
	if event is InputEventMouseButton and not event.pressed and _is_dragging():
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_handle_mouse_button(event)

func set_selection_enabled(enabled: bool) -> void:
	selection_enabled = enabled
	_end_navigation()

func _end_navigation() -> void:
	var was_dragging := _is_dragging()
	_left_down = false
	_right_down = false
	_middle_down = false
	_drag_mode = DragMode.NONE
	if was_dragging: _set_mouse_mode(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _end_navigation()

func _unhandled_input(event: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event is InputEventMouseButton and event.pressed and navigation_area != null and not navigation_area.get_global_rect().has_point(event.position): return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key_input(event)

func _process(delta: float) -> void:
	var alpha: float = clamp(delta * smoothing_speed, 0.0, 1.0)
	current_roll = lerp_angle(current_roll, target_roll, alpha)
	current_yaw = lerp_angle(current_yaw, target_yaw, alpha)
	current_pitch = lerp(current_pitch, target_pitch, alpha)
	current_distance = lerp(current_distance, target_distance, alpha)
	_update_camera_transform()

func _initialize_from_transform() -> void:
	var offset: Vector3 = global_position - target_position
	var distance: float = offset.length()
	if distance < min_distance:
		distance = max(min_distance, 0.001)
		offset = Vector3(0.0, 0.0, distance)

	target_distance = clamp(distance, min_distance, max_distance)
	current_distance = target_distance

	target_yaw = atan2(offset.x, offset.z)
	current_yaw = target_yaw

	target_pitch = asin(clamp(offset.y / distance, -1.0, 1.0))
	target_pitch = clamp(target_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	current_pitch = target_pitch

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# Selection owns left click only while its explicit toolbar mode is enabled.
	if event.button_index == MOUSE_BUTTON_LEFT:
		if selection_enabled and not _left_down: return
		_left_down = event.pressed
		_update_drag_mode(event.shift_pressed)
		_set_mouse_mode(_is_dragging())
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		_right_down = event.pressed
		_update_drag_mode(event.shift_pressed)
		_set_mouse_mode(_is_dragging())
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and event.double_click:
			fit_scene_requested.emit()
			get_viewport().set_input_as_handled()
			return
		_middle_down = event.pressed
		_update_drag_mode(event.shift_pressed)
		_set_mouse_mode(_is_dragging())
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_apply_zoom(-1.0)
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_apply_zoom(1.0)
		get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	_update_drag_mode(event.shift_pressed)

	if _drag_mode == DragMode.ORBIT:
		target_yaw -= event.relative.x * orbit_sensitivity
		target_pitch -= event.relative.y * orbit_sensitivity
		target_pitch = clamp(target_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		get_viewport().set_input_as_handled()
		return

	if _drag_mode == DragMode.PAN:
		_apply_pan(-event.relative.x * pan_sensitivity, event.relative.y * pan_sensitivity)
		get_viewport().set_input_as_handled()

func _apply_zoom(steps: float) -> void:
	if projection == PROJECTION_ORTHOGONAL:
		size = clampf(size * pow(zoom_step_factor, steps), 0.00001, 10000000.0)
		return
	var adaptive_base: float = zoom_step_factor + 0.1 * clamp(target_distance / 200.0, 0.0, 1.0)
	var zoom_factor: float = pow(adaptive_base, steps)
	var new_distance: float = target_distance * zoom_factor

	if new_distance < min_distance:
		var forward: Vector3 = _forward_direction(target_yaw, target_pitch)
		var overshoot: float = min_distance - new_distance
		target_position += forward * overshoot
		target_distance = min_distance
	else:
		target_distance = clamp(new_distance, min_distance, max_distance)

# Screen-aligned panning for the navigation handle, including poles and rolled views.
func pan_by(relative: Vector2) -> void:
	var height: float = scene_view_rect.size.y
	if height <= 0.0: height = get_viewport().get_visible_rect().size.y
	var span: float = size if projection == PROJECTION_ORTHOGONAL else 2.0 * current_distance * tan(deg_to_rad(fov) * 0.5)
	target_position += (-global_basis.x * relative.x + global_basis.y * relative.y) * span / maxf(height, 1.0)

func _apply_pan(delta_x: float, delta_y: float) -> void:
	var right: Vector3 = Vector3(cos(target_yaw), 0.0, -sin(target_yaw))
	target_position += right * delta_x
	target_position += Vector3.UP * delta_y

func _forward_direction(yaw: float, pitch: float) -> Vector3:
	var cos_pitch: float = cos(pitch)
	return Vector3(
		-cos_pitch * sin(yaw),
		-sin(pitch),
		-cos_pitch * cos(yaw)
	)

func _handle_key_input(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_LEFT:
		if event.shift_pressed:
			_apply_pan(-0.1, 0.0)
		elif event.alt_pressed:
			_apply_zoom(-1.0)
		else:
			target_yaw -= deg_to_rad(5.0)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_RIGHT:
		if event.shift_pressed:
			_apply_pan(0.1, 0.0)
		elif event.alt_pressed:
			_apply_zoom(1.0)
		else:
			target_yaw += deg_to_rad(5.0)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_UP:
		if event.shift_pressed:
			_apply_pan(0.0, 0.1)
		elif event.alt_pressed:
			_apply_zoom(-1.0)
		else:
			target_pitch = clamp(target_pitch + deg_to_rad(5.0), deg_to_rad(-89.0), deg_to_rad(89.0))
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_DOWN:
		if event.shift_pressed:
			_apply_pan(0.0, -0.1)
		elif event.alt_pressed:
			_apply_zoom(1.0)
		else:
			target_pitch = clamp(target_pitch - deg_to_rad(5.0), deg_to_rad(-89.0), deg_to_rad(89.0))
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_KP_1:
		set_view_direction(Vector3.BACK)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_KP_3:
		set_view_direction(Vector3.RIGHT)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_KP_7:
		set_view_direction(Vector3.UP)
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_KP_5:
		target_roll = 0.0
		target_position = Vector3.ZERO
		target_yaw = deg_to_rad(45.0)
		target_pitch = deg_to_rad(30.0)
		target_distance = 15.0
		get_viewport().set_input_as_handled()

func _update_drag_mode(shift_down: bool) -> void:
	if not _is_dragging():
		_drag_mode = DragMode.NONE
		return

	if _middle_down:
		_drag_mode = DragMode.ORBIT if shift_down else DragMode.PAN
	else:
		_drag_mode = DragMode.PAN if shift_down else DragMode.ORBIT

func _is_dragging() -> bool:
	return _left_down or _right_down or _middle_down

func _update_camera_transform() -> void:
	var cos_pitch: float = cos(current_pitch)
	var sin_pitch: float = sin(current_pitch)
	var sin_yaw: float = sin(current_yaw)
	var cos_yaw: float = cos(current_yaw)

	var orbit_offset := Vector3(
		current_distance * cos_pitch * sin_yaw,
		current_distance * sin_pitch,
		current_distance * cos_pitch * cos_yaw
	)

	global_position = target_position + orbit_offset
	var camera_up := Vector3.FORWARD if absf(cos(current_pitch)) < 0.0001 else Vector3.UP
	look_at(target_position, camera_up)
	rotate_object_local(Vector3.BACK, current_roll)
	# Keep one root viewport and native renderer ownership. Shift the camera so its
	# orbit target projects into the unobscured UI rectangle; rays remain root pixels.
	if scene_view_rect.has_area():
		var viewport_size := get_viewport().get_visible_rect().size
		var center_delta := scene_view_rect.get_center() - viewport_size * 0.5
		var span: float = size if projection == PROJECTION_ORTHOGONAL else 2.0 * current_distance * tan(deg_to_rad(fov) * 0.5)
		var pixels: float = viewport_size.y if keep_aspect == KEEP_HEIGHT else viewport_size.x
		global_position += (-global_basis.x * center_delta.x + global_basis.y * center_delta.y) * span / maxf(pixels, 1.0)

func _set_mouse_mode(active: bool) -> void:
	if active:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Presentation-only camera changes leave scene transforms and native resources intact.
func set_view_direction(direction: Vector3) -> void:
	if not direction.is_finite() or direction.length_squared() < 0.000001: return
	direction = direction.normalized()
	target_roll = 0.0
	target_yaw = atan2(direction.x, direction.z) if Vector2(direction.x, direction.z).length_squared() > 0.000001 else 0.0
	target_pitch = asin(clampf(direction.y, -1.0, 1.0))

func set_projection_mode(orthographic: bool) -> void:
	if orthographic == (projection == PROJECTION_ORTHOGONAL): return
	if orthographic:
		size = 2.0 * current_distance * tan(deg_to_rad(fov) * 0.5)
		projection = PROJECTION_ORTHOGONAL
	else:
		target_distance = clampf(size / maxf(2.0 * tan(deg_to_rad(fov) * 0.5), 0.00001), min_distance, max_distance)
		current_distance = target_distance
		projection = PROJECTION_PERSPECTIVE

func orbit_by(relative: Vector2) -> void:
	target_yaw -= relative.x * orbit_sensitivity
	target_pitch = clampf(target_pitch - relative.y * orbit_sensitivity, deg_to_rad(-89.9), deg_to_rad(89.9))

func roll_view(angle: float) -> void:
	target_roll = wrapf(target_roll + angle, -PI, PI)
