extends RefCounted
class_name GoboPrismMeshBuilder

const VECTORIZATION_MAX_SIZE: int = 512
const VECTORIZATION_ALPHA_THRESHOLD: float = 0.5
const VECTORIZATION_EPSILON: float = 0.45
const MAX_TOTAL_VECTOR_POINTS: int = 768
const MIN_POLYGON_AREA: float = 0.00004
const FALLBACK_SEGMENTS: int = 36
const BINARY_LUMA_THRESHOLD: float = 0.5
const OUTER_BORDER_PIXELS: int = 1
const APERTURE_BORDER_RATIO: float = 0.985
const GOBO_VECTOR_POLYGONS_META_KEY: String = "peraviz_gobo_vector_polygons"
const GOBO_VECTOR_WIDTH_META_KEY: String = "peraviz_gobo_vector_width"
const GOBO_VECTOR_HEIGHT_META_KEY: String = "peraviz_gobo_vector_height"
const DEBUG_GOBO_VECTORIZATION: bool = false
const CIRCULAR_STDDEV_RATIO_THRESHOLD: float = 0.045
const CIRCULAR_MAX_DEVIATION_RATIO_THRESHOLD: float = 0.14
const CIRCULAR_MIN_POINTS: int = 16

const GoboPolygonCleanupScript = preload("res://scripts/beam_renderers/gobo_polygon_cleanup.gd")
const GoboCompoundTopologyScript = preload("res://scripts/beam_renderers/gobo_compound_topology.gd")

var _shape_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _normalized_polygon_cache: Dictionary = {}
var _counters: Dictionary = {"normalized_topology_creations": 0, "normalized_topology_cache_hits": 0}

func clear_cache() -> void:
	_shape_cache.clear()
	_mesh_cache.clear()
	_normalized_polygon_cache.clear()
	_counters = {"normalized_topology_creations": 0, "normalized_topology_cache_hits": 0}

func get_counters() -> Dictionary:
	return _counters.duplicate(true)

func build_normalized_beam_mesh(gobo_texture: Texture2D, apply_edge_mask_correction: bool = true) -> ArrayMesh:
	var topology_key: String = _shape_cache_key(gobo_texture, apply_edge_mask_correction)
	if _mesh_cache.has(topology_key):
		_counters["normalized_topology_cache_hits"] += 1
		return _mesh_cache[topology_key] as ArrayMesh
	var polygons: Array[PackedVector2Array] = _get_or_build_shape_base(gobo_texture, apply_edge_mask_correction)
	if polygons.is_empty():
		polygons = [_build_fallback_circle()]
	var mesh: ArrayMesh = _build_extruded_mesh(GoboCompoundTopologyScript.build(polygons), 1.0, 1.0, 1.0)
	_mesh_cache[topology_key] = mesh
	_counters["normalized_topology_creations"] += 1
	return mesh

func build_aperture_beam_mesh(aperture_profile: Dictionary, beam_height: float) -> ArrayMesh:
	var shape: String = str(aperture_profile.get("shape", "circle")).to_lower()
	if shape == "no_projected_beam":
		return null
	var ratio: float = max(float(aperture_profile.get("rectangle_ratio", 1.0)), 0.01)
	var key: String = "__aperture_%s_%.3f_%.4f" % [shape, ratio, beam_height]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as ArrayMesh
	var polygons: Array[PackedVector2Array] = []
	if shape == "rectangle":
		polygons = [_build_normalized_rectangle(ratio)]
	else:
		polygons = [_build_fallback_circle()]
	var mesh: ArrayMesh = _build_extruded_mesh(GoboCompoundTopologyScript.build(polygons), 1.0, 1.0, max(beam_height, 0.001))
	_mesh_cache[key] = mesh
	return mesh

func _build_normalized_rectangle(rectangle_ratio: float) -> PackedVector2Array:
	var safe_ratio: float = max(rectangle_ratio, 0.01)
	var half_width: float = sqrt(safe_ratio)
	var half_height: float = 1.0 / max(half_width, 0.01)
	return PackedVector2Array([Vector2(-half_width, -half_height), Vector2(half_width, -half_height), Vector2(half_width, half_height), Vector2(-half_width, half_height)])

