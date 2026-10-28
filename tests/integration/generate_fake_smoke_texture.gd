extends SceneTree

# Offline source-asset generator; never invoked by scene import or playback.
func _initialize() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 17041
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.085
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var images: Array[Image] = noise.get_seamless_image_3d(32,32,32,false,0.25,true)
	var data := PackedByteArray()
	for image in images: data.append_array(image.get_data())
	var atlas := Image.create_from_data(32,1024,false,Image.FORMAT_L8,data)
	var error := ResourceSaver.save(atlas,"res://resources/fake_smoke_density.res")
	print("SMOKE_TEXTURE ",error," bytes=",FileAccess.get_file_as_bytes("res://resources/fake_smoke_density.res").size())
	quit(error)
