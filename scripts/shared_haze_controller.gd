extends RefCounted
class_name SharedHazeController

const NODE_NAME: String = "PeravizSharedHaze"

var _volume: FogVolume

func update(owner: Node3D, scene_bounds: AABB, enabled: bool, settings: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if not enabled or scene_bounds.size == Vector3.ZERO:
		if _volume != null and is_instance_valid(_volume):
			_volume.visible = false
		return
	if _volume == null or not is_instance_valid(_volume):
		_volume = FogVolume.new()
		_volume.name = NODE_NAME
		_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		_volume.material = FogMaterial.new()
		owner.add_child(_volume)
	var margin: float = clamp(float(settings.get("shared_haze_margin", 5.0)), 0.0, 30.0)
	_volume.global_position = scene_bounds.get_center()
	_volume.size = scene_bounds.size + Vector3.ONE * margin * 2.0
	var material: FogMaterial = _volume.material as FogMaterial
	material.density = clamp(float(settings.get("shared_haze_density", 0.015)), 0.0, 0.08)
	material.albedo = Color(0.92, 0.94, 1.0)
	material.emission = Color.BLACK
	material.height_falloff = 0.0
	_volume.visible = material.density > 0.0

func clear() -> void:
	if _volume != null and is_instance_valid(_volume):
		_volume.queue_free()
	_volume = null

func get_volume() -> FogVolume:
	return _volume if _volume != null and is_instance_valid(_volume) else null
