extends RefCounted
class_name UiController

var _load_button: Button
var _save_project_button: Button
var _visual_settings_button: Button
var _picker: FileDialog
var _open_file_selected_callback: Callable
var _save_file_selected_callback: Callable
var _open_visual_settings_callback: Callable
var _file_dialog_mode: StringName = &"open"

func configure(load_button: Button,
		save_project_button: Button,
		visual_settings_button: Button,
		picker: FileDialog,
		on_file_selected_callback: Callable,
		on_save_file_selected_callback: Callable,
		open_visual_settings_callback: Callable) -> void:
	_load_button = load_button
	_save_project_button = save_project_button
	_visual_settings_button = visual_settings_button
	_picker = picker
	_open_file_selected_callback = on_file_selected_callback
	_save_file_selected_callback = on_save_file_selected_callback
	_open_visual_settings_callback = open_visual_settings_callback

	if _load_button != null and not _load_button.pressed.is_connected(_on_load_pressed):
		_load_button.pressed.connect(_on_load_pressed)
	if _save_project_button != null and not _save_project_button.pressed.is_connected(_on_save_project_pressed):
		_save_project_button.pressed.connect(_on_save_project_pressed)
	if _picker != null:
		_picker.access = FileDialog.ACCESS_FILESYSTEM
		if not _picker.file_selected.is_connected(_on_file_dialog_file_selected):
			_picker.file_selected.connect(_on_file_dialog_file_selected)
	if _visual_settings_button != null and not _visual_settings_button.pressed.is_connected(_on_visual_settings_pressed):
		_visual_settings_button.pressed.connect(_on_visual_settings_pressed)

func _on_load_pressed() -> void:
	if _picker == null:
		return
	_file_dialog_mode = &"open"
	_picker.title = "Open MVR or PVZ"
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_picker.filters = PackedStringArray(["*.mvr, *.pvz ; MVR or Peraviz Project", "*.mvr ; MVR", "*.pvz ; Peraviz Project"])
	_picker.popup_centered_ratio(0.7)

func _on_save_project_pressed() -> void:
	if _picker == null:
		return
	_file_dialog_mode = &"save"
	_picker.title = "Save Peraviz Project"
	_picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_picker.filters = PackedStringArray(["*.pvz ; Peraviz Project"])
	_picker.popup_centered_ratio(0.7)

func _on_file_dialog_file_selected(path: String) -> void:
	if _file_dialog_mode == &"save":
		if _save_file_selected_callback.is_valid():
			_save_file_selected_callback.call(path)
		return
	if _open_file_selected_callback.is_valid():
		_open_file_selected_callback.call(path)

func _on_visual_settings_pressed() -> void:
	if not _open_visual_settings_callback.is_valid():
		return
	_open_visual_settings_callback.call()
