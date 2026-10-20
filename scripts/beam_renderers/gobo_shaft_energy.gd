extends RefCounted

# Setup-only conservative line-crossing table. A ray through a homothetic prism
# maps to a straight line in its artwork plane. Each entry bounds contour crossings
# over a complete direction/offset cell, including vertex and grazing cases.
const DIRECTIONS: int = 128
const OFFSETS: int = 256
const EXTENT: float = 1.5

static func build(rings: Array[PackedVector2Array], source: Texture2D) -> Texture2D:
	var image := coverage_bounds(rings)
	# One-cell minimum dilation keeps bilinear samples conservative, while removing
	# quantization bands from the lookup. At the PI seam the signed offset flips.
	var smooth := Image.create(OFFSETS, DIRECTIONS, false, Image.FORMAT_RF)
	for row in range(DIRECTIONS):
		for column in range(OFFSETS):
			var gain := 1.0
			for dy in range(-1, 2):
				var wrapped := posmod(row + dy, DIRECTIONS)
				for dx in range(-1, 2):
					var x := clampi(column + dx, 0, OFFSETS - 1)
					if row + dy < 0 or row + dy >= DIRECTIONS: x = OFFSETS - 1 - x
					gain = minf(gain, image.get_pixel(x, wrapped).r)
			smooth.set_pixel(column, row, Color(gain, 0, 0))
	var chords := chord_lengths(rings)
	for row in range(DIRECTIONS):
		for column in range(OFFSETS):
			smooth.set_pixel(column, row, Color(smooth.get_pixel(column, row).r * chords.get_pixel(column, row).r, 0, 0))
	var texture := ImageTexture.create_from_image(smooth)
	var measured := transmission(source)
	var topology = preload("res://scripts/beam_renderers/gobo_compound_topology.gd")
	var area := 0.0
	for component in topology.build(rings):
		area += absf(topology.signed_area(component["outer"]))
		for hole in component["holes"]: area -= absf(topology.signed_area(hole))
	# Chord integration already accounts for binary open area. Only residual
	# grayscale/alpha transmission is applied again, avoiding double attenuation.
	texture.set_meta("transmission", clampf(measured / maxf(area / PI, 0.000001), 0.0, 1.0))
	texture.set_meta("open_area_transmission", measured)
	return texture

static func transmission(source: Texture2D) -> float:
	if source == null: return 1.0
	var image := source.get_image()
	if image == null: return 0.0
	image = image.duplicate()
	if image.is_compressed(): image.decompress()
	var total := 0.0
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(image.get_width(), image.get_height()) * 2.0 - Vector2.ONE
			if point.length_squared() > 1.0: continue
			var sample := image.get_pixel(x, y).srgb_to_linear()
			total += clampf((sample.r * 0.299 + sample.g * 0.587 + sample.b * 0.114) * sample.a, 0.0, 1.0)
			count += 1
	return clampf(total / maxf(count, 1), 0.0, 1.0)

# Scan conversion distributes each edge only over the offset bins it crosses.
# Sorting intersection pairs integrates actual transmitted chord length, rather
# than assigning every contour the same brightness regardless of its thickness.
static func chord_lengths(rings: Array[PackedVector2Array]) -> Image:
	var result := Image.create(OFFSETS, DIRECTIONS, false, Image.FORMAT_RF)
	var step := 2.0 * EXTENT / OFFSETS
	for row in range(DIRECTIONS):
		var angle := PI * (row + 0.5) / DIRECTIONS
		var normal := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-normal.y, normal.x)
		var intersections: Array[Array] = []
		for column in range(OFFSETS): intersections.append([])
		for ring in rings:
			for i in range(ring.size()):
				var a: Vector2 = ring[i]
				var b: Vector2 = ring[(i+1)%ring.size()]
				var an := normal.dot(a)
				var bn := normal.dot(b)
				if absf(bn-an) < 0.000001: continue
				var first := clampi(int(ceil((minf(an,bn)+EXTENT)/step-0.5)),0,OFFSETS-1)
				var last := clampi(int(ceil((maxf(an,bn)+EXTENT)/step-0.5))-1,0,OFFSETS-1)
				for column in range(first,last+1):
					var offset := (column+0.5)*step-EXTENT
					var t := (offset-an)/(bn-an)
					if t >= 0.0 and t < 1.0: intersections[column].append(tangent.dot(a.lerp(b,t)))
		for column in range(OFFSETS):
			var offset := (column+0.5)*step-EXTENT
			if absf(offset) >= 1.0: continue
			var limit := sqrt(maxf(1.0-offset*offset,0.0))
			var values: Array = intersections[column]
			values.sort()
			var length := 0.0
			for i in range(0,values.size()-1,2): length += maxf(minf(values[i+1],limit)-maxf(values[i],-limit),0.0)
			result.set_pixel(column,row,Color(clampf(length*0.5,0.0,1.0),0,0))
	return result

# Consecutive edges with the same projected direction are one monotone crossing
# chain, not separate contributors. This removes tessellation-dependent bounds.
# Subdivide direction cells at edge-perpendicular events so no chain configuration
# inside a cell can be missed, then conservatively bound moving chain endpoints.
static func coverage_bounds(rings: Array[PackedVector2Array]) -> Image:
	var events: Array[Array] = []
	for row in range(DIRECTIONS): events.append([PI*(row+0.5)/DIRECTIONS])
	for ring in rings:
		for i in range(ring.size()):
			var edge := ring[(i+1)%ring.size()] - ring[i]
			var angle := fposmod(atan2(-edge.x,edge.y),PI)
			var row := clampi(int(angle/PI*DIRECTIONS),0,DIRECTIONS-1)
			events[row].append(angle-0.000001)
			events[row].append(angle+0.000001)
	var result := Image.create(OFFSETS,DIRECTIONS,false,Image.FORMAT_RF)
	for row in range(DIRECTIONS):
		var maximum := PackedInt32Array()
		maximum.resize(OFFSETS)
		for angle: float in events[row]:
			var normal := Vector2(cos(angle),sin(angle))
			var differences := PackedInt32Array()
			differences.resize(OFFSETS+1)
			for ring in rings:
				var extrema := PackedFloat64Array()
				var margin := 0.0
				for i in range(ring.size()):
					var current := normal.dot(ring[i])
					var previous := normal.dot(ring[posmod(i-1,ring.size())])
					var next := normal.dot(ring[(i+1)%ring.size()])
					if (current-previous)*(next-current) < 0.0: extrema.append(current)
					margin = maxf(margin,ring[i].length()*PI/DIRECTIONS)
				for i in range(extrema.size()):
					var low := minf(extrema[i],extrema[(i+1)%extrema.size()])-margin
					var high := maxf(extrema[i],extrema[(i+1)%extrema.size()])+margin
					var first := clampi(int(floor((low/EXTENT+1.0)*0.5*OFFSETS)),0,OFFSETS-1)
					var last := clampi(int(floor((high/EXTENT+1.0)*0.5*OFFSETS)),0,OFFSETS-1)
					differences[first] += 1
					differences[last+1] -= 1
			var count := 0
			for column in range(OFFSETS):
				count += differences[column]
				maximum[column] = maxi(maximum[column],count)
		for column in range(OFFSETS): result.set_pixel(column,row,Color(1.0/maxf(ceil(maximum[column]*0.5),1),0,0))
	return result