func _get_or_build_shape_base(gobo_texture: Texture2D, apply_edge_mask_correction: bool) -> Array[PackedVector2Array]:
	var shape_key: String = _shape_cache_key(gobo_texture, apply_edge_mask_correction)
	if _shape_cache.has(shape_key):
		return (_shape_cache[shape_key] as Array).duplicate(true) as Array[PackedVector2Array]
	var polygons: Array[PackedVector2Array] = _vectorize_gobo(gobo_texture, 1.0, apply_edge_mask_correction)
	_shape_cache[shape_key] = polygons.duplicate(true)
	return polygons

func _shape_cache_key(gobo_texture: Texture2D, apply_edge_mask_correction: bool) -> String:
	if gobo_texture == null:
		return "__fallback_shape_%s" % [str(apply_edge_mask_correction)]
	var content_id: int = int(gobo_texture.get_meta("peraviz_gobo_asset_id", gobo_texture.get_rid().get_id()))
	return "__shape_v2_%d_%s_%d_%.2f" % [content_id, str(apply_edge_mask_correction), MAX_TOTAL_VECTOR_POINTS, VECTORIZATION_EPSILON]

func _vectorize_gobo(gobo_texture: Texture2D, gobo_scale: float, apply_edge_mask_correction: bool = true) -> Array[PackedVector2Array]:
	if gobo_texture == null:
		return []

	var native_polygons: Array[PackedVector2Array] = _vectorize_from_texture_metadata(gobo_texture)
	if not native_polygons.is_empty():
		var cleaned_native: Array[PackedVector2Array] = _finalize_vector_polygons(native_polygons, gobo_scale)
		if not cleaned_native.is_empty():
			if DEBUG_GOBO_VECTORIZATION:
				print("[PeravizGoboVectorization] source=metadata polygons=", cleaned_native.size(), " points=", _count_polygon_points(cleaned_native))
			return cleaned_native

	var normalized_polygons: Array[PackedVector2Array] = _get_or_build_normalized_raster_polygons(gobo_texture, apply_edge_mask_correction)
	if normalized_polygons.is_empty():
		return []
	return _finalize_vector_polygons(normalized_polygons, gobo_scale)


func _vectorize_from_texture_metadata(gobo_texture: Texture2D) -> Array[PackedVector2Array]:
	if gobo_texture == null or not gobo_texture.has_meta(GOBO_VECTOR_POLYGONS_META_KEY):
		return []
	var raw_polygons: Array = gobo_texture.get_meta(GOBO_VECTOR_POLYGONS_META_KEY, [])
	var source_width: int = int(gobo_texture.get_meta(GOBO_VECTOR_WIDTH_META_KEY, 0))
	var source_height: int = int(gobo_texture.get_meta(GOBO_VECTOR_HEIGHT_META_KEY, 0))
	if source_width <= 0 or source_height <= 0 or raw_polygons.is_empty():
		return []

	var inv_width: float = 1.0 / max(float(source_width), 1.0)
	var inv_height: float = 1.0 / max(float(source_height), 1.0)
	var normalized: Array[PackedVector2Array] = []
	for polygon_variant in raw_polygons:
		if polygon_variant is not PackedVector2Array:
			continue
		var polygon: PackedVector2Array = polygon_variant as PackedVector2Array
		if polygon.size() < 3:
			continue
		var normalized_polygon: PackedVector2Array = _normalize_polygon_to_local_space(polygon, inv_width, inv_height)
		if normalized_polygon.size() >= 3:
			normalized.append(normalized_polygon)
	return normalized

func _get_or_build_normalized_raster_polygons(gobo_texture: Texture2D, apply_edge_mask_correction: bool) -> Array[PackedVector2Array]:
	var normalization_key: String = _normalized_polygon_cache_key(gobo_texture, apply_edge_mask_correction)
	if _normalized_polygon_cache.has(normalization_key):
		return (_normalized_polygon_cache[normalization_key] as Array).duplicate(true) as Array[PackedVector2Array]
	var normalized_polygons: Array[PackedVector2Array] = _vectorize_texture_to_normalized_polygons(gobo_texture, apply_edge_mask_correction)
	_normalized_polygon_cache[normalization_key] = normalized_polygons.duplicate(true)
	return normalized_polygons

