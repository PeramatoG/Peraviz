extends RefCounted
class_name MvrXchangeController

signal stations_changed(stations: Array)
signal status_changed(is_running: bool, station_count: int, message: String)

const POLL_INTERVAL_SEC: float = 1.0

var _owner: Node
var _client = null
var _timer: Timer
var _stations: Array = []
var _last_signature: String = ""

func configure(owner: Node) -> void:
	_owner = owner
	if ClassDB.class_exists("PeravizMvrXchangeClient"):
		_client = ClassDB.instantiate("PeravizMvrXchangeClient")
	_ensure_timer()

func is_available() -> bool:
	return _client != null

func start_discovery(group: String = "Default", bind_ip: String = "") -> bool:
	if _client == null:
		status_changed.emit(false, 0, "MVR-xchange unavailable in this build")
		return false
	var ok: bool = bool(_client.start(group, bind_ip))
	if ok:
		_timer.start(POLL_INTERVAL_SEC)
	_poll()
	return ok

func stop_discovery() -> void:
	if _timer != null:
		_timer.stop()
	if _client != null:
		_client.stop()
	_stations = []
	_last_signature = ""
	stations_changed.emit(_stations)
	status_changed.emit(false, 0, "OFF")

func is_running() -> bool:
	return _client != null and bool(_client.is_running())

func get_stations() -> Array:
	return _stations.duplicate(true)

func get_last_error() -> String:
	return "" if _client == null else str(_client.get_last_error())

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
	var signature: String = JSON.stringify(_stations)
	if signature != _last_signature:
		_last_signature = signature
		stations_changed.emit(_stations)
	var message: String = "Discovering" if is_running() else "OFF"
	var error: String = get_last_error()
	if not error.is_empty():
		message = error
	status_changed.emit(is_running(), _stations.size(), message)
