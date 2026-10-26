extends Node3D

# Cold scenic-mesh subscription. Mechanical fixture playback never enters here.
var owner_ref: WeakRef
var _last: Transform3D
var _known: bool = false

func _ready() -> void:
	_last = global_transform
	_known = true
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED or not is_inside_tree(): return
	var current := global_transform
	if _known and current.is_equal_approx(_last): return
	_last = current
	_known = true
	var receiver_owner: RefCounted = owner_ref.get_ref() if owner_ref != null else null
	if receiver_owner != null: receiver_owner.receivers_moved()
