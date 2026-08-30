extends RefCounted
class_name NativeGoboResourceRegistry

const GoboPrismMeshBuilderScript = preload("res://scripts/beam_renderers/gobo_prism_mesh_builder.gd")
const GoboRotationPresentationScript = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")

const VECTOR_POLYGONS_META_KEY := "peraviz_gobo_vector_polygons"
const VECTOR_WIDTH_META_KEY := "peraviz_gobo_vector_width"
const VECTOR_HEIGHT_META_KEY := "peraviz_gobo_vector_height"
const ASSET_ID_META_KEY := "peraviz_gobo_asset_id"

var _assets: Dictionary = {}
var _selections_by_target: Dictionary = {}
var _composition_cache: Dictionary = {}
var _moving_layers: Dictionary = {}
var _mesh_builder: RefCounted = GoboPrismMeshBuilderScript.new()
var _vectorizer: Object = null
var _counters: Dictionary = {}

func _init() -> void:
	if ClassDB.class_exists("PeravizGoboVectorizer"):
		_vectorizer = ClassDB.instantiate("PeravizGoboVectorizer")
	reset()

func reset() -> void:
	_assets.clear()
	_selections_by_target.clear()
	_composition_cache.clear()
	_moving_layers.clear()
	_mesh_builder.clear_cache()
	_counters = {"vectorization_requests": 0, "vectorization_cache_hits": 0, "prism_mesh_creations": 0, "prism_cache_hits": 0, "composition_requests": 0, "composition_cache_hits": 0, "composed_png_generations": 0, "composed_vectorizations": 0, "composed_mesh_creations": 0, "composed_topology_reuse": 0, "topology_resource_updates": 0, "parametric_updates": 0, "missing_media_warnings": 0, "deferred_multi_wheel_warnings": 0}

