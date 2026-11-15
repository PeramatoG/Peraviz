extends Node
class_name AppShell

@export var side_panel_path: NodePath
@export var side_toggle_button_path: NodePath
@export var modules_container_path: NodePath

var selection := SceneSelection.new()
var explorer: SceneExplorer
var inspector: FixtureInspectionPanel
var _owner: Node3D
var _preferences: UserPreferences
var _left: PanelContainer
var _right: PanelContainer
var _outer: HSplitContainer
var _inner: HSplitContainer
var _area: Control
var _cube: Control
var _highlight: Node
var _toolbar: HFlowContainer
var _row: HBoxContainer
var _left_button: Button
var _right_button: Button
var _tools_button: Button
var _fullscreen_button: Button
var _ui_root: Control
var _top_bar: Control
var _status_bar: PanelContainer
var _fps: Label
var _exit_layer: CanvasLayer
var _exit_fullscreen: Button
var _fullscreen_windows: Array[WeakRef] = []
var _view: PopupMenu
var _windows: Array[Window] = []
var _modes = preload("res://scripts/ui/window_modes.gd").new()
var _project_label: Label
var _press_position := Vector2.ZERO
var _left_pressed: bool = false
var _pick_bounds: Dictionary = {}
var _configured: bool = false

func configure(owner_node: Node3D, preferences: UserPreferences, details: FixtureInspectionPanel) -> void:
	_owner = owner_node
	_preferences = preferences
	inspector = details
	_row = _owner.topbar_row
	_ui_root = _owner.get_node("UIRoot")
	_top_bar = _owner.get_node("UIRoot/RootVBox/TopBar")
	_owner.get_node("UIRoot").theme = preload("res://scripts/ui/application_theme.tres")
	_owner.visual_settings_window.theme = preload("res://scripts/ui/application_theme.tres")
	_owner.visual_settings_window._advanced_mode_toggle.toggled.connect(_owner._on_show_advanced_controls_toggled)
	_modes.configure(_owner.get_window())
	_build_layout()
	_build_toolbar()
	inspector.show_object_uuids = preferences.show_object_uuids
	explorer.show_object_uuids = preferences.show_object_uuids
	inspector.configure(selection, _owner._fixture_row_provider)
	selection.changed.connect(_selection_changed)
	_configured = true
	_outer.resized.connect(func() -> void: _restore_widths.call_deferred())
	_inner.resized.connect(func() -> void: _restore_widths.call_deferred())
	_outer.dragged.connect(func(offset: int) -> void:
		_preferences.explorer_width = maxi(roundi(_left.get_combined_minimum_size().x), offset)
		_save())
	_inner.dragged.connect(func(offset: int) -> void:
		_preferences.inspector_width = maxi(roundi(_right.get_combined_minimum_size().x), -offset)
		_save())
	_owner.get_viewport().size_changed.connect(_layout_changed)
	_layout_changed()

