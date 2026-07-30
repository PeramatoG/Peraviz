extends SceneTree

const EXPECTED_NATIVE_CLASSES: PackedStringArray = [
	"HelloWorld",
	"PeravizLoader",
	"PeravizGoboVectorizer",
	"PeravizDmxReceiver",
	"PeravizVisualRuntime",
	"PeravizMvrXchangeClient",
]


func _initialize() -> void:
	for native_class_name: String in EXPECTED_NATIVE_CLASSES:
		if not ClassDB.class_exists(native_class_name):
			printerr("Missing native class: %s" % native_class_name)
			quit(1)
			return
	print("Registered %d expected Peraviz native classes." % EXPECTED_NATIVE_CLASSES.size())
	quit(0)
