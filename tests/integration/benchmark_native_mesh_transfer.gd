extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var iterations: int = int(args[1]) if args.size() > 1 else 500
	var loader: Object = ClassDB.instantiate("PeravizLoader")
	var initial: Dictionary = loader.load_3ds_mesh_data(args[0])
	if not initial.get("ok",false):
		push_error("Synthetic native mesh did not decode")
		loader.free()
		quit(1)
		return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(initial))
	var signature: String = hash.finish().hex_encode()
	var started := Time.get_ticks_usec()
	for iteration in range(iterations):
		var decoded: Dictionary = loader.load_3ds_mesh_data(args[0])
		if not decoded.get("ok",false):
			push_error("Repeated native mesh decode failed")
			loader.free()
			quit(1)
			return
	print("NATIVE_MESH_TRANSFER_BENCHMARK ",JSON.stringify({"iterations":iterations,"total_ms":(Time.get_ticks_usec()-started)/1000.0,"vertices":initial.vertices.size(),"indices":initial.indices.size(),"buffer_signature":signature}))
	loader.free()
	quit()