func _build_layout() -> void:
	var content: Control = _owner.get_node("UIRoot/RootVBox/ContentRow")
	# All @onready paths have resolved before moving the original diagnostic host.
	var legacy: Control = get_node(side_panel_path)
	var modules := get_node(modules_container_path)
	var diagnostic_window := _tool_window("Fixture diagnostics", legacy)
	diagnostic_window.size = Vector2i(560, 680)
	_owner.user_module.hide()
	_owner.advanced_module.hide()
	_owner.debug_module.show()
	_owner.auto_load_last_project_toggle.reparent(modules)
	_owner.show_advanced_controls_toggle.reparent(modules)
	_owner.auto_start_dmx_project_toggle.reparent(modules)
	_owner.auto_load_last_project_toggle.show()
	_owner.show_advanced_controls_toggle.show()
	_owner.auto_start_dmx_project_toggle.show()
	var dmx_window := _tool_window("DMX connection", _owner.dmx_controls_mount)
	dmx_window.size = Vector2i(560, 420)
	_tool_window("MVR-xchange", _owner._mvr_xchange_panel)
	_owner.dmx_controls_mount.show()
	_outer = HSplitContainer.new()
	_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outer.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_outer)
	_left = PanelContainer.new()
	_left.custom_minimum_size.x = 180
	_outer.add_child(_left)
	explorer = SceneExplorer.new()
	_left.add_child(explorer)
	explorer.configure(selection)
	_inner = HSplitContainer.new()
	_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inner.mouse_filter = Control.MOUSE_FILTER_PASS
	_outer.add_child(_inner)
	_area = _owner.get_node("UIRoot/RootVBox/ContentRow/MainViewportArea")
	_area.reparent(_inner)
	_area.custom_minimum_size = Vector2(280, 100)
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.clip_contents = true
	_right = PanelContainer.new()
	_right.custom_minimum_size.x = 240
	_inner.add_child(_right)
	inspector.reparent(_right)
	inspector.show()
	_toolbar = HFlowContainer.new()
	_toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toolbar.offset_left = 8
	_toolbar.offset_top = 5
	_toolbar.offset_right = -154
	_area.add_child(_toolbar)
	_toolbar.resized.connect(_update_camera_rect)
	for entry in [["Select", "Select mode: on = left-click selection (Ctrl adds/removes); off = left-drag orbit, Shift+left-drag pan"], ["Move", "Reserved for MVR document editing"], ["Rotate", "Reserved for MVR document editing"]]:
		var button := _button(_toolbar, "", entry[1], func() -> void: pass)
		button.name = entry[0]
		_icon(button, str(entry[0]).to_lower(), entry[1])
		button.disabled = entry[0] != "Select"
		if entry[0] == "Select":
			button.focus_mode = Control.FOCUS_NONE
			button.toggle_mode = true
			button.button_pressed = true
			button.toggled.connect(_set_selection_enabled)
	var frame_button := _button(_toolbar, "", "Frame selection (F); fit scene when empty", frame_selection)
	frame_button.name = "Frame"
	_icon(frame_button, "frame_selection", frame_button.tooltip_text)
	var fit_button := _button(_toolbar, "", "Fit entire scene (Shift+F / double middle-click)", _owner._focus_loaded_scene)
	fit_button.name = "Fit"
	_icon(fit_button, "fit_scene", fit_button.tooltip_text)
	_highlight = preload("res://scripts/ui/selection_highlight.gd").new()
	add_child(_highlight)
	_highlight.configure(selection)
	_owner._asset_cache.derived_lods.meshes_changed.connect(_highlight.refresh_meshes)
	_cube = preload("res://scripts/ui/navigation_cube.gd").new()
	_area.add_child(_cube)
	_cube.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_cube.offset_left = -146
	_cube.offset_top = 8
	_cube.offset_right = -10
	_cube.offset_bottom = 170
	_cube.configure(_owner.camera,selection,_preferences)
	_cube.home_requested.connect(_owner._focus_loaded_scene)
	_cube.fit_requested.connect(_owner._focus_loaded_scene)
	_owner.camera.fit_scene_requested.connect(_owner._focus_loaded_scene)
	_status_bar = PanelContainer.new()
	_status_bar.name = "StatusBar"
	_owner.get_node("UIRoot/RootVBox").add_child(_status_bar)
	var status_row := HBoxContainer.new()
	_status_bar.add_child(status_row)
	_owner.status_label.reparent(status_row)
	_owner.status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owner.status_label.clip_text = true
	_owner.status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_owner.status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_fps = _area.get_node("FpsOverlay") as Label
	_fps.reparent(status_row)
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps.custom_minimum_size.x = 74
	_owner.camera.navigation_area = _area
	_area.resized.connect(_update_camera_rect)
	_area.item_rect_changed.connect(_update_camera_rect)
	# Keep the sole presentation control outside the hidden application UI tree.
	_exit_layer = CanvasLayer.new()
	_exit_layer.name = "FullscreenExitLayer"
	_exit_layer.layer = 128
	_owner.add_child(_exit_layer)
	_exit_fullscreen = _button(_exit_layer, "", "Exit fullscreen (Esc / F11)", toggle_fullscreen)
	_exit_fullscreen.name = "ExitFullscreen"
	_exit_fullscreen.theme = _ui_root.theme
	_icon(_exit_fullscreen, "close", _exit_fullscreen.tooltip_text)
	_exit_fullscreen.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_exit_fullscreen.offset_left = -40
	_exit_fullscreen.offset_right = -8
	_exit_fullscreen.offset_top = 8
	_exit_fullscreen.offset_bottom = 40
	_exit_layer.hide()

