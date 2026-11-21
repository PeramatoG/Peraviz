extends RefCounted

signal changed
var native: RefCounted
var context: Dictionary = {}
var _owner: Node
var _shell: Node
var _export_dialog: FileDialog
var _edit_menu: PopupMenu
var _busy: bool = false
var patch_error: String = ""
var patch_warnings: Array = []
var _discard_dialog: ConfirmationDialog
var _pending_open: Callable
var _pending_generation: int = -1

func configure(owner: Node, shell: Node) -> void:
	_owner = owner
	_shell = shell
	var file := MenuButton.new()
	file.text = "File"
	_shell._row.add_child(file)
	_shell._row.move_child(file, _shell._row.get_node("ViewMenu").get_index())
	file.get_popup().add_item("Export MVR…", 0)
	file.get_popup().id_pressed.connect(func(_id: int) -> void: export_dialog())
	file.get_popup().about_to_popup.connect(func() -> void: file.get_popup().set_item_disabled(0, native == null or not native.state().ready or _owner._scene_loading))
	var edit := MenuButton.new()
	edit.text = "Edit"
	_shell._row.add_child(edit)
	_shell._row.move_child(edit, file.get_index()+1)
	_edit_menu = edit.get_popup()
	_edit_menu.add_item("Undo MVR edit (Ctrl+Z)", 0)
	_edit_menu.add_item("Redo MVR edit (Ctrl+Y / Ctrl+Shift+Z)", 1)
	_edit_menu.id_pressed.connect(func(id: int) -> void: history(id == 1))
	_edit_menu.about_to_popup.connect(_sync_menu)
	_export_dialog = FileDialog.new()
	_export_dialog.title = "Export current MVR document"
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.filters = PackedStringArray(["*.mvr ; MVR document"])
	_owner.get_node("UIRoot").add_child(_export_dialog)
	_export_dialog.file_selected.connect(func(path: String) -> void: export_mvr(path))
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "Unsaved MVR document edits"
	_discard_dialog.dialog_text = "Save a PVZ or export the current MVR before leaving. Discard the unsaved edits?"
	_discard_dialog.ok_button_text = "Discard and continue"
	_discard_dialog.cancel_button_text = "Keep editing"
	_owner.get_node("UIRoot").add_child(_discard_dialog)
	_discard_dialog.confirmed.connect(_discard_confirmed)
	_discard_dialog.canceled.connect(func() -> void: _pending_open = Callable())
	_owner._ui_controller.open_guard = guard_open
	_owner.get_tree().auto_accept_quit = false
	_owner.get_window().close_requested.connect(_request_quit)
	changed.connect(_on_changed)

func _on_changed() -> void:
	_shell.set_project_name(_shell._project_label.tooltip_text)
	_sync_menu()

func open_scene(path: String, project_context: Dictionary = {}) -> void:
	retire()
	context = project_context.duplicate(true)
	if ClassDB.class_exists("PeravizMvrDocument"):
		native = ClassDB.instantiate("PeravizMvrDocument")
		if not native.open(ProjectSettings.globalize_path(path)): _message("MVR editing unavailable: " + str(native.state().error))
	changed.emit()

func retire() -> void:
	_pending_open = Callable()
	if _discard_dialog != null: _discard_dialog.hide()
	native = null
	context.clear()
	changed.emit()

func state() -> Dictionary:
	return native.state() if native != null else {"ready": false, "dirty": false, "can_undo": false, "can_redo": false}

func fixture(id: String) -> Dictionary:
	return native.fixture(id) if native != null else {"editable": false, "reason": "Unavailable in this preview: no canonical MVR document"}

func apply(ids: PackedStringArray, axis: int, value: bool) -> bool:
	if native == null or _busy or _owner._scene_loading: return false
	for id in ids:
		var node: Node = _shell.selection.node_for(id)
		if node == null or str(node.get_meta("peraviz_type","")) != "fixture":
			_message("Select canonical published fixtures only; no document change was made.")
			return false
	if not native.prepare(ids,axis,value):
		_message(str(native.state().error))
		return false
	return _commit_pending()

# Canonical rows come from the document; parser capabilities only annotate supported routing.
func patch_fixture(id: String) -> Dictionary:
	var result := fixture(id).duplicate(true)
	var capabilities: Dictionary = _owner._loader.document_patch_info(id)
	result["breaks"] = capabilities.get("breaks", [])
	if not capabilities.get("editable", false):
		result["patch_editable"] = false
		result["patch_reason"] = capabilities.get("reason", "Selected GDTF mode is unavailable")
	return result

func apply_patch(id: String, break_id: int, universe: int, address: int, operation: String = "set") -> bool:
	patch_error = ""
	patch_warnings.clear()
	if native == null or _busy or _owner._scene_loading: return false
	var node: Node = _shell.selection.node_for(id)
	if node == null or str(node.get_meta("peraviz_type", "")) != "fixture":
		patch_error = "Select a canonical published fixture."
		return false
	if not native.prepare_patch(id, break_id, universe, address, operation):
		patch_error = str(native.state().error)
		_message(patch_error)
		return false
	return _commit_pending()

