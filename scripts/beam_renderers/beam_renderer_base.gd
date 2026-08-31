extends RefCounted

class_name BeamRendererBase

const INTENSITY_UNRESOLVED: int = 0
const INTENSITY_UNCHANGED: int = 1
const INTENSITY_CHANGED: int = 2

func configure(_view_camera: Camera3D, _settings: Dictionary) -> void:
	pass

func ensure_beam(_light: SpotLight3D) -> void:
	pass

func update_beam(_light: SpotLight3D, _params: Dictionary) -> void:
	pass

func is_beam_dynamic_ready(_light: SpotLight3D) -> bool:
	return false

func update_beam_intensity(_light: SpotLight3D, _params: Dictionary) -> int:
	return INTENSITY_UNRESOLVED

func get_last_parameter_write_count() -> int:
	return 0

func apply_beam_optics(_light: SpotLight3D, _params: Dictionary) -> Dictionary:
	return {"applied": false, "failure_reason": "renderer does not implement BeamOptics"}

func get_beam_optics_state(_light: SpotLight3D) -> Dictionary:
	return {}

func get_beam_resource(_light: SpotLight3D) -> MeshInstance3D:
	return null

func cleanup_beam(_light: SpotLight3D) -> void:
	pass
