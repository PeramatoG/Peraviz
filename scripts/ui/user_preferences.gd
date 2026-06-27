extends RefCounted
class_name UserPreferences

const SETTINGS_FILE_PATH: String = "user://user_preferences.cfg"
const SETTINGS_SECTION: String = "ui"
const SESSION_SETTINGS_SECTION: String = "session"

const KEY_SIDEBAR_OPEN: String = "sidebar_open"
const KEY_ADVANCED_MODE: String = "advanced_mode"
const KEY_LAST_SETTINGS_TAB: String = "last_settings_tab"
const KEY_MODULE_USER_VISIBLE: String = "module_user_visible"
const KEY_MODULE_ADVANCED_VISIBLE: String = "module_advanced_visible"
const KEY_MODULE_DEBUG_VISIBLE: String = "module_debug_visible"
const KEY_LAST_FILE_PATH: String = "last_file_path"
const KEY_LAST_FILE_TYPE: String = "last_file_type"
const KEY_AUTO_LOAD_LAST_FILE: String = "auto_load_last_file"
const KEY_AUTO_START_DMX: String = "auto_start_dmx"
const KEY_MVR_XCHANGE_GROUP: String = "mvr_xchange_group"
const KEY_MVR_XCHANGE_BIND_IP: String = "mvr_xchange_bind_ip"
const KEY_MVR_XCHANGE_AUTO_UPDATE: String = "mvr_xchange_auto_update"

const DEFAULT_SIDEBAR_OPEN: bool = false
const DEFAULT_ADVANCED_MODE: bool = false
const DEFAULT_LAST_SETTINGS_TAB: int = 0
const DEFAULT_MODULE_VISIBILITY := {
	"User": true,
	"Advanced": true,
	"Debug": false,
}
const DEFAULT_LAST_FILE_PATH: String = ""
const DEFAULT_LAST_FILE_TYPE: String = ""
const DEFAULT_AUTO_LOAD_LAST_FILE: bool = true
const DEFAULT_AUTO_START_DMX: bool = false
const DEFAULT_MVR_XCHANGE_GROUP: String = "Default"
const DEFAULT_MVR_XCHANGE_BIND_IP: String = ""
const DEFAULT_MVR_XCHANGE_AUTO_UPDATE: bool = false

var sidebar_open: bool = DEFAULT_SIDEBAR_OPEN
var advanced_mode: bool = DEFAULT_ADVANCED_MODE
var last_settings_tab: int = DEFAULT_LAST_SETTINGS_TAB
var module_visibility: Dictionary = DEFAULT_MODULE_VISIBILITY.duplicate(true)
var last_file_path: String = DEFAULT_LAST_FILE_PATH
var last_file_type: String = DEFAULT_LAST_FILE_TYPE
var auto_load_last_file: bool = DEFAULT_AUTO_LOAD_LAST_FILE
var auto_start_dmx: bool = DEFAULT_AUTO_START_DMX
var mvr_xchange_group: String = DEFAULT_MVR_XCHANGE_GROUP
var mvr_xchange_bind_ip: String = DEFAULT_MVR_XCHANGE_BIND_IP
var mvr_xchange_auto_update: bool = DEFAULT_MVR_XCHANGE_AUTO_UPDATE