func install_assets(asset_rows: Array) -> void:
	reset()
	for item in asset_rows:
		if item is not Dictionary:
			continue
		var row: Dictionary = (item as Dictionary).duplicate(true)
		var asset_id: int = int(row.get("gobo_asset_id", 0))
		if asset_id <= 0:
			continue
		var path: String = str(row.get("extracted_media_path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			row["texture"] = null
			row["media_valid"] = false
			_counters["missing_media_warnings"] += 1
		else:
			var image := Image.new()
			if image.load(path) == OK:
				row["canonical_image"] = image
				row["texture"] = _texture_for_image(image, asset_id)
			else:
				row["texture"] = null
				row["media_valid"] = false
				_counters["missing_media_warnings"] += 1
		_assets[asset_id] = row

func apply_selection(beam_target_id: int, wheel_id: int, wheel_instance_index: int, slot_index: int, asset_id: int, selection_mode: int, target_record: Dictionary) -> Dictionary:
	var target_states: Dictionary = _selections_by_target.get(beam_target_id, {})
	var previous: Dictionary = target_states.get(wheel_instance_index, {})
	if int(previous.get("slot_index", -1)) == slot_index and int(previous.get("asset_id", -1)) == asset_id and int(previous.get("selection_mode", -1)) == selection_mode:
		return {"applied": true, "unchanged": true, "topology_updates": 0}
	var indexed_angle: float = float(previous.get("indexed_angle_degrees", 0.0))
	target_states[wheel_instance_index] = {"wheel_id": wheel_id, "slot_index": slot_index, "asset_id": asset_id, "selection_mode": selection_mode, "indexed_angle_degrees": indexed_angle}
	_selections_by_target[beam_target_id] = target_states
	var active: Array[Dictionary] = []
	var indexes: Array = target_states.keys()
	indexes.sort()
	for index in indexes:
		var state: Dictionary = target_states[index]
		if int(state.get("asset_id", 0)) > 0:
			active.append(state)
	var resource: Dictionary = {}
	if active.size() == 1:
		resource = _resource_for_asset(int(active[0].get("asset_id", 0)))
	elif active.size() > 1:
		for state in active:
			if int(state.get("selection_mode", 0)) != 0:
				_counters["deferred_multi_wheel_warnings"] += 1
				return {"applied": true, "unsupported_moving_composition": true, "topology_updates": 0}
		resource = _resource_for_composition(active)
	_apply_resource_to_target(target_record, resource)
	if active.size() == 1:
		_apply_rotation_to_target(target_record, float(active[0].get("indexed_angle_degrees", 0.0)))
	_counters["topology_resource_updates"] += 1
	return {"applied": true, "unchanged": false, "cleared": resource.is_empty(), "topology_updates": 1, "asset_id": int(resource.get("asset_id", 0))}

func apply_indexed_rotation(beam_target_id: int, wheel_id: int, wheel_instance_index: int, angle_degrees: float, target_record: Dictionary) -> Dictionary:
	return apply_rotation_state(beam_target_id, wheel_id, wheel_instance_index, 1, 0, angle_degrees, 0.0, 0.0, 0.0, target_record)

func apply_rotation_state(beam_target_id: int, wheel_id: int, wheel_instance_index: int, rotation_mode: int, revision: int, phase_degrees: float, angular_velocity_dps: float, reference_seconds: float, native_now_seconds: float, target_record: Dictionary) -> Dictionary:
	var compensated_phase: float = phase_degrees + angular_velocity_dps * maxf(0.0, native_now_seconds - reference_seconds)
	var key: String = "%d:%d" % [beam_target_id, wheel_instance_index]
	var motion := {"beam_target_id": beam_target_id, "wheel_id": wheel_id, "wheel_instance_index": wheel_instance_index, "mode": rotation_mode, "revision": revision, "phase_degrees": compensated_phase, "angular_velocity_dps": angular_velocity_dps}
	_moving_layers[key] = motion
	var target_states: Dictionary = _selections_by_target.get(beam_target_id, {})
	var state: Dictionary = target_states.get(wheel_instance_index, {"wheel_id": wheel_id, "slot_index": 0, "asset_id": 0, "selection_mode": 0})
	state["indexed_angle_degrees"] = compensated_phase
	target_states[wheel_instance_index] = state
	_selections_by_target[beam_target_id] = target_states
	_counters["parametric_updates"] += 1
	var result: Dictionary = _present_layer_motion(motion, target_record)
	if bool(result.get("unsupported_moving_composition", false)):
		_counters["deferred_multi_wheel_warnings"] += 1
	return result

func advance_motion(delta_seconds: float, target_records: Dictionary) -> void:
	for key in _moving_layers:
		var motion: Dictionary = _moving_layers[key]
		if int(motion.get("mode", 3)) != 2 or is_zero_approx(float(motion.get("angular_velocity_dps", 0.0))):
			continue
		motion["phase_degrees"] = wrapf(float(motion.get("phase_degrees", 0.0)) + float(motion.get("angular_velocity_dps", 0.0)) * delta_seconds, 0.0, 360.0)
		_moving_layers[key] = motion
		var target_states: Dictionary = _selections_by_target.get(int(motion.get("beam_target_id", 0)), {})
		var layer_state: Dictionary = target_states.get(int(motion.get("wheel_instance_index", 0)), {})
		layer_state["indexed_angle_degrees"] = motion["phase_degrees"]
		target_states[int(motion.get("wheel_instance_index", 0))] = layer_state
		_selections_by_target[int(motion.get("beam_target_id", 0))] = target_states
		var target_record: Dictionary = target_records.get(int(motion.get("beam_target_id", 0)), {})
		if not target_record.is_empty():
			_present_layer_motion(motion, target_record)

func _present_layer_motion(motion: Dictionary, target_record: Dictionary) -> Dictionary:
	var beam_target_id: int = int(motion.get("beam_target_id", 0))
	var wheel_instance_index: int = int(motion.get("wheel_instance_index", 0))
	var target_states: Dictionary = _selections_by_target.get(beam_target_id, {})
	var state: Dictionary = target_states.get(wheel_instance_index, {})
	var visible_count: int = 0
	for item in target_states.values():
		if int(item.get("asset_id", 0)) > 0: visible_count += 1
	if int(state.get("asset_id", 0)) <= 0:
		return {"applied": true, "open_slot": true, "topology_updates": 0}
	if visible_count > 1:
		return {"applied": true, "unsupported_moving_composition": true, "topology_updates": 0}
	_apply_rotation_to_target(target_record, float(motion.get("phase_degrees", 0.0)))
	return {"applied": true, "rotation_applied": true, "topology_updates": 0}

func counters() -> Dictionary:
	var result: Dictionary = _counters.duplicate(true)
	result.merge(_mesh_builder.get_counters(), true)
	return result

func _resource_for_asset(asset_id: int) -> Dictionary:
	var asset: Dictionary = _assets.get(asset_id, {})
	var texture: Texture2D = asset.get("texture", null) as Texture2D
	if texture == null:
		return {}
	if asset.has("mesh"):
		_counters["vectorization_cache_hits"] += 1
		_counters["prism_cache_hits"] += 1
		return asset
	_counters["vectorization_requests"] += 1
	asset["mesh"] = _mesh_builder.build_normalized_beam_mesh(texture)
	_counters["prism_mesh_creations"] += 1
	_assets[asset_id] = asset
	return asset

func _resource_for_composition(states: Array[Dictionary]) -> Dictionary:
	_counters["composition_requests"] += 1
	var parts := PackedStringArray(["v1", "quality:280"])
	for state in states:
		parts.append("%d:%d:0:0" % [int(state.get("asset_id", 0)), int(state.get("slot_index", 0))])
	var key: String = "|".join(parts)
	if _composition_cache.has(key):
		_counters["composition_cache_hits"] += 1
		_counters["composed_topology_reuse"] += 1
		return _composition_cache[key]
	var images: Array[Image] = []
	for state in states:
		var asset: Dictionary = _assets.get(int(state.get("asset_id", 0)), {})
		var image: Image = asset.get("canonical_image", null) as Image
		if image == null:
			return {}
		images.append(image)
	var composed: Image = _multiply_binary_masks(images)
	if composed == null:
		return {}
	_counters["composed_png_generations"] += 1
	var composed_id: int = key.hash() & 0x7fffffff
	var texture: ImageTexture = _texture_for_image(composed, composed_id)
	_counters["composed_vectorizations"] += 1
	var resource := {"asset_id": composed_id, "composition_key": key, "canonical_image": composed, "texture": texture, "mesh": _mesh_builder.build_normalized_beam_mesh(texture)}
	_counters["composed_mesh_creations"] += 1
	_composition_cache[key] = resource
	return resource

func _multiply_binary_masks(images: Array[Image]) -> Image:
	if images.is_empty():
		return null
	var width: int = images[0].get_width()
	var height: int = images[0].get_height()
	var output := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			var open_value: float = 1.0
			for source in images:
				var sx: int = clampi(int(float(x) * source.get_width() / width), 0, source.get_width() - 1)
				var sy: int = clampi(int(float(y) * source.get_height() / height), 0, source.get_height() - 1)
				var pixel: Color = source.get_pixel(sx, sy)
				open_value *= 1.0 if pixel.a >= 0.5 and pixel.get_luminance() >= 0.5 else 0.0
			output.set_pixel(x, y, Color(open_value, open_value, open_value, 1.0))
	return output

func _texture_for_image(image: Image, asset_id: int) -> ImageTexture:
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta(ASSET_ID_META_KEY, asset_id)
	return texture

func _apply_resource_to_target(target_record: Dictionary, resource: Dictionary) -> void:
	var texture: Texture2D = resource.get("texture", null) as Texture2D
	var mesh: ArrayMesh = resource.get("mesh", null) as ArrayMesh
	for light_item in target_record.get("emitter_anchors", []):
		var light: SpotLight3D = light_item as SpotLight3D
		if light != null:
			light.set_meta("peraviz_gobo_texture", texture)
	for beam_item in target_record.get("beam_instances", []):
		var beam: MeshInstance3D = beam_item as MeshInstance3D
		if beam != null:
			beam.mesh = mesh

func _apply_rotation_to_target(target_record: Dictionary, physical_angle_degrees: float) -> void:
	var backend: String = _presentation_backend(target_record)
	for beam_item in target_record.get("beam_instances", []):
		GoboRotationPresentationScript.apply_physical_angle(beam_item as MeshInstance3D, physical_angle_degrees, backend)

func _presentation_backend(target_record: Dictionary) -> String:
	for light_item in target_record.get("emitter_anchors", []):
		var light: SpotLight3D = light_item as SpotLight3D
		if light != null and str(light.get_meta("peraviz_last_beam_renderer_mode", "")) == "volumetric_cone":
			return GoboRotationPresentationScript.SHADER_BACKEND
	return "vector_prism"
