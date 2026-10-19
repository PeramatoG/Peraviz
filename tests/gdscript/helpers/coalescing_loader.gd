extends Node
const BEAM_INTENSITY_MAX: float = 50.0
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
var renderer = LegacyConeBeamRendererScript.new()
var output_count: int = 3
var anchors: Array[SpotLight3D] = []
var outputs: Array = []
var _cached_beam_defaults: Dictionary = {}
var _visual_settings: Dictionary = {"enable_realtime_spotlights": true}

func _ready() -> void:
	for index in range(output_count):
		var anchor := SpotLight3D.new()
		anchors.append(anchor)
		add_child(anchor)
		renderer.ensure_beam(anchor)
		outputs.append(_output(401 + index, anchor, index < output_count - 1))

func _output(output_id: int, anchor: SpotLight3D, projected: bool) -> Dictionary:
	return {
		"beam_render_target_id": output_id,
		"emitter_anchors": [anchor],
		"emitter_nodes": [],
		"lens_material_targets": [],
		"beam_optical_profile": {"beam_type": "Wash" if projected else "Glow", "has_projected_beam": projected, "projected_lumen_scale": 1.0 if projected else 0.0, "beam_angle": 25.0},
	}

func _has_native_dimmer_target(target_id: int) -> bool:
	return target_id == 201

func _get_native_dimmer_target_record(_target_id: int) -> Dictionary:
	return {"beam_output_records": outputs, "emitter_anchors": anchors}

func _has_native_color_target(target_id: int) -> bool:
	return target_id == 301 or target_id == 302

func _get_native_color_target_record(target_id: int) -> Dictionary:
	return {"beam_output_records": outputs if target_id == 301 else [outputs[1]], "emitter_anchors": anchors if target_id == 301 else [anchors[1]]}

func _get_beam_resource_for_light(light: SpotLight3D) -> MeshInstance3D:
	return renderer.get_beam_resource(light)

func _ensure_beam_runtime_for_light(light: SpotLight3D) -> void:
	renderer.ensure_beam(light)

func _update_beam_for_light(light: SpotLight3D, params: Dictionary) -> void:
	light.set_meta("peraviz_beam_last_params", params)
	renderer.update_beam(light, params)

func _update_beam_intensity_for_light(light: SpotLight3D, dimmer_norm: float, beam_color: Color, scaled_intensity_override: float = -1.0) -> int:
	var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
	params["normalized_dimmer"] = dimmer_norm
	params["scaled_intensity"] = scaled_intensity_override
	params["beam_intensity"] = scaled_intensity_override
	params["beam_color"] = beam_color
	params["intensity_max"] = BEAM_INTENSITY_MAX
	var result: int = renderer.update_beam_intensity(light, params)
	if result != BeamRendererBase.INTENSITY_UNRESOLVED:
		light.set_meta("peraviz_beam_last_params", params)
	return result

func _get_last_beam_parameter_write_count() -> int:
	return renderer.get_last_parameter_write_count()

func _apply_emitter_light_state(light: SpotLight3D, photometric: Dictionary, normalized_dimmer: float, controls: Dictionary = {}) -> void:
	var values: PackedFloat32Array = controls.get("render_ready_values", PackedFloat32Array())
	var color := Color(values[4], values[5], values[6]) if values.size() >= 9 else Color.WHITE
	var params := _build_cached_beam_params(light, float(photometric.get("beam_angle", 25.0)), color, normalized_dimmer, values[7] if values.size() >= 9 else 0.0, 0.03, {})
	renderer.update_beam(light, params)
	light.set_meta("peraviz_beam_last_params", params)

func _build_cached_beam_params(_light: SpotLight3D, beam_angle: float, beam_color: Color, normalized_dimmer: float, scaled_intensity: float, lens_radius: float, _defaults: Dictionary) -> Dictionary:
	return {"beam_type": "Wash", "beam_angle": beam_angle, "beam_color": beam_color, "normalized_dimmer": normalized_dimmer, "scaled_intensity": scaled_intensity, "beam_intensity": scaled_intensity, "beam_range": 4.0, "lens_radius": lens_radius, "intensity_visibility_threshold": 0.015, "intensity_max": BEAM_INTENSITY_MAX}