func _build_toolbar() -> void:
	_left_button = get_node(side_toggle_button_path)
	_left_button.toggle_mode = true
	_left_button.pressed.connect(toggle_side_panel)
	_icon(_left_button, "explorer", "Toggle Scene Explorer")
	var identity := Label.new()
	identity.text = "PERAVIZ"
	_row.add_child(identity)
	_row.move_child(identity, 0)
	_project_label = Label.new()
	_project_label.text = "Untitled"
	_project_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_project_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_project_label.custom_minimum_size.x = 60
	_row.add_child(_project_label)
	_row.move_child(_project_label, 1)
	_icon(_owner.load_button, "open", "Open MVR or PVZ (Ctrl+O)")
	_icon(_owner.save_project_button, "save", "Save Peraviz project (Ctrl+S)")
	_icon(_owner.visual_settings_button, "settings", "Visual settings")
	var view_menu: MenuButton = _row.get_node("ViewMenu")
	_row.move_child(view_menu, _owner.save_project_button.get_index() + 1)
	_view = view_menu.get_popup()
	_view.add_separator()
	for index in range(5):
		_view.add_check_item(["Scene Explorer", "Inspector", "Hide all tools", "Fullscreen", "1 m scale reference"][index], index + 2)
	_view.add_item("Reset Layout", 7)
	_view.add_separator()
	for index in range(3): _view.add_item(["UI scale 100%", "UI scale 125%", "UI scale 150%"][index], index + 9)
	_view.id_pressed.connect(_view_action)
	_view.about_to_popup.connect(_sync_view)
	var tools := MenuButton.new()
	tools.text = "Tools"
	_row.add_child(tools)
	_row.move_child(tools, view_menu.get_index() + 1)
	for label in ["DMX connection…", "DMX technical monitor…", "MVR-xchange…", "Diagnostics…"]: tools.get_popup().add_item(label)
	tools.get_popup().add_check_item("Show object UUIDs", 4)
	tools.get_popup().set_item_checked(4, _preferences.show_object_uuids)
	tools.get_popup().id_pressed.connect(func(id: int) -> void:
		match id:
			0: _windows[1].popup_centered()
			1: _owner._dmx_controller._on_dmx_monitor_pressed()
			2: _windows[2].popup_centered()
			3:
				_owner.debug_module.show()
				_windows[0].popup_centered()
			4:
				_preferences.show_object_uuids = not _preferences.show_object_uuids
				tools.get_popup().set_item_checked(4, _preferences.show_object_uuids)
				inspector.show_object_uuids = _preferences.show_object_uuids
				inspector.refresh([])
				explorer.set_technical_identity(_preferences.show_object_uuids)
				_save()
	)
	var dmx := _button(_row, "Art-Net", "Start / stop Art-Net reception", func() -> void:
		if _owner._dmx_controller.is_dmx_enabled(): _owner._dmx_controller.stop_dmx()
		else: _owner._dmx_controller.start_dmx())
	dmx.name = "ArtNetToggle"
	dmx.toggle_mode = true
	_row.move_child(dmx, tools.get_index() + 1)
	_right_button = _button(_row, "", "Toggle Inspector", toggle_inspector)
	_right_button.toggle_mode = true
	_icon(_right_button, "inspector", "Toggle Inspector")
	_tools_button = _button(_row, "", "Hide / restore all tools (Tab)", toggle_tools)
	_tools_button.toggle_mode = true
	_icon(_tools_button, "tools", "Hide / restore all tools (Tab)")
	_fullscreen_button = _button(_row, "", "Fullscreen (F11)", toggle_fullscreen)
	_fullscreen_button.toggle_mode = true
	_icon(_fullscreen_button, "fullscreen", "Fullscreen (F11)")
	# The useful scale helper remains owned by its existing controller.
	_owner._scale_reference_controller._toggle.hide()

func _tool_window(title_text: String, control: Control) -> Window:
	var window := Window.new()
	window.title = title_text
	window.size = Vector2i(540, 600)
	window.transient = true
	window.visible = false
	window.theme = preload("res://scripts/ui/application_theme.tres")
	_owner.get_node("UIRoot").add_child(window)
	var scroll := ScrollContainer.new()
	window.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.reparent(scroll)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.show()
	preload("res://scripts/ui/window_modes.gd").install_escape(window)
	window.close_requested.connect(window.hide)
	_windows.append(window)
	return window

