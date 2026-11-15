extends RefCounted

var _window: Window
var _previous_mode: int = Window.MODE_WINDOWED
var _previous_position := Vector2i.ZERO
var _previous_size := Vector2i.ZERO
var active: bool = false

func configure(window: Window) -> void:
	_window = window

func toggle() -> void:
	set_fullscreen(not active)

func set_fullscreen(enabled: bool) -> void:
	if active == enabled or _window == null: return
	if enabled:
		_previous_mode = _window.mode
		_previous_position = _window.position
		_previous_size = _window.size
		_window.mode = Window.MODE_FULLSCREEN
	else:
		_window.mode = Window.MODE_WINDOWED
		_window.position = _previous_position
		_window.size = _previous_size
		_window.mode = _previous_mode
	active = enabled

static func install_escape(window: Window) -> void:
	window.window_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			window.hide()
			window.set_input_as_handled())
