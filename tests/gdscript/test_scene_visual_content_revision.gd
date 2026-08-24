extends SceneTree

const SceneRegistryScript = preload("res://scripts/scene_registry.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()
var _notifications: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry: SceneRegistry = SceneRegistryScript.new()
	registry.visual_content_changed.connect(_on_visual_content_changed)

	test.check(registry.get_visual_content_revision() == 0, "A new registry should start at visual content revision zero")
	registry.notify_visual_content_changed("mvr_import")
	registry.notify_visual_content_changed("scene_edit")

	test.check(registry.get_visual_content_revision() == 2, "Every visual content invalidation should advance the revision")
	test.check(_notifications.size() == 2, "Every visual content invalidation should notify dependent views")
	if _notifications.size() == 2:
		test.check(_notifications[0] == {"revision": 1, "reason": "mvr_import"}, "MVR imports should identify the first completed visual revision")
		test.check(_notifications[1] == {"revision": 2, "reason": "scene_edit"}, "Later visual edits should remain distinguishable")

	test.finish(self)

func _on_visual_content_changed(revision: int, reason: String) -> void:
	_notifications.append({"revision": revision, "reason": reason})