func _button(parent: Node, text: String, tooltip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _icon(button: Button, icon_name: String, tooltip: String) -> void:
	button.text = ""
	button.icon = load("res://assets/ui/%s.svg" % icon_name)
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(32, 30)

func publish_scene(project_path: String = "") -> void:
	_pick_bounds.clear()
	_cube.reset_home()
	selection.publish(_owner._node_index)
	explorer.publish(_owner._node_index, _owner._fixture_row_provider)
	set_project_name(project_path if not project_path.is_empty() else _owner._loaded_mvr_path)

func set_project_name(path: String) -> void:
	_project_label.text = path.get_file() if not path.is_empty() else "Untitled"
	_project_label.tooltip_text = path

func retire_scene() -> void:
	selection.retire()
	_pick_bounds.clear()
	if explorer != null: explorer.publish({}, _owner._fixture_row_provider)

func _selection_changed() -> void:
	# Manual controls consume application selection only when explicitly enabled.
	_owner._fixture_debug_controller.refresh_fixture_debug_panel()
	if _owner._is_manual_fixture_test_enabled() and selection.ids.size() == 1:
		var id: String = selection.ids[0]
		if _owner._scene_registry.has_fixture(id):
			_owner._fixture_debug_controller.refresh_fixture_debug_panel()
			_owner._fixture_debug_controller._apply_selected_fixture_controls("application_selection")

func toggle_side_panel() -> void:
	set_side_panel_open(not is_side_panel_open())

func set_side_panel_open(is_open: bool) -> void:
	if _preferences == null: return
	_preferences.sidebar_open = is_open
	_preferences.tools_hidden = false
	_layout_changed()
	_save()

func is_side_panel_open() -> bool:
	return _preferences.sidebar_open if _preferences != null else true

func toggle_inspector() -> void:
	_preferences.inspector_open = not _preferences.inspector_open
	_preferences.tools_hidden = false
	_layout_changed()
	_save()

func toggle_tools() -> void:
	_preferences.tools_hidden = not _preferences.tools_hidden
	_layout_changed()
	_save()

func toggle_fullscreen() -> void:
	_modes.toggle()
	_fullscreen_button.set_pressed_no_signal(_modes.active)
	if _modes.active:
		_fullscreen_windows.clear()
		# Search UI only; never traverse the imported MVR hierarchy for a layout action.
		for node in _ui_root.find_children("*", "Window", true, false):
			_hide_fullscreen_window(node as Window)
		_hide_fullscreen_window(_owner._dmx_controller._dmx_monitor_window)
	else:
		for reference in _fullscreen_windows:
			var window: Window = reference.get_ref()
			if is_instance_valid(window): window.show()
		_fullscreen_windows.clear()
	_layout_changed()

func _hide_fullscreen_window(window: Window) -> void:
	if not is_instance_valid(window) or not window.visible: return
	# Menus are transient interactions; restore tool/dialog windows, not open menus.
	if not window is PopupMenu: _fullscreen_windows.append(weakref(window))
	window.hide()

func reset_layout() -> void:
	_preferences.sidebar_open = true
	_preferences.inspector_open = true
	_preferences.explorer_width = 270
	_preferences.inspector_width = 320
	_preferences.tools_hidden = false
	_layout_changed()
	_save()

func _layout_changed() -> void:
	if not _configured: return
	var width: float = _owner.get_viewport().get_visible_rect().size.x
	var show_tools: bool = not _preferences.tools_hidden and not _modes.active
	_ui_root.visible = not _modes.active
	_top_bar.visible = not _modes.active
	_status_bar.visible = not _modes.active
	_exit_layer.visible = _modes.active
	_left.visible = _preferences.sidebar_open and show_tools
	_right.visible = _preferences.inspector_open and show_tools and width >= 1200
	_toolbar.visible = show_tools
	_cube.visible = show_tools
	_left_button.set_pressed_no_signal(_left.visible)
	_right_button.set_pressed_no_signal(_right.visible)
	_tools_button.set_pressed_no_signal(_preferences.tools_hidden)
	_restore_widths.call_deferred()
	_update_camera_rect.call_deferred()

func _restore_widths() -> void:
	if not _configured: return
	if _left.visible: _outer.split_offset = _preferences.explorer_width
	if _right.visible: _inner.split_offset = -_preferences.inspector_width

func _update_camera_rect() -> void:
	if _area == null: return
	if _modes.active:
		_owner.camera.navigation_area = null
		_owner.camera.scene_view_rect = _owner.get_viewport().get_visible_rect()
		return
	_owner.camera.navigation_area = _area
	var rect := _area.get_global_rect()
	if _toolbar.visible:
		var toolbar_height: float = maxf(36.0, _toolbar.size.y + 10.0)
		rect.position.y += toolbar_height
		rect.size.y -= toolbar_height
	_owner.camera.scene_view_rect = rect

func _save() -> void:
	_preferences.save_to_disk()

func _sync_view() -> void:
	_view.set_item_checked(_view.get_item_index(2), _left.visible)
	_view.set_item_checked(_view.get_item_index(3), _right.visible)
	_view.set_item_checked(_view.get_item_index(4), _preferences.tools_hidden)
	_view.set_item_checked(_view.get_item_index(5), _modes.active)
	_view.set_item_checked(_view.get_item_index(6), _owner._scale_reference_controller._toggle.button_pressed)

func _view_action(id: int) -> void:
	match id:
		2: toggle_side_panel()
		3: toggle_inspector()
		4: toggle_tools()
		5: toggle_fullscreen()
		6: _owner._scale_reference_controller._toggle.button_pressed = not _owner._scale_reference_controller._toggle.button_pressed
		7: reset_layout()
		9, 10, 11:
			_preferences.ui_scale = [1.0, 1.25, 1.5][id - 9]
			_owner.get_window().content_scale_factor = _preferences.ui_scale
			_save()

func _set_selection_enabled(enabled: bool) -> void:
	_left_pressed = false
	_owner.camera.set_selection_enabled(enabled)

func frame_selection() -> void:
	if selection.ids.is_empty(): _owner._focus_loaded_scene()
	else: _owner.camera.focus_on_aabb(selection.bounds())

func _input(event: InputEvent) -> void:
	if not _configured or not event is InputEventKey or not event.pressed or event.echo: return
	if _modes.active:
		if event.keycode in [KEY_F11,KEY_ESCAPE]: toggle_fullscreen()
		elif event.keycode == KEY_F and not event.ctrl_pressed and not event.alt_pressed:
			if event.shift_pressed: _owner._focus_loaded_scene()
			else: frame_selection()
		elif event.keycode in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_KP_1,KEY_KP_3,KEY_KP_5,KEY_KP_7]: return
		get_viewport().set_input_as_handled()
		return
	if event.keycode not in [KEY_TAB, KEY_F11]: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	# Let modal dialogs and child tools own their input first.
	if _cube._menu.get_popup().visible: return
	for child in _row.get_children():
		if child is MenuButton and child.get_popup().visible: return
	for window in _windows:
		if window.visible: return
	if _owner.picker.visible or _owner.visual_settings_window.visible: return
	if event.keycode == KEY_TAB: toggle_tools()
	else: toggle_fullscreen()
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _configured or _modes.active: return
	var focus := _owner.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F11: toggle_fullscreen()
			KEY_TAB: toggle_tools()
			KEY_ESCAPE:
				if _modes.active: toggle_fullscreen()
				elif _preferences.tools_hidden: toggle_tools()
				else: selection.clear()
			KEY_F:
				if event.shift_pressed: _owner._focus_loaded_scene()
				else: frame_selection()
			KEY_O:
				if not event.ctrl_pressed: return
				_owner._ui_controller._on_load_pressed()
			KEY_S:
				if not event.ctrl_pressed: return
				_owner._ui_controller._on_save_project_pressed()
			_: return
		get_viewport().set_input_as_handled()
	if _owner._scene_loading: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _owner.camera.selection_enabled:
		if event.pressed:
			_left_pressed = _area.get_global_rect().has_point(event.position)
			_press_position = event.position
		elif _left_pressed:
			_left_pressed = false
			if event.position.distance_to(_press_position) <= 5.0:
				pick(event.position, event.ctrl_pressed)

