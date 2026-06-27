extends RefCounted
class_name MvrXchangeController

signal stations_changed(stations: Array)
signal status_changed(is_running: bool, station_count: int, message: String)
signal state_changed(state: String, metadata: Dictionary)
signal mvr_file_received(path: String, metadata: Dictionary)

const POLL_INTERVAL_SEC: float = 0.5
const STATE_DISCONNECTED: String = "disconnected"
const STATE_DISCOVERING: String = "discovering"
const STATE_STATION_FOUND: String = "station_found"
const STATE_JOINING: String = "joining"
const STATE_JOINED: String = "joined"
const STATE_REVISION_AVAILABLE: String = "revision_available"
const STATE_REQUESTING: String = "requesting"
const STATE_RECEIVING: String = "receiving"
const STATE_RECEIVED: String = "received"
const STATE_ERROR: String = "error"

var _owner: Node
var _client = null
var _timer: Timer
var _stations: Array = []
var _commits: Array = []
var _last_signature: String = ""
var _selected_service_name: String = ""
var _state: String = STATE_DISCONNECTED
var _transfer_dir: String = ""

func configure(owner: Node) -> void:
	_owner = owner
	_transfer_dir = ProjectSettings.globalize_path("user://mvrxchange")
	if ClassDB.class_exists("PeravizMvrXchangeClient"):
		_client = ClassDB.instantiate("PeravizMvrXchangeClient")
	_ensure_timer()

func is_available() -> bool:
	return _client != null

func start_discovery(group: String = "Default", bind_ip: String = "") -> bool:
	if _client == null:
		_set_state(STATE_ERROR, {"message": "MVR-xchange unavailable in this build"})
		status_changed.emit(false, 0, "MVR-xchange unavailable in this build")
		return false
	var ok: bool = bool(_client.start(group, bind_ip))
	if ok:
		_timer.start(POLL_INTERVAL_SEC)
		_set_state(STATE_DISCOVERING, {})
	_poll()
	return ok

func stop_discovery() -> void:
	if _timer != null:
		_timer.stop()
	if _client != null:
		_client.stop()
	_stations = []
	_commits = []
	_selected_service_name = ""
	_last_signature = ""
	stations_changed.emit(_stations)
	_set_state(STATE_DISCONNECTED, {})
	status_changed.emit(false, 0, "OFF")

func is_running() -> bool:
	return _client != null and bool(_client.is_running())

func get_stations() -> Array:
	return _stations.duplicate(true)

func get_commits() -> Array:
	return _commits.duplicate(true)

func get_selected_service_name() -> String:
	return _selected_service_name

func can_request_update() -> bool:
	return _state == STATE_REVISION_AVAILABLE and not _selected_service_name.is_empty() and not _is_transfer_busy()

func get_last_error() -> String:
	return "" if _client == null else str(_client.get_last_error())

func select_station(service_name: String) -> void:
	_selected_service_name = service_name
	_join_selected_station()

func request_update() -> bool:
	if _client == null or not can_request_update():
		return false
	DirAccess.make_dir_recursive_absolute(_transfer_dir)
	var safe_name: String = _selected_service_name.replace(".", "_").replace("@", "_").replace("/", "_").replace("\\", "_")
	var target_path: String = _transfer_dir.path_join("%s_%d.mvr" % [safe_name, Time.get_unix_time_from_system()])
	var ok: bool = bool(_client.request_latest_mvr(_selected_service_name, target_path))
	if ok:
		_set_state(STATE_REQUESTING, {"service_name": _selected_service_name, "path": target_path, "message": "Requesting MVR..."})
	return ok

func mark_loaded(path: String) -> void:
	_set_state(STATE_RECEIVED, {"path": path, "message": "MVR loaded"})

func _ensure_timer() -> void:
	if _owner == null or _timer != null:
		return
	_timer = Timer.new()
	_timer.name = "MvrXchangePollTimer"
	_timer.wait_time = POLL_INTERVAL_SEC
	_timer.one_shot = false
	_owner.add_child(_timer)
	_timer.timeout.connect(_poll)

func _poll() -> void:
	if _client == null:
		return
	_stations = _client.get_stations()
	_commits = _client.get_commits() if _client.has_method("get_commits") else []
	_handle_events(_client.poll_events() if _client.has_method("poll_events") else [])
	var signature: String = JSON.stringify(_stations) + JSON.stringify(_commits) + _state + _selected_service_name
	if signature != _last_signature:
		_last_signature = signature
		stations_changed.emit(_stations)
		state_changed.emit(_state, _state_metadata())
	if _selected_service_name.is_empty() and not _stations.is_empty():
		var first: Dictionary = _stations[0] as Dictionary
		select_station(str(first.get("service_name", "")))
	var message: String = _message_for_state()
	var error: String = get_last_error()
	if _state == STATE_ERROR and not error.is_empty():
		message = error
	status_changed.emit(is_running(), _stations.size(), message)

func _join_selected_station() -> void:
	if _client == null or _selected_service_name.is_empty():
		return
	_set_state(STATE_JOINING, {"service_name": _selected_service_name, "message": "Joining station..."})
	_client.join_station(_selected_service_name)

func _handle_events(events: Array) -> void:
	for event_value in events:
		var event: Dictionary = event_value as Dictionary
		var type: String = str(event.get("type", ""))
		match type:
			"join_started":
				_set_state(STATE_JOINING, event)
			"join_succeeded":
				_set_state(STATE_JOINED, event)
			"join_failed", "error":
				_set_state(STATE_ERROR, event)
			"commit_available":
				_set_state(STATE_REVISION_AVAILABLE, event)
			"transfer_started":
				_set_state(STATE_RECEIVING, event)
			"transfer_progress":
				_set_state(STATE_RECEIVING, event)
			"transfer_finished":
				_set_state(STATE_RECEIVED, event)
				mvr_file_received.emit(str(event.get("path", "")), event)
			"transfer_failed", "protocol_error":
				_set_state(STATE_ERROR, event)

func _set_state(state: String, metadata: Dictionary) -> void:
	_state = state
	state_changed.emit(_state, metadata)

func _state_metadata() -> Dictionary:
	return {"selected_service_name": _selected_service_name, "commits": _commits, "can_update": can_request_update(), "transfer_busy": _is_transfer_busy()}

func _is_transfer_busy() -> bool:
	if _client == null or not _client.has_method("get_stats"):
		return false
	var stats: Dictionary = _client.get_stats()
	return bool(stats.get("transfer_busy", false))

func _message_for_state() -> String:
	match _state:
		STATE_DISCONNECTED:
			return "OFF"
		STATE_DISCOVERING:
			return "Discovering"
		STATE_STATION_FOUND:
			return "Station found"
		STATE_JOINING:
			return "Joining station..."
		STATE_JOINED:
			return "Joined"
		STATE_REVISION_AVAILABLE:
			return "New MVR revision available"
		STATE_REQUESTING:
			return "Requesting MVR..."
		STATE_RECEIVING:
			return "Receiving MVR..."
		STATE_RECEIVED:
			return "MVR loaded"
		STATE_ERROR:
			return "Error"
	return "OFF"
