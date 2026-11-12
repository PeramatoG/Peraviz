extends VBoxContainer

signal policy_changed(policy: String)
const Policy = preload("res://scripts/project/dmx_auto_span_policy.gd")
var selector: OptionButton

func _init() -> void:
	name = "DMX"
	var label := Label.new()
	label.text = "DMX Auto Span"
	add_child(label)
	selector = OptionButton.new()
	for text in ["Off (strict)", "Automatic — only if free", "Allow overlaps"]: selector.add_item(text)
	selector.tooltip_text = "Automatically continues eligible fixtures into the next DMX universe. This is a Peraviz compatibility feature and does not modify the original MVR patch. Allow overlaps makes multiple fixtures respond to the same DMX channels."
	add_child(selector)
	selector.select(1)
	selector.item_selected.connect(func(index: int) -> void: policy_changed.emit(Policy.IDS[index]))

func set_policy(policy: String) -> void:
	selector.select(Policy.IDS.find(Policy.normalize(policy)))
