extends "res://tests/gdscript/helpers/dense_mutation_loader.gd"

const Surface = preload("res://scripts/beam_renderers/surface_footprint_presentation.gd")
var _fixture_gobo_projector = preload("res://scripts/fixture_gobo_projector.gd").new()
var _fixture_light_apply_service: RefCounted
var _beam_params_template_cache: Dictionary = {}
var _live_settings_trace: Dictionary = {}
var _has_loaded_bounds: bool = false
var _loaded_bounds: AABB
var proxies_root: Node3D

func _refresh_native_gobo_presentation(light: SpotLight3D, texture: Texture2D = null) -> void:
	projector_refreshes += 1
	Surface.refresh(self, light, texture)

func _build_cached_beam_params(light: SpotLight3D, angle: float, color: Color, dimmer: float, intensity: float, radius: float, defaults: Dictionary) -> Dictionary:
	var params: Dictionary = super._build_cached_beam_params(light, angle, color, dimmer, intensity, radius, defaults)
	params["footprint_softness"] = float(_visual_settings.get("footprint_softness", 0.10))
	params["beam_type"] = light.get_meta("test_beam_type", "Wash")
	return params
