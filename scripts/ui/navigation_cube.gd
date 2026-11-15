extends Control

signal home_requested
signal fit_requested

const Palette = preload("res://scripts/ui/ui_palette.gd")
const PREVIEW_RECT := Rect2(4, 8, 128, 128)
var camera: Camera3D
var _selection: SceneSelection
var _preferences: UserPreferences
var _viewport: SubViewport
var _model: Node3D
var _image: TextureRect
var _pan_button: Button
var _panning: bool = false
var _menu: MenuButton
var _arrows: Array[Button] = []
var _previous_basis := Basis()
var _last_projection: int = -1
var _mode: String = "hybrid"
var _snap: bool = true
var _compass: bool = true
var _fit_after: bool = false
var _active: bool = false
var _pressed: bool = false
var _dragged: bool = false
var _drag_distance := Vector2.ZERO
var _drag_compass: bool = false
var _compass_start := Vector3.ZERO
var _home_snapshot: Dictionary = {}
var _hover := Vector3.ZERO

func configure(view_camera: Camera3D, state: SceneSelection = null, preferences: UserPreferences = null) -> void:
	camera = view_camera
	_selection = state
	_preferences = preferences
	if preferences != null:
		_mode = preferences.navigation_projection
		_snap = preferences.navigation_snap
		_compass = preferences.navigation_compass
		_fit_after = preferences.navigation_fit
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.name = "NavigationCubeViewport"
	_viewport.size = Vector2i(256,256)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_model = preload("res://scripts/ui/navigation_cube_model.gd").new()
	_viewport.add_child(_model)
	_model.build()
	_model.show_compass(_compass)
	_image = TextureRect.new()
	_image.position = PREVIEW_RECT.position
	_image.size = PREVIEW_RECT.size
	_image.texture = _viewport.get_texture()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	var home := _icon_button("", "Home — restore the saved view", Vector2(0,0), _home)
	home.icon = preload("res://assets/ui/home.svg")
	home.expand_icon = true
	_pan_button = _icon_button("", "Pan — hold and drag to move the view", Vector2(112,0), func() -> void: pass)
	_pan_button.name = "Pan"
	_pan_button.icon = preload("res://assets/ui/pan.svg")
	_pan_button.expand_icon = true
	# Drag handling owns the pressed state, including release outside the widget.
	_pan_button.button_mask = 0
	_pan_button.toggle_mode = true
	_pan_button.focus_mode = Control.FOCUS_NONE
	_pan_button.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_pan_button.gui_input.connect(_pan_input)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): _end_pan())
	_arrows.append(_icon_button("↶", "Roll view 90° counterclockwise", Vector2(0,112), func() -> void: camera.roll_view(PI*0.5)))
	_arrows.append(_icon_button("↷", "Roll view 90° clockwise", Vector2(112,112), func() -> void: camera.roll_view(-PI*0.5)))
	for index in range(4):
		_arrows.append(_icon_button(["▲","▶","▼","◀"][index], "Adjacent face", [Vector2(56,14),Vector2(112,59),Vector2(56,112),Vector2(0,59)][index], _adjacent.bind(index)))
	_menu = MenuButton.new()
	_menu.text = "WCS ▾"
	_menu.tooltip_text = "World coordinates (Y up) · navigation options"
	_menu.position = Vector2(35,135)
	_menu.size = Vector2(68,24)
	add_child(_menu)
	var popup := _menu.get_popup()
	popup.add_item("World coordinates · Y up",99)
	popup.set_item_disabled(0,true)
	popup.add_separator()
	popup.add_item("Home",0)
	popup.add_item("Set current view as Home",1)
	popup.add_item("Reset Home",2)
	popup.add_separator()
	popup.add_radio_check_item("Parallel",10)
	popup.add_radio_check_item("Perspective",11)
	popup.add_radio_check_item("Perspective with orthographic faces",12)
	popup.add_separator()
	popup.add_check_item("Snap to closest view after dragging",20)
	popup.add_check_item("Fit scene after view changes",21)
	popup.add_check_item("Show compass",22)
	popup.id_pressed.connect(_menu_action)
	popup.about_to_popup.connect(_sync_menu)
	mouse_entered.connect(func() -> void: _set_active(true))
	mouse_exited.connect(_update_activity.call_deferred)
	_sync_menu()
	_project()
	_set_active(false)

