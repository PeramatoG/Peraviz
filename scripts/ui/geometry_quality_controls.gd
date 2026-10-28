extends RefCounted

# Import preferences intentionally do not replace resources in the active scene.
static func install(host: VBoxContainer, preferences: UserPreferences) -> void:
	var label := Label.new()
	label.text = "Geometry quality — next import"
	host.add_child(label)
	var detail := OptionButton.new()
	for title in ["Default GDTF geometry","Prefer GDTF Low","Prefer GDTF High"]: detail.add_item(title)
	detail.select(["default","low","high"].find(preferences.gdtf_model_detail))
	detail.item_selected.connect(func(index: int) -> void:
		preferences.gdtf_model_detail = ["default","low","high"][index]
		preferences.save_to_disk()
	)
	host.add_child(detail)
	var lod := CheckBox.new()
	lod.text = "Automatic casing LOD (bounded)"
	lod.tooltip_text = "Optional Godot LOD for eligible opaque 3DS casing only. Off preserves original detail. Scenery and optics stay unchanged. Applies on next import."
	lod.button_pressed = preferences.fixture_casing_lod
	lod.toggled.connect(func(enabled: bool) -> void:
		preferences.fixture_casing_lod = enabled
		preferences.save_to_disk()
	)
	host.add_child(lod)