func history(redo: bool) -> bool:
	if native == null or _busy or _owner._scene_loading: return false
	if not native.prepare_history(redo): return false
	return _commit_pending()

# The staged native document command is published only after the exclusive runtime boundary succeeds.
func _commit_pending() -> bool:
	_busy = true
	var values: Array = native.pending_values()
	var runtime = _owner._dmx_controller._dmx_fixture_runtime
	if native.pending_patch(): return _commit_patch(values, runtime)
	var triples := PackedInt32Array()
	if runtime != null:
		for row in values:
			var id: int = int(runtime._native_fixture_ids_by_uuid.get(row.fixture_uuid, -1))
			if id > 0: triples.append_array(PackedInt32Array([id,int(row.pan),int(row.tilt)]))
	if not triples.is_empty():
		var adapter = _owner._fixture_light_apply_service._dense_adapter
		if adapter == null or not adapter._native.set_fixture_inversions(runtime._native_visual_runtime,adapter._generation,triples):
			native.cancel()
			_busy = false
			_message("MVR edit rejected: the native runtime is not at a safe document transaction boundary.")
			return false
	_owner._loader.sync_document_inversions(values)
	var committed: bool = native.commit()
	if runtime != null and not triples.is_empty():
		# Poll the existing presentation owner with held native input; no packet or geometry rebuild is required.
		runtime.apply_visual_frame(_owner._dmx_controller._dmx_receiver,_owner,_owner._fixture_light_apply_service,0.0)
	_busy = false
	changed.emit()
	return committed

# Install a validated same-topology native route candidate before publishing XML/history.
func _commit_patch(values: Array, runtime) -> bool:
	var row: Dictionary = values[0]
	var candidate: Dictionary = _owner._loader.stage_document_patch(row.fixture_uuid, row.addresses, int(_owner._dmx_controller._dmx_universe_offset_input.value))
	var adapter = _owner._fixture_light_apply_service._dense_adapter
	var ok: bool = candidate.get("ok", false) and runtime != null and adapter != null
	if ok: ok = adapter._native.apply_document_patch(runtime._native_visual_runtime, adapter._generation, _owner._loader)
	if not ok:
		native.cancel()
		_owner._loader.cancel_document_patch()
		patch_error = "MVR break %d: %s" % [int(row.patch_break), str(candidate.get("error", "Native runtime could not safely install the patch; no edit was committed."))]
		_busy = false
		_message(patch_error)
		return false
	var committed: bool = native.commit()
	patch_error = ""
	patch_warnings = candidate.get("warnings", [])
	runtime._receiver_subscription_generation = -1
	# Existing provider owns display caches; no fixture nodes or renderer targets are rebuilt.
	_owner._fixture_row_provider.set_dmx_state(runtime._bindings, runtime._unbound)
	runtime.apply_visual_frame(_owner._dmx_controller._dmx_receiver, _owner, _owner._fixture_light_apply_service, 0.0)
	_busy = false
	changed.emit()
	if not patch_warnings.is_empty(): _message(str(patch_warnings[0]))
	return committed

func mark_saved() -> void:
	if native != null: native.mark_saved()
	changed.emit()

func export_dialog() -> void:
	if native == null or not native.state().ready: return
	_export_dialog.current_file = "edited-scene.mvr"
	_export_dialog.popup_centered_ratio(0.75)

func export_mvr(path: String) -> bool:
	if native == null or _busy or _owner._scene_loading: return false
	if path.get_extension().to_lower() != "mvr": path += ".mvr"
	var ok: bool = native.export_mvr(ProjectSettings.globalize_path(path))
	_message("Exported current MVR: " + path if ok else "MVR export failed: " + str(native.state().error))
	return ok

func _sync_menu() -> void:
	var current := state()
	_edit_menu.set_item_disabled(0, not current.can_undo or _busy or _owner._scene_loading)
	_edit_menu.set_item_disabled(1, not current.can_redo or _busy or _owner._scene_loading)

func _message(text: String) -> void:
	if _owner._status_presenter != null: _owner._status_presenter.show_toast(text)

func guard_open(action: Callable) -> bool:
	if not state().dirty: return true
	_pending_open = action
	_pending_generation = _owner._scene_load_generation
	_discard_dialog.popup_centered()
	return false

func _discard_confirmed() -> void:
	var action := _pending_open
	_pending_open = Callable()
	if _pending_generation == _owner._scene_load_generation and action.is_valid(): action.call()

func _request_quit() -> void:
	var action := Callable(_owner.get_tree(), "quit")
	if guard_open(action): action.call()