func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		_apply_defaults()
		return

	sidebar_open = bool(config.get_value(SETTINGS_SECTION, KEY_SIDEBAR_OPEN, DEFAULT_SIDEBAR_OPEN))
	advanced_mode = bool(config.get_value(SETTINGS_SECTION, KEY_ADVANCED_MODE, DEFAULT_ADVANCED_MODE))
	last_settings_tab = max(0, int(config.get_value(SETTINGS_SECTION, KEY_LAST_SETTINGS_TAB, DEFAULT_LAST_SETTINGS_TAB)))

	module_visibility = DEFAULT_MODULE_VISIBILITY.duplicate(true)
	module_visibility["User"] = bool(config.get_value(SETTINGS_SECTION, KEY_MODULE_USER_VISIBLE, DEFAULT_MODULE_VISIBILITY["User"]))
	module_visibility["Advanced"] = bool(config.get_value(SETTINGS_SECTION, KEY_MODULE_ADVANCED_VISIBLE, DEFAULT_MODULE_VISIBILITY["Advanced"]))
	module_visibility["Debug"] = bool(config.get_value(SETTINGS_SECTION, KEY_MODULE_DEBUG_VISIBLE, DEFAULT_MODULE_VISIBILITY["Debug"]))

	last_file_path = str(config.get_value(SESSION_SETTINGS_SECTION, KEY_LAST_FILE_PATH, DEFAULT_LAST_FILE_PATH))
	last_file_type = str(config.get_value(SESSION_SETTINGS_SECTION, KEY_LAST_FILE_TYPE, DEFAULT_LAST_FILE_TYPE)).to_lower()
	auto_load_last_file = bool(config.get_value(SESSION_SETTINGS_SECTION, KEY_AUTO_LOAD_LAST_FILE, DEFAULT_AUTO_LOAD_LAST_FILE))
	auto_start_dmx = bool(config.get_value(SESSION_SETTINGS_SECTION, KEY_AUTO_START_DMX, DEFAULT_AUTO_START_DMX))
	mvr_xchange_group = str(config.get_value(SETTINGS_SECTION, KEY_MVR_XCHANGE_GROUP, DEFAULT_MVR_XCHANGE_GROUP))
	mvr_xchange_bind_ip = str(config.get_value(SETTINGS_SECTION, KEY_MVR_XCHANGE_BIND_IP, DEFAULT_MVR_XCHANGE_BIND_IP))
	mvr_xchange_auto_update = bool(config.get_value(SETTINGS_SECTION, KEY_MVR_XCHANGE_AUTO_UPDATE, DEFAULT_MVR_XCHANGE_AUTO_UPDATE))

func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, KEY_SIDEBAR_OPEN, sidebar_open)
	config.set_value(SETTINGS_SECTION, KEY_ADVANCED_MODE, advanced_mode)
	config.set_value(SETTINGS_SECTION, KEY_LAST_SETTINGS_TAB, max(0, last_settings_tab))
	config.set_value(SETTINGS_SECTION, KEY_MODULE_USER_VISIBLE, bool(module_visibility.get("User", DEFAULT_MODULE_VISIBILITY["User"])))
	config.set_value(SETTINGS_SECTION, KEY_MODULE_ADVANCED_VISIBLE, bool(module_visibility.get("Advanced", DEFAULT_MODULE_VISIBILITY["Advanced"])))
	config.set_value(SETTINGS_SECTION, KEY_MODULE_DEBUG_VISIBLE, bool(module_visibility.get("Debug", DEFAULT_MODULE_VISIBILITY["Debug"])))
	config.set_value(SESSION_SETTINGS_SECTION, KEY_LAST_FILE_PATH, last_file_path)
	config.set_value(SESSION_SETTINGS_SECTION, KEY_LAST_FILE_TYPE, last_file_type)
	config.set_value(SESSION_SETTINGS_SECTION, KEY_AUTO_LOAD_LAST_FILE, auto_load_last_file)
	config.set_value(SESSION_SETTINGS_SECTION, KEY_AUTO_START_DMX, auto_start_dmx)
	config.set_value(SETTINGS_SECTION, KEY_MVR_XCHANGE_GROUP, mvr_xchange_group)
	config.set_value(SETTINGS_SECTION, KEY_MVR_XCHANGE_BIND_IP, mvr_xchange_bind_ip)
	config.set_value(SETTINGS_SECTION, KEY_MVR_XCHANGE_AUTO_UPDATE, mvr_xchange_auto_update)

	var save_result: int = config.save(SETTINGS_FILE_PATH)
	if save_result != OK:
		push_warning("Failed to save user preferences to %s (error=%d)" % [SETTINGS_FILE_PATH, save_result])

func get_module_visible(module_name: StringName, default_value: bool) -> bool:
	return bool(module_visibility.get(str(module_name), default_value))

func set_module_visible(module_name: StringName, visible: bool) -> void:
	module_visibility[str(module_name)] = visible

func _apply_defaults() -> void:
	sidebar_open = DEFAULT_SIDEBAR_OPEN
	advanced_mode = DEFAULT_ADVANCED_MODE
	last_settings_tab = DEFAULT_LAST_SETTINGS_TAB
	module_visibility = DEFAULT_MODULE_VISIBILITY.duplicate(true)
	last_file_path = DEFAULT_LAST_FILE_PATH
	last_file_type = DEFAULT_LAST_FILE_TYPE
	auto_load_last_file = DEFAULT_AUTO_LOAD_LAST_FILE
	auto_start_dmx = DEFAULT_AUTO_START_DMX
	mvr_xchange_group = DEFAULT_MVR_XCHANGE_GROUP
	mvr_xchange_bind_ip = DEFAULT_MVR_XCHANGE_BIND_IP
	mvr_xchange_auto_update = DEFAULT_MVR_XCHANGE_AUTO_UPDATE
