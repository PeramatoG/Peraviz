extends RefCounted
class_name GoboCompoundTopology

const MIN_RING_POINTS: int = 3

static func build(rings: Array[PackedVector2Array]) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for ring in rings:
		if ring.size() >= MIN_RING_POINTS:
			records.append({"ring": ring, "area": absf(signed_area(ring)), "parent": -1, "depth": 0})
	for index in range(records.size()):
		var parent_index: int = -1
		var parent_area: float = INF
		var point: Vector2 = (records[index]["ring"] as PackedVector2Array)[0]
		for candidate in range(records.size()):
			if candidate == index or float(records[candidate]["area"]) <= float(records[index]["area"]):
				continue
			if Geometry2D.is_point_in_polygon(point, records[candidate]["ring"] as PackedVector2Array) and float(records[candidate]["area"]) < parent_area:
				parent_index = candidate
				parent_area = float(records[candidate]["area"])
		records[index]["parent"] = parent_index
	for index in range(records.size()):
		var depth: int = 0
		var ancestor: int = int(records[index]["parent"])
		while ancestor >= 0:
			depth += 1
			ancestor = int(records[ancestor]["parent"])
		records[index]["depth"] = depth
		records[index]["ring"] = normalize_winding(records[index]["ring"] as PackedVector2Array, depth % 2 == 0)

	var components: Array[Dictionary] = []
	for index in range(records.size()):
		if int(records[index]["depth"]) % 2 != 0:
			continue
		var holes: Array[PackedVector2Array] = []
		for child in range(records.size()):
			if int(records[child]["parent"]) == index and int(records[child]["depth"]) % 2 == 1:
				holes.append(records[child]["ring"] as PackedVector2Array)
		components.append({"outer": records[index]["ring"], "holes": holes, "depth": records[index]["depth"]})
	return components

static func triangulate(component: Dictionary) -> Array[Dictionary]:
	var cap: PackedVector2Array = component.get("outer", PackedVector2Array()) as PackedVector2Array
	for hole in component.get("holes", []) as Array[PackedVector2Array]:
		cap = _bridge_hole(cap, hole)
	var triangles: Array[Dictionary] = []
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(cap)
	for offset in range(0, indices.size(), 3):
		triangles.append({"a": cap[indices[offset]], "b": cap[indices[offset + 1]], "c": cap[indices[offset + 2]]})
	return triangles

static func _bridge_hole(outer: PackedVector2Array, hole: PackedVector2Array) -> PackedVector2Array:
	var hole_index: int = 0
	for index in range(1, hole.size()):
		if hole[index].x > hole[hole_index].x or (is_equal_approx(hole[index].x, hole[hole_index].x) and hole[index].y < hole[hole_index].y):
			hole_index = index
	var outer_index: int = -1
	var best_distance: float = INF
	for index in range(outer.size()):
		var midpoint: Vector2 = (hole[hole_index] + outer[index]) * 0.5
		if not Geometry2D.is_point_in_polygon(midpoint, outer) or _bridge_crosses_ring(hole[hole_index], outer[index], outer, index):
			continue
		var distance: float = hole[hole_index].distance_squared_to(outer[index])
		if distance < best_distance:
			best_distance = distance
			outer_index = index
	if outer_index < 0:
		return outer
	var bridged := PackedVector2Array()
	for index in range(outer_index + 1):
		bridged.append(outer[index])
	for offset in range(hole.size() + 1):
		bridged.append(hole[(hole_index + offset) % hole.size()])
	bridged.append(outer[outer_index])
	for index in range(outer_index + 1, outer.size()):
		bridged.append(outer[index])
	return bridged

static func _bridge_crosses_ring(start: Vector2, end: Vector2, ring: PackedVector2Array, allowed_vertex: int) -> bool:
	for index in range(ring.size()):
		if index == allowed_vertex or (index + 1) % ring.size() == allowed_vertex:
			continue
		if Geometry2D.segment_intersects_segment(start, end, ring[index], ring[(index + 1) % ring.size()]) != null:
			return true
	return false

static func normalize_winding(ring: PackedVector2Array, counter_clockwise: bool) -> PackedVector2Array:
	var normalized := PackedVector2Array(ring)
	if (signed_area(normalized) > 0.0) != counter_clockwise:
		normalized.reverse()
	return normalized

static func signed_area(ring: PackedVector2Array) -> float:
	var area: float = 0.0
	for index in range(ring.size()):
		area += ring[index].cross(ring[(index + 1) % ring.size()])
	return area * 0.5

static func has_self_intersections(ring: PackedVector2Array) -> bool:
	for first in range(ring.size()):
		for second in range(first + 1, ring.size()):
			if abs(first - second) <= 1 or (first == 0 and second == ring.size() - 1):
				continue
			if Geometry2D.segment_intersects_segment(ring[first], ring[(first + 1) % ring.size()], ring[second], ring[(second + 1) % ring.size()]) != null:
				return true
	return false

static func simplify_closed_ring(ring: PackedVector2Array, target_points: int, area_threshold: float = 0.0) -> PackedVector2Array:
	var result := PackedVector2Array(ring)
	var original_sign: bool = signed_area(ring) > 0.0
	var safe_target: int = maxi(target_points, MIN_RING_POINTS)
	while result.size() > MIN_RING_POINTS:
		var candidates: Array[Dictionary] = []
		for index in range(result.size()):
			var previous: Vector2 = result[(index - 1 + result.size()) % result.size()]
			var next: Vector2 = result[(index + 1) % result.size()]
			candidates.append({"index": index, "area": absf((result[index] - previous).cross(next - result[index]))})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["area"]) < float(b["area"]))
		if result.size() <= safe_target and (candidates.is_empty() or float(candidates[0]["area"]) > area_threshold):
			break
		var removed: bool = false
		for candidate in candidates:
			if result.size() <= safe_target and float(candidate["area"]) > area_threshold:
				break
			var candidate_index: int = int(candidate["index"])
			if not _preserves_neighbor_turns(result, candidate_index):
				continue
			var trial := PackedVector2Array(result)
			trial.remove_at(candidate_index)
			if not has_self_intersections(trial) and (signed_area(trial) > 0.0) == original_sign:
				result = trial
				removed = true
				break
		if not removed:
			break
	return result

static func _preserves_neighbor_turns(ring: PackedVector2Array, removed_index: int) -> bool:
	var count: int = ring.size()
	if count <= 4:
		return true
	var previous_previous: Vector2 = ring[(removed_index - 2 + count) % count]
	var previous: Vector2 = ring[(removed_index - 1 + count) % count]
	var removed: Vector2 = ring[removed_index]
	var next: Vector2 = ring[(removed_index + 1) % count]
	var next_next: Vector2 = ring[(removed_index + 2) % count]
	var old_previous_turn: float = (previous - previous_previous).cross(removed - previous)
	var new_previous_turn: float = (previous - previous_previous).cross(next - previous)
	var old_next_turn: float = (next - removed).cross(next_next - next)
	var new_next_turn: float = (next - previous).cross(next_next - next)
	return _same_nonzero_sign(old_previous_turn, new_previous_turn) and _same_nonzero_sign(old_next_turn, new_next_turn)

static func _same_nonzero_sign(reference_turn: float, candidate: float) -> bool:
	if absf(reference_turn) <= 0.0000001:
		return true
	return candidate * reference_turn > 0.0