func _normalized_polygon_cache_key(gobo_texture: Texture2D, apply_edge_mask_correction: bool) -> String:
	if gobo_texture == null:
		return "__normalized_fallback_%s_%.3f" % [str(apply_edge_mask_correction), VECTORIZATION_ALPHA_THRESHOLD]
	return "__normalized_v2_%d_%s_%.3f_%d_%.2f" % [gobo_texture.get_rid().get_id(), str(apply_edge_mask_correction), VECTORIZATION_ALPHA_THRESHOLD, MAX_TOTAL_VECTOR_POINTS, VECTORIZATION_EPSILON]

func _vectorize_texture_to_normalized_polygons(gobo_texture: Texture2D, apply_edge_mask_correction: bool) -> Array[PackedVector2Array]:
	var image: Image = gobo_texture.get_image()
	if image == null:
		return []
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var longest_size: int = max(image.get_width(), image.get_height())
	if longest_size > VECTORIZATION_MAX_SIZE:
		var target_width: int = max(8, int(round(float(image.get_width()) * float(VECTORIZATION_MAX_SIZE) / float(longest_size))))
		var target_height: int = max(8, int(round(float(image.get_height()) * float(VECTORIZATION_MAX_SIZE) / float(longest_size))))
		image.resize(target_width, target_height, Image.INTERPOLATE_BILINEAR)
	if apply_edge_mask_correction:
		_prepare_binary_mask_image(image)
	if DEBUG_GOBO_VECTORIZATION:
		print("[PeravizGoboVectorization] source=raster texture=", gobo_texture.get_rid().get_id())

	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, VECTORIZATION_ALPHA_THRESHOLD)
	var all_polygons: Array = bitmap.opaque_to_polygons(Rect2i(0, 0, image.get_width(), image.get_height()), VECTORIZATION_EPSILON)
	if all_polygons.is_empty():
		return []
	var inv_width: float = 1.0 / max(float(image.get_width()), 1.0)
	var inv_height: float = 1.0 / max(float(image.get_height()), 1.0)
	var normalized: Array[PackedVector2Array] = []
	for polygon_variant in all_polygons:
		if polygon_variant is not PackedVector2Array:
			continue
		var polygon: PackedVector2Array = polygon_variant as PackedVector2Array
		if polygon.size() < 3:
			continue
		var normalized_polygon: PackedVector2Array = _normalize_polygon_to_local_space(polygon, inv_width, inv_height)
		if normalized_polygon.size() >= 3:
			normalized.append(normalized_polygon)
	return normalized

func _normalize_polygon_to_local_space(polygon: PackedVector2Array, inv_width: float, inv_height: float) -> PackedVector2Array:
	var center := Vector2(0.5, 0.5)
	var normalized_polygon := PackedVector2Array()
	for point in polygon:
		var uv := Vector2(point.x * inv_width, point.y * inv_height)
		var local := (uv - center) * 2.0
		# Preserve source artwork orientation; renderer alignment owns any optical transform.
		normalized_polygon.append(local)
	return normalized_polygon

func _finalize_vector_polygons(normalized_polygons: Array[PackedVector2Array], gobo_scale: float) -> Array[PackedVector2Array]:
	if normalized_polygons.is_empty():
		return []
	var safe_scale: float = max(gobo_scale, 0.05)
	var scaled_polygons: Array[PackedVector2Array] = []
	for polygon in normalized_polygons:
		var scaled_polygon := PackedVector2Array()
		for point in polygon:
			scaled_polygon.append(point / safe_scale)
		scaled_polygons.append(scaled_polygon)
	var cleaned_output: Array[PackedVector2Array] = GoboPolygonCleanupScript.sanitize_polygons(scaled_polygons, MIN_POLYGON_AREA)
	if cleaned_output.is_empty():
		return []
	var regularized_output: Array[PackedVector2Array] = _regularize_near_circular_polygons(cleaned_output)
	var reduced_output: Array[PackedVector2Array] = _reduce_polygon_point_count(regularized_output, MAX_TOTAL_VECTOR_POINTS)
	return _sort_polygons_by_area_descending(reduced_output)

