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

func texture_for(profile: RefCounted, source: Texture2D) -> Texture2D:
	var source_id: int = source.get_instance_id() if source != null else 0
	var key := "%d|%s" % [source_id, str(profile.signature)]
	if _textures.has(key): return _textures[key]
	var mask: Image = source.get_image() if source != null else null
	var width: int = maxi(SIZE, mask.get_width()) if mask != null else SIZE
	var height: int = maxi(SIZE, mask.get_height()) if mask != null else SIZE
	if mask != null:
		if mask.is_compressed(): mask.decompress()
		mask.convert(Image.FORMAT_RGBA8)
		mask.resize(width, height, Image.INTERPOLATE_BILINEAR)
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(width, height) * 2.0 - Vector2.ONE
			var intensity: float = profile.sample_support(point)
			var transmission := Color.WHITE if mask == null else mask.get_pixel(x, y).srgb_to_linear()
			image.set_pixel(x, y, Color(transmission.r * intensity * transmission.a, transmission.g * intensity * transmission.a, transmission.b * intensity * transmission.a, 1.0).linear_to_srgb())
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	if _textures.size() >= MAX_ENTRIES: _textures.clear()
	_textures[key] = texture
	creations += 1
	return texture
