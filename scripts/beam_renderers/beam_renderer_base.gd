extends RefCounted

class_name BeamRendererBase

# Keep new renderer modes behind this interface; see docs/batched-beam-rendering-plan.md for the planned batched path.

func configure(_view_camera: Camera3D, _settings: Dictionary) -> void:
	pass

func ensure_beam(_light: SpotLight3D) -> void:
	pass

func update_beam(_light: SpotLight3D, _params: Dictionary) -> void:
	pass

func update_beam_intensity(_light: SpotLight3D, _params: Dictionary) -> bool:
	return false

func cleanup_beam(_light: SpotLight3D) -> void:
	pass
