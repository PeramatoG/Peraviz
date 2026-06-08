extends RefCounted
class_name PeravizProjectArchive

const FORMAT_NAME: String = "PeravizProject"
const FORMAT_VERSION: int = 1
const PROJECT_JSON_PATH: String = "project.json"
const SCENE_MVR_PATH: String = "scene.mvr"
const VISUAL_SETTINGS_PATH: String = "visual_settings.json"
const DMX_SETTINGS_PATH: String = "dmx_settings.json"
const APP_STATE_PATH: String = "app_state.json"
const FIXTURE_OVERRIDES_PATH: String = "fixture_overrides.json"
const CACHE_DIR: String = "user://pvz_cache"

func save_project(project_path: String, source_mvr_path: String, peraviz_version: String, visual_settings: Dictionary, dmx_settings: Dictionary, app_state: Dictionary) -> Dictionary:
	if source_mvr_path.is_empty() or not FileAccess.file_exists(source_mvr_path):
		return _error("No loaded MVR file is available to save into the project archive.")

	var mvr_bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_mvr_path)
	if mvr_bytes.is_empty() and FileAccess.get_open_error() != OK:
		return _error("Unable to read the loaded MVR file.")

	var normalized_path: String = _ensure_extension(project_path, "pvz")
	if normalized_path.is_empty():
		return _error("Choose a valid PVZ filename before saving.")
	if not _parent_directory_exists(normalized_path):
		return _error("Unable to create PVZ archive because the target directory does not exist: %s" % normalized_path.get_base_dir())

	var packer := ZIPPacker.new()
	var open_error: Error = packer.open(normalized_path)
	if open_error != OK:
		return _error("Unable to create PVZ archive: %s" % error_string(open_error))

	var project_metadata := {
		"format": FORMAT_NAME,
		"format_version": FORMAT_VERSION,
		"peraviz_version": peraviz_version,
		"scene_mvr": SCENE_MVR_PATH,
	}
	var write_error: Error = _write_json_file(packer, PROJECT_JSON_PATH, project_metadata)
	if write_error == OK:
		write_error = _write_raw_file(packer, SCENE_MVR_PATH, mvr_bytes)
	if write_error == OK:
		write_error = _write_json_file(packer, VISUAL_SETTINGS_PATH, _normalize_json_value(visual_settings))
	if write_error == OK:
		write_error = _write_json_file(packer, DMX_SETTINGS_PATH, _merge_dmx_defaults(dmx_settings))
	if write_error == OK:
		write_error = _write_json_file(packer, APP_STATE_PATH, app_state)
	if write_error == OK:
		write_error = _write_json_file(packer, FIXTURE_OVERRIDES_PATH, {})

	var close_error: Error = packer.close()
	if write_error != OK:
		return _error("Unable to write PVZ archive: %s" % error_string(write_error))
	if close_error != OK:
		return _error("Unable to finalize PVZ archive: %s" % error_string(close_error))
	if not FileAccess.file_exists(normalized_path):
		return _error("PVZ archive was finalized but no file appeared at the selected path: %s" % normalized_path)

	return {
		"ok": true,
		"project_path": normalized_path,
	}

func open_project(project_path: String) -> Dictionary:
	if project_path.is_empty() or not FileAccess.file_exists(project_path):
		return _error("PVZ file does not exist.")

	var reader := ZIPReader.new()
	var open_error: Error = reader.open(project_path)
	if open_error != OK:
		return _error("Unable to open PVZ archive: %s" % error_string(open_error))

	var files: PackedStringArray = reader.get_files()
	if not files.has(SCENE_MVR_PATH):
		reader.close()
		return _error("Invalid PVZ archive: missing scene.mvr.")

	var project_metadata: Dictionary = _read_json_file(reader, PROJECT_JSON_PATH, {})
	var visual_settings: Dictionary = {}
	var visual_settings_value: Variant = _denormalize_json_value(_read_json_file(reader, VISUAL_SETTINGS_PATH, {}))
	if visual_settings_value is Dictionary:
		visual_settings = visual_settings_value as Dictionary
	var dmx_settings: Dictionary = _merge_dmx_defaults(_read_json_file(reader, DMX_SETTINGS_PATH, {}))
	var app_state: Dictionary = _read_json_file(reader, APP_STATE_PATH, {})
	var fixture_overrides: Dictionary = _read_json_file(reader, FIXTURE_OVERRIDES_PATH, {})
	var scene_bytes: PackedByteArray = reader.read_file(SCENE_MVR_PATH)
	reader.close()

	if scene_bytes.is_empty():
		return _error("Invalid PVZ archive: scene.mvr is empty or unreadable.")

	var extracted_scene_path: String = _build_extracted_scene_path(project_path)
	var ensure_result: Error = _ensure_cache_dir()
	if ensure_result != OK:
		return _error("Unable to prepare PVZ cache directory: %s" % error_string(ensure_result))
	var scene_file := FileAccess.open(extracted_scene_path, FileAccess.WRITE)
	if scene_file == null:
		return _error("Unable to extract scene.mvr from PVZ archive.")
	scene_file.store_buffer(scene_bytes)
	scene_file.close()

	return {
		"ok": true,
		"scene_path": extracted_scene_path,
		"project": project_metadata,
		"visual_settings": visual_settings,
		"dmx_settings": dmx_settings,
		"app_state": app_state,
		"fixture_overrides": fixture_overrides,
	}

