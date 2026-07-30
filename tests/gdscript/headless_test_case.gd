extends RefCounted

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	if abs(actual - expected) > tolerance:
		failures.append("%s: expected %.7f got %.7f" % [message, expected, actual])

func finish(tree: SceneTree) -> void:
	for failure in failures:
		print("TEST FAILURE: %s" % failure)
	tree.quit(0 if failures.is_empty() else 1)
