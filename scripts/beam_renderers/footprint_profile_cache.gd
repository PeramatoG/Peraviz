extends RefCounted

# Renderer-owned, bounded cache. Never called from intensity/color/roll playback.
# Source gobo assets remain untouched: only the surface projector is composed.
const SIZE: int = 128
const MAX_ENTRIES: int = 128
var _textures: Dictionary = {}
var creations: int = 0

func clear() -> void:
	_textures.clear()
	creations = 0

func texture_for(profile: RefCounted, source: Texture2D, softness: float = 0.04) -> Texture2D:
	var source_id: int = source.get_instance_id() if source != null else 0
	softness = clampf(softness, 0.0, 0.25)
	var key := "%d|%s|%.6f|%.6f" % [source_id, str(profile.signature), profile.feather_start, softness]
	if _textures.has(key): return _textures[key]
	var mask: Image = source.get_image() if source != null else null
	var width: int = maxi(SIZE, mask.get_width()) if mask != null else SIZE
	var height: int = maxi(SIZE, mask.get_height()) if mask != null else SIZE
	if mask != null:
		mask = mask.duplicate()
		if mask.is_compressed(): mask.decompress()
		mask.convert(Image.FORMAT_RGBA8)
		mask.resize(width, height, Image.INTERPOLATE_BILINEAR)
	var linear: Image = null
	if mask != null:
		linear = Image.create(width, height, false, Image.FORMAT_RGBAF)
		for y in range(height):
			for x in range(width):
				var value := mask.get_pixel(x, y).srgb_to_linear()
				linear.set_pixel(x, y, Color(value.r * value.a, value.g * value.a, value.b * value.a, 1.0))
		var radius := clampi(int(ceil(mini(width, height) * softness * 0.15)), 0, 16)
		if radius > 0: linear = soften(linear, radius)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(width, height) * 2.0 - Vector2.ONE
			var intensity: float = profile.sample_support(point)
			var transmission := Color.WHITE if linear == null else linear.get_pixel(x, y)
			image.set_pixel(x, y, Color(transmission.r * intensity * transmission.a, transmission.g * intensity * transmission.a, transmission.b * intensity * transmission.a, 1.0).linear_to_srgb())
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	if _textures.size() >= MAX_ENTRIES: _textures.clear()
	_textures[key] = texture
	creations += 1
	return texture

# Two running-sum box passes: O(pixels), performed only at cache creation.
static func soften(source: Image, radius: int) -> Image:
	var width := source.get_width()
	var height := source.get_height()
	var current := source
	for horizontal in [true, false]:
		var output := Image.create(width, height, false, Image.FORMAT_RGBAF)
		var lines: int = height if horizontal else width
		var length: int = width if horizontal else height
		for line in range(lines):
			var sum := Color(0, 0, 0, 0)
			for tap in range(-radius, radius + 1):
				var pos := clampi(tap, 0, length - 1)
				sum += current.get_pixel(pos, line) if horizontal else current.get_pixel(line, pos)
			for index in range(length):
				var value := sum / float(radius * 2 + 1)
				if horizontal: output.set_pixel(index, line, value)
				else: output.set_pixel(line, index, value)
				var remove := clampi(index - radius, 0, length - 1)
				var add := clampi(index + radius + 1, 0, length - 1)
				sum += (current.get_pixel(add, line) - current.get_pixel(remove, line)) if horizontal else (current.get_pixel(line, add) - current.get_pixel(line, remove))
		current = output
	return current