func get_default_dmx_settings() -> Dictionary:
	return {
		"universe_offset": -1,
		"auto_start_dmx": false,
		"dmx_enabled_when_saved": false,
	}

func _write_json_file(packer: ZIPPacker, archive_path: String, value: Variant) -> Error:
	var json_text: String = JSON.stringify(value, "\t") + "\n"
	return _write_raw_file(packer, archive_path, json_text.to_utf8_buffer())

func _write_raw_file(packer: ZIPPacker, archive_path: String, bytes: PackedByteArray) -> Error:
	var start_error: Error = packer.start_file(archive_path)
	if start_error != OK:
		return start_error
	var write_error: Error = packer.write_file(bytes)
	if write_error != OK:
		return write_error
	return packer.close_file()

func _read_json_file(reader: ZIPReader, archive_path: String, fallback: Dictionary) -> Dictionary:
	if not reader.get_files().has(archive_path):
		return fallback.duplicate(true)
	var bytes: PackedByteArray = reader.read_file(archive_path)
	if bytes.is_empty():
		return fallback.duplicate(true)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed as Dictionary
	return fallback.duplicate(true)

func _merge_dmx_defaults(settings: Dictionary) -> Dictionary:
	var merged: Dictionary = get_default_dmx_settings()
	for key in settings.keys():
		if merged.has(key):
			merged[key] = settings[key]
	merged["universe_offset"] = int(merged.get("universe_offset", -1))
	merged["auto_start_dmx"] = bool(merged.get("auto_start_dmx", false))
	merged["dmx_enabled_when_saved"] = bool(merged.get("dmx_enabled_when_saved", false))
	return merged

func _normalize_json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for key in value.keys():
			normalized[str(key)] = _normalize_json_value(value[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_normalize_json_value(item))
		return normalized_array
	if value is Color:
		var color: Color = value
		return {
			"type": "Color",
			"r": color.r,
			"g": color.g,
			"b": color.b,
			"a": color.a,
		}
	return value

func _denormalize_json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		if str(dictionary.get("type", "")) == "Color":
			return Color(
				float(dictionary.get("r", 0.0)),
				float(dictionary.get("g", 0.0)),
				float(dictionary.get("b", 0.0)),
				float(dictionary.get("a", 1.0))
			)
		var denormalized: Dictionary = {}
		for key in dictionary.keys():
			denormalized[key] = _denormalize_json_value(dictionary[key])
		return denormalized
	if value is Array:
		var denormalized_array: Array = []
		for item in value:
			denormalized_array.append(_denormalize_json_value(item))
		return denormalized_array
	return value

func _build_extracted_scene_path(project_path: String) -> String:
	var hash_text: String = str(project_path.hash()).replace("-", "n")
	return "%s/%s_scene.mvr" % [CACHE_DIR, hash_text]

func _ensure_cache_dir() -> Error:
	var absolute_cache_dir: String = ProjectSettings.globalize_path(CACHE_DIR)
	return DirAccess.make_dir_recursive_absolute(absolute_cache_dir)

func _ensure_extension(path: String, extension: String) -> String:
	if path.get_extension().to_lower() == extension.to_lower():
		return path
	return "%s.%s" % [path, extension]

func _parent_directory_exists(path: String) -> bool:
	var base_dir: String = path.get_base_dir()
	if base_dir.is_empty() or base_dir == path:
		return true
	if base_dir.begins_with("user://") or base_dir.begins_with("res://"):
		base_dir = ProjectSettings.globalize_path(base_dir)
	return DirAccess.dir_exists_absolute(base_dir)

func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
