extends RefCounted

# Import quality and live presentation are deliberately separate from optical settings.
static func install(tabs: TabContainer, preferences: UserPreferences, cache: RefCounted, viewport: Viewport) -> void:
	var host := VBoxContainer.new()
	host.name = "Geometry"
	host.add_theme_constant_override("separation",10)
	tabs.add_child(host)
	var label := Label.new()
	label.text = "GDTF source model quality — next import"
	host.add_child(label)
	var detail := OptionButton.new()
	detail.name = "SourceQuality"
	for title in ["Default GDTF model","Prefer GDTF Low","Prefer GDTF High"]: detail.add_item(title)
	detail.select(["default","low","high"].find(preferences.gdtf_model_detail))
	detail.item_selected.connect(func(index: int) -> void:
		preferences.gdtf_model_detail = ["default","low","high"][index]
		preferences.save_to_disk()
	)
	host.add_child(detail)
	var explanation := Label.new()
	explanation.text = "Selects an authored GDTF asset. Missing tiers use a deterministic fallback. Reimport to apply."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(explanation)
	var lod_label := Label.new()
	lod_label.text = "Automatic mesh LOD"
	host.add_child(lod_label)
	var lod := OptionButton.new()
	lod.name = "AutomaticLOD"
	lod.add_item("Enabled for verified compatible geometry")
	lod.add_item("Disabled / Original geometry")
	lod.select(0 if preferences.fixture_casing_lod else 1)
	lod.item_selected.connect(func(index: int) -> void:
		preferences.fixture_casing_lod = index == 0
		preferences.save_to_disk()
		cache.set_automatic(index == 0,viewport)
	)
	host.add_child(lod)
	cache.set_automatic(preferences.fixture_casing_lod,viewport)
	var note := Label.new()
	note.text = "Changes prepared meshes immediately. Original restores the retained source. Reimport to prepare meshes loaded while disabled. Optics and unsupported meshes stay original."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(note)
	var report_button := Button.new()
	report_button.text = "Inspect loaded geometry / refresh report"
	host.add_child(report_button)
	var report := TextEdit.new()
	report.name = "GeometryReport"
	report.editable = false
	report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report.custom_minimum_size.y = 140
	report.text = "On-demand report: resource paths, loader routes, LOD coverage, exclusions and packed memory. Rendered primitives include the entire viewport."
	host.add_child(report)
	report_button.pressed.connect(func() -> void: report.text = JSON.stringify(cache.report(viewport),"  "))