func pick(position: Vector2, additive: bool = false) -> void:
	var camera: Camera3D = _owner.camera
	var origin := camera.project_ray_origin(position)
	var direction := camera.project_ray_normal(position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * camera.far)
	var hit := _owner.get_world_3d().direct_space_state.intersect_ray(query)
	var id := selection.id_for(hit.get("collider"))
	var nearest: float = origin.distance_to(hit.get("position", origin + direction * camera.far))
	# Non-fixture imported objects use their existing model bounds; no extra physics bodies.
	for object_id in _owner._node_index:
		var node: Node3D = _owner._node_index[object_id]
		if str(node.get_meta("peraviz_type", "")) not in ["truss", "scene_object", "support"]: continue
		if not _pick_bounds.has(object_id): _pick_bounds[object_id] = SceneSelection.object_bounds(node)
		var intersection: Variant = (_pick_bounds[object_id] as AABB).intersects_ray(origin, direction)
		if intersection is Vector3 and origin.distance_to(intersection) < nearest:
			nearest = origin.distance_to(intersection)
			id = str(object_id)
	var values: PackedStringArray = selection.ids.duplicate() if additive else PackedStringArray()
	if not id.is_empty():
		if values.has(id): values.remove_at(values.find(id))
		else: values.append(id)
	selection.select(values)