func _sort_polygons_by_area_descending(polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if polygons.is_empty():
		return []
	var sorted: Array[Dictionary] = []
	for polygon in polygons:
		var area: float = abs(_signed_polygon_area(polygon))
		if area < MIN_POLYGON_AREA:
			continue
		sorted.append({"polygon": polygon, "area": area})
	if sorted.is_empty():
		return []
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("area", 0.0)) > float(b.get("area", 0.0))
	)
	var output: Array[PackedVector2Array] = []
	for item in sorted:
		output.append(item.get("polygon", PackedVector2Array()) as PackedVector2Array)
	return output

func _regularize_near_circular_polygons(polygons: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	for polygon in polygons:
		if _is_near_circular_polygon(polygon):
			output.append(_fit_polygon_to_circle(polygon))
		else:
			output.append(polygon)
	return output

func _is_near_circular_polygon(polygon: PackedVector2Array) -> bool:
	if polygon.size() < CIRCULAR_MIN_POINTS:
		return false
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	centroid /= float(polygon.size())

	var radii: PackedFloat32Array = PackedFloat32Array()
	radii.resize(polygon.size())
	var mean_radius: float = 0.0
	for i in range(polygon.size()):
		var radius: float = polygon[i].distance_to(centroid)
		radii[i] = radius
		mean_radius += radius
	mean_radius /= float(polygon.size())
	if mean_radius <= 0.0001:
		return false

	var variance: float = 0.0
	var max_deviation: float = 0.0
	for radius in radii:
		var deviation: float = abs(radius - mean_radius)
		variance += deviation * deviation
		max_deviation = max(max_deviation, deviation)
	variance /= float(polygon.size())
	var stddev: float = sqrt(max(variance, 0.0))
	var stddev_ratio: float = stddev / mean_radius
	var max_deviation_ratio: float = max_deviation / mean_radius
	return stddev_ratio <= CIRCULAR_STDDEV_RATIO_THRESHOLD and max_deviation_ratio <= CIRCULAR_MAX_DEVIATION_RATIO_THRESHOLD

func _fit_polygon_to_circle(polygon: PackedVector2Array) -> PackedVector2Array:
	if polygon.size() < 3:
		return polygon
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	centroid /= float(polygon.size())

	var mean_radius: float = 0.0
	for point in polygon:
		mean_radius += point.distance_to(centroid)
	mean_radius /= float(polygon.size())
	if mean_radius <= 0.0001:
		return polygon

	var fitted := PackedVector2Array()
	for point in polygon:
		var direction: Vector2 = point - centroid
		var length: float = direction.length()
		if length <= 0.000001:
			fitted.append(point)
			continue
		fitted.append(centroid + ((direction / length) * mean_radius))
	return fitted

func _reduce_polygon_point_count(polygons: Array[PackedVector2Array], max_points: int) -> Array[PackedVector2Array]:
	if polygons.is_empty():
		return []
	if _count_polygon_points(polygons) <= max_points:
		return polygons

	var minimum_budget: int = polygons.size() * 3
	var available_budget: int = maxi(max_points, minimum_budget)
	var source_points: int = _count_polygon_points(polygons)
	var reduced: Array[PackedVector2Array] = []
	var assigned: int = 0
	for index in range(polygons.size()):
		var remaining_rings: int = polygons.size() - index - 1
		var proportional: int = maxi(3, int(round(float(polygons[index].size()) * float(available_budget) / float(source_points))))
		var target: int = mini(polygons[index].size(), mini(proportional, available_budget - assigned - remaining_rings * 3))
		reduced.append(GoboCompoundTopologyScript.simplify_closed_ring(polygons[index], target))
		assigned += reduced[-1].size()
	return reduced

func _count_polygon_points(polygons: Array[PackedVector2Array]) -> int:
	var total: int = 0
	for polygon in polygons:
		total += polygon.size()
	return total

func _prepare_binary_mask_image(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return
	var center := Vector2((float(width) - 1.0) * 0.5, (float(height) - 1.0) * 0.5)
	var aperture_radius: float = (min(float(width), float(height)) * 0.5) * APERTURE_BORDER_RATIO
	for y in range(height):
		for x in range(width):
			if x < OUTER_BORDER_PIXELS or y < OUTER_BORDER_PIXELS or x >= (width - OUTER_BORDER_PIXELS) or y >= (height - OUTER_BORDER_PIXELS):
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var pos := Vector2(float(x), float(y))
			if pos.distance_to(center) >= aperture_radius:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var sample: Color = image.get_pixel(x, y)
			var luma: float = (sample.r * 0.299) + (sample.g * 0.587) + (sample.b * 0.114)
			var binary: float = 1.0 if (luma * sample.a) >= BINARY_LUMA_THRESHOLD else 0.0
			image.set_pixel(x, y, Color(binary, binary, binary, binary))

func _signed_polygon_area(polygon: PackedVector2Array) -> float:
	var count: int = polygon.size()
	if count < 3:
		return 0.0
	var area: float = 0.0
	for i in range(count):
		var current: Vector2 = polygon[i]
		var next: Vector2 = polygon[(i + 1) % count]
		area += (current.x * next.y) - (next.x * current.y)
	return 0.5 * area

func _build_fallback_circle() -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for i in range(FALLBACK_SEGMENTS):
		var angle: float = TAU * float(i) / float(FALLBACK_SEGMENTS)
		polygon.append(Vector2(cos(angle), sin(angle)))
	return polygon

func _build_extruded_mesh(components: Array[Dictionary], near_radius: float, far_radius: float, beam_height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_height: float = beam_height * 0.5
	for component in components:
		_add_caps(st, component, near_radius, far_radius, half_height)
		_add_sides(st, component.get("outer", PackedVector2Array()) as PackedVector2Array, near_radius, far_radius, half_height)
		for hole in component.get("holes", []) as Array[PackedVector2Array]:
			_add_sides(st, hole, near_radius, far_radius, half_height)
	st.generate_normals()
	return st.commit()

func _add_caps(st: SurfaceTool, component: Dictionary, near_radius: float, far_radius: float, half_height: float) -> void:
	st.set_smooth_group(-1)
	for triangle in GoboCompoundTopologyScript.triangulate(component):
		var a: Vector2 = triangle["a"]
		var b: Vector2 = triangle["b"]
		var c: Vector2 = triangle["c"]
		st.add_vertex(Vector3(a.x * near_radius, half_height, a.y * near_radius))
		st.add_vertex(Vector3(b.x * near_radius, half_height, b.y * near_radius))
		st.add_vertex(Vector3(c.x * near_radius, half_height, c.y * near_radius))
		st.add_vertex(Vector3(c.x * far_radius, -half_height, c.y * far_radius))
		st.add_vertex(Vector3(b.x * far_radius, -half_height, b.y * far_radius))
		st.add_vertex(Vector3(a.x * far_radius, -half_height, a.y * far_radius))

func _add_sides(st: SurfaceTool, polygon: PackedVector2Array, near_radius: float, far_radius: float, half_height: float) -> void:
	st.set_smooth_group(0)
	var point_count: int = polygon.size()
	for i in range(point_count):
		var current: Vector2 = polygon[i]
		var next: Vector2 = polygon[(i + 1) % point_count]
		var near_current := Vector3(current.x * near_radius, half_height, current.y * near_radius)
		var near_next := Vector3(next.x * near_radius, half_height, next.y * near_radius)
		var far_current := Vector3(current.x * far_radius, -half_height, current.y * far_radius)
		var far_next := Vector3(next.x * far_radius, -half_height, next.y * far_radius)
		st.add_vertex(near_current)
		st.add_vertex(near_next)
		st.add_vertex(far_next)
		st.add_vertex(near_current)
		st.add_vertex(far_next)
		st.add_vertex(far_current)
	st.set_smooth_group(-1)