func _icon_button(text: String, tooltip: String, position_value: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.position = position_value
	button.custom_minimum_size = Vector2(22,22)
	button.size = Vector2(22,22)
	button.flat = true
	button.add_theme_font_size_override("font_size",14)
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		button.add_theme_stylebox_override(state, preload("res://scripts/ui/cube_icon_button.tres"))
	button.pressed.connect(action)
	button.mouse_entered.connect(func() -> void: _set_active(true))
	button.mouse_exited.connect(_update_activity.call_deferred)
	add_child(button)
	return button

func _process(_delta: float) -> void:
	if camera == null or not is_visible_in_tree(): return
	if _mode == "hybrid": camera.set_projection_mode(_face_view(camera.global_basis.z))
	if camera.global_basis != _previous_basis or camera.projection != _last_projection: _project()

# This viewport contains only the real 3D cube; it never borrows the MVR world.
# UPDATE_ONCE redraws its 256² texture only for orientation or hover changes.
func _project() -> void:
	_previous_basis = camera.global_basis
	_last_projection = camera.projection
	_model.orient(camera.global_basis)
	_redraw_model()
	_update_arrows()

func _redraw_model() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _face_view(direction: Vector3) -> bool:
	return maxf(absf(direction.x),maxf(absf(direction.y),absf(direction.z))) > 0.99999

func hit_direction(point: Vector2) -> Vector3:
	if not PREVIEW_RECT.has_point(point): return Vector3.ZERO
	return _model.hit_direction(_to_preview(point))

func patch_screen_center(direction: Vector3) -> Vector2:
	return PREVIEW_RECT.position + _model.patch_center(direction) * PREVIEW_RECT.size / Vector2(_viewport.size)

func _to_preview(point: Vector2) -> Vector2:
	return (point-PREVIEW_RECT.position) * Vector2(_viewport.size) / PREVIEW_RECT.size

func _prepare_pivot() -> void:
	if _selection != null and not _selection.ids.is_empty(): camera.target_position = _selection.bounds().get_center()

func _activate(direction: Vector3) -> void:
	_prepare_pivot()
	camera.set_view_direction(direction)
	camera.set_projection_mode(_mode == "parallel" or (_mode == "hybrid" and _face_view(direction)))
	if _fit_after: fit_requested.emit()

func _finish_click(point: Vector2) -> void:
	if _pressed and not _dragged:
		var direction := hit_direction(point)
		if direction != Vector3.ZERO: _activate(direction)
		elif _drag_compass and _compass_start != Vector3.ZERO:
			var snapped := _nearest_direction(_compass_start,true)
			_turn_compass(snapped)
	elif _pressed and _dragged and _snap and not _drag_compass:
		var direction := Vector3(sin(camera.target_yaw)*cos(camera.target_pitch),sin(camera.target_pitch),cos(camera.target_yaw)*cos(camera.target_pitch))
		var nearest := _nearest_direction(direction)
		if direction.dot(nearest) > cos(deg_to_rad(10.0)): _activate(nearest)
	_pressed = false

func _nearest_direction(direction: Vector3, cardinal_only: bool = false) -> Vector3:
	var best := Vector3.BACK
	var score: float = -INF
	for patch in _model.patches:
		var candidate: Vector3 = patch.direction
		if cardinal_only and (candidate.y != 0 or not _face_view(candidate)): continue
		if direction.dot(candidate) > score:
			score = direction.dot(candidate)
			best = candidate
	return best

func _pan_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_panning = event.pressed
		_pan_button.set_pressed_no_signal(_panning)
		_pan_button.accept_event()

func _end_pan() -> void:
	_panning = false
	if is_instance_valid(_pan_button): _pan_button.set_pressed_no_signal(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _end_pan()

func _input(event: InputEvent) -> void:
	if _panning:
		if event is InputEventMouseMotion:
			camera.pan_by(event.relative)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_end_pan()
			get_viewport().set_input_as_handled()
		return
	if _pressed and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish_click(event.position-global_position)
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_menu.get_popup().position = Vector2i(get_screen_position()+event.position)
			_menu.get_popup().popup()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_dragged = false
				_drag_distance = Vector2.ZERO
				_compass_start = _model.compass_hit(_to_preview(event.position)) if hit_direction(event.position) == Vector3.ZERO else Vector3.ZERO
				_drag_compass = _compass_start != Vector3.ZERO
				_prepare_pivot()
			else: _finish_click(event.position)
			accept_event()
	elif event is InputEventMouseMotion:
		if _pressed:
			_drag_distance += event.relative
			if _drag_distance.length() > 4: _dragged = true
			if _dragged:
				if _drag_compass:
					if absf(sin(camera.target_pitch)) > 0.9999: camera.roll_view(-event.relative.x*camera.orbit_sensitivity)
					else: camera.target_yaw -= event.relative.x*camera.orbit_sensitivity
				else: camera.orbit_by(event.relative)
		else:
			_hover = hit_direction(event.position)
			var compass: bool = _hover == Vector3.ZERO and _model.compass_hit(_to_preview(event.position)) != Vector3.ZERO
			_model.hover(_hover,compass)
			_redraw_model()
			tooltip_text = "Click a face, edge or corner. Drag cube to orbit; drag compass to turn. Right-click for options."
		accept_event()

func _turn_compass(direction: Vector3) -> void:
	if absf(sin(camera.target_pitch)) > 0.9999:
		# At the poles yaw cannot turn the view; roll aligns the requested cardinal up.
		camera.target_roll = -atan2(direction.x,-direction.z)*signf(sin(camera.target_pitch))
	else: camera.target_yaw = atan2(direction.x,direction.z)

func _adjacent(index: int) -> void:
	var direction: Vector3 = [camera.global_basis.y,camera.global_basis.x,-camera.global_basis.y,-camera.global_basis.x][index]
	_activate(_nearest_direction(direction))

func _update_arrows() -> void:
	for arrow in _arrows: arrow.visible = _active and _face_view(camera.global_basis.z)

func _set_active(enabled: bool) -> void:
	_active = enabled
	_image.modulate.a = 1.0 if enabled else 0.65
	if not enabled:
		_hover = Vector3.ZERO
		_model.hover(Vector3.ZERO)
		_redraw_model()
	_update_arrows()

func _update_activity() -> void:
	_set_active(get_global_rect().has_point(get_global_mouse_position()))

func _home() -> void:
	if _home_snapshot.is_empty():
		camera.set_projection_mode(_mode == "parallel")
		camera.set_view_direction(Vector3.ONE.normalized())
		home_requested.emit()
	else:
		_mode = _home_snapshot.projection_mode
		camera.set_projection_mode(_home_snapshot.orthographic)
		camera.target_position = _home_snapshot.position
		camera.target_distance = _home_snapshot.distance
		camera.target_yaw = _home_snapshot.yaw
		camera.target_pitch = _home_snapshot.pitch
		camera.target_roll = _home_snapshot.roll
		camera.size = _home_snapshot.extent
	_sync_menu()
	_save_preferences()

func reset_home() -> void:
	_home_snapshot.clear()

func _menu_action(id: int) -> void:
	match id:
		0: _home()
		1:
			_home_snapshot = {"projection_mode":_mode,"position":camera.target_position,"distance":camera.current_distance,"yaw":camera.current_yaw,"pitch":camera.current_pitch,"roll":camera.current_roll,"orthographic":camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"extent":camera.size}
		2: reset_home()
		10,11,12:
			_mode = ["parallel","perspective","hybrid"][id-10]
			camera.set_projection_mode(_mode == "parallel" or (_mode == "hybrid" and _face_view(camera.global_basis.z)))
		20: _snap = not _snap
		21: _fit_after = not _fit_after
		22:
			_compass = not _compass
			_model.show_compass(_compass)
			_redraw_model()
	_sync_menu()
	_save_preferences()

func _save_preferences() -> void:
	if _preferences != null:
		_preferences.navigation_projection = _mode
		_preferences.navigation_snap = _snap
		_preferences.navigation_fit = _fit_after
		_preferences.navigation_compass = _compass
		_preferences.save_to_disk()

func _sync_menu() -> void:
	var popup := _menu.get_popup()
	for index in range(3): popup.set_item_checked(popup.get_item_index(10+index),_mode==["parallel","perspective","hybrid"][index])
	popup.set_item_checked(popup.get_item_index(20),_snap)
	popup.set_item_checked(popup.get_item_index(21),_fit_after)
	popup.set_item_checked(popup.get_item_index(22),_compass)
