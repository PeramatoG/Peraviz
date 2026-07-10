extends RefCounted

class_name BeamRendererBase

func configure(_view_camera: Camera3D, _settings: Dictionary) -> void:
	pass

func ensure_beam(_light: SpotLight3D) -> void:
	pass

func update_beam(_light: SpotLight3D, _params: Dictionary) -> void:
	pass

func update_beam_intensity(_light: SpotLight3D, _params: Dictionary) -> bool:
	return false

func get_beam_resource(_light: SpotLight3D) -> MeshInstance3D:
	return null

func cleanup_beam(_light: SpotLight3D) -> void:
	pass
