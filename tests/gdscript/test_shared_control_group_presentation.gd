extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const LoaderBase = preload("res://tests/gdscript/helpers/coalescing_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")

class GroupLoader extends LoaderBase:
	var _active_beam_renderer: BeamRendererBase
	var lenses: Array[MeshInstance3D] = []
	var split_materials: bool = false
	func _ready() -> void:
		output_count = 51
		renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd").new()
		_visual_settings = {"enable_realtime_spotlights": false, "beam_presentation": 1}
		renderer.configure(null, _visual_settings)
		super._ready()
		_active_beam_renderer = renderer
		var source := StandardMaterial3D.new()
		source.albedo_color = Color(0.4, 0.5, 0.6)
		for i in range(50):
			outputs[i]["presentation_control_group"] = 1
			var lens := MeshInstance3D.new()
			lens.mesh = SphereMesh.new()
			add_child(lens)
			lenses.append(lens)
			var static_source: BaseMaterial3D = source
			if split_materials and i < 3:
				static_source = source.duplicate(true)
				static_source.albedo_color = Color(float(i)/3.0, 0.5, 0.6)
				if i == 2: static_source.next_pass = StandardMaterial3D.new()
			var prepared: BaseMaterial3D = static_source.duplicate(true)
			prepared.emission_enabled = true
			prepared.emission_energy_multiplier = 0
			lens.set_surface_override_material(0, prepared)
			outputs[i]["lens_material_targets"] = [{"mesh": lens, "surface": 0, "material": prepared, "source_material": static_source, "beam_optical_profile": {"emission_lumen_scale": 2.0 if split_materials and i == 3 else 1.0}}]

class Bindings extends RefCounted:
	var outputs: Array
	func get_dense_presentation_bindings() -> Dictionary:
		var ids := PackedInt32Array()
		var scales := PackedFloat32Array()
		var routes := PackedInt32Array()
		for i in range(outputs.size()):
			ids.append(int(outputs[i]["beam_render_target_id"]))
			scales.append(1.0 if i < 50 else 0.0)
			routes.append_array(PackedInt32Array([2, 201, i, 3, 301+i, i, 4, 401, i]))
		return {"ids": ids, "scales": scales, "routes": routes, "outputs": outputs}

var test = TestCase.new()

func _init() -> void:
	call_deferred("_run")

func _snapshot(adapter: RefCounted, dim: PackedFloat32Array, color: PackedFloat32Array) -> void:
	var descriptors := PackedInt32Array()
	var integers := PackedInt32Array()
	var values := PackedFloat32Array()
	if not dim.is_empty():
		descriptors.append_array(PackedInt32Array([2, 1, 0, 0, 0]))
		integers.append_array(PackedInt32Array([1, 201, 2]))
		values.append_array(dim)
	if not color.is_empty():
		descriptors.append_array(PackedInt32Array([3, 50, integers.size(), values.size(), 0]))
		for i in range(50):
			integers.append_array(PackedInt32Array([1, 301+i, 4]))
			values.append_array(color)
	test.check(adapter.compose(descriptors, integers, values, true, "full"), "Native group snapshot is accepted")
	adapter.apply()

func _run() -> void:
	var loader := GroupLoader.new()
	get_root().add_child(loader)
	await process_frame
	var service = Service.new()
	var bindings := Bindings.new()
	bindings.outputs = loader.outputs
	service.install_dense_presentation(loader, bindings)
	var adapter: RefCounted = service._dense_adapter
	var sizes: Dictionary = adapter.diagnostics()
	test.check(sizes["physical_outputs"] == 51 and sizes["presentation_control_groups"] == 2 and sizes["largest_group"] == 50, "51 canonical outputs become one 50-member presentation group plus Aura")
	test.check(sizes["shared_beam_material_groups"] == 1 and sizes["shared_lens_material_groups"] == 1, "Beam and source-identical lens resources share safely")
	var group = adapter._groups[0]
	var shared: ShaderMaterial = group.material
	var shared_lens: Material = loader.lenses[0].get_surface_override_material(0)
	for i in range(50):
		test.check(loader.renderer.get_beam_resource(loader.anchors[i]).material_override == shared, "Every physical shaft shares group material")
		test.check(loader.lenses[i].get_surface_override_material(0) == shared_lens, "Every source-identical lens shares prepared material")
	test.check(adapter._groups[50] == null, "Aura remains independently emission-only")
	_snapshot(adapter, PackedFloat32Array([0.5, 10, 8, 10, 2]), PackedFloat32Array([0.2, 0.4, 0.8, 1]))
	adapter.consume_diagnostics()
	var instance_writes: int = loader.renderer.renderer_shader_parameter_writes
	_snapshot(adapter, PackedFloat32Array(), PackedFloat32Array([0.7, 0.3, 0.1, 1]))
	var counters: Dictionary = adapter.consume_diagnostics()
	test.check(counters["physical_dynamic_candidates"] == 50 and counters["control_group_dynamic_updates"] == 1, "Physical fan-out is coalesced before the GDScript boundary")
	test.check(counters["actual_beam_dynamic_renderer_writes"] == 1 and loader.renderer.renderer_shader_parameter_writes == instance_writes, "Color change writes one group uniform and zero per-instance uniforms")
	test.check(counters["actual_lens_material_renderer_writes"] == 1, "RGB change writes one lens material RID")
	var dynamic: Color = shared.get_shader_parameter("control_group_dynamic_state")
	test.check(is_equal_approx(dynamic.r, 0.7) and dynamic.a == 10, "Shared shaft receives exact held RGB/intensity")
	_snapshot(adapter, PackedFloat32Array([0, 0, 0, 0, 0]), PackedFloat32Array())
	_snapshot(adapter, PackedFloat32Array(), PackedFloat32Array([0.1, 0.6, 0.3, 0.25]))
	_snapshot(adapter, PackedFloat32Array([0, 0, 0, 0, 0]), PackedFloat32Array([0.3, 0.5, 0.2, 0.5]))
	_snapshot(adapter, PackedFloat32Array([0.8, 20, 16, 30, 4]), PackedFloat32Array())
	dynamic = shared.get_shader_parameter("control_group_dynamic_state")
	test.check(is_equal_approx(dynamic.r, 0.3) and dynamic.a > 0, "Dark-to-visible restores latest held RGB and Color gain without another Color packet")
	test.check(is_equal_approx(group.materials[0].energy, 2.0), "Latest held gain scales lens material emission exactly")
	for i in range(50):
		test.check(loader.renderer.get_beam_resource(loader.anchors[i]).visible, "All 50 physical shafts remain rendered")
		test.check(is_equal_approx(adapter.light_state(loader.anchors[i])["color"].r, 0.3), "Inverse physical lookup resolves current grouped held Color")
	test.check(not loader.renderer.get_beam_resource(loader.anchors[50]).visible, "Aura never becomes a projected shaft")
	# Color-gain blackout also retains Dimmer changes independently of Color packets.
	_snapshot(adapter, PackedFloat32Array(), PackedFloat32Array([0.3, 0.5, 0.2, 0]))
	_snapshot(adapter, PackedFloat32Array([0.9, 22, 18, 35, 5]), PackedFloat32Array())
	test.check(adapter._groups[0].dynamic.a == 0, "Dimmer changes remain dark under zero Color gain")
	_snapshot(adapter, PackedFloat32Array(), PackedFloat32Array([0.3, 0.5, 0.2, 1]))
	test.check(adapter._groups[0].dynamic.a == 35 and adapter._groups[0].materials[0].energy == 5, "Reopening Color restores latest held Dimmer/intensity/material energy without another Dimmer packet")
	adapter.set_mode("no-beams")
	test.check(adapter.light_state(loader.anchors[0])["visible"], "Suppression preserves canonical desired visibility for physical inverse lookup")
	adapter.set_mode("full")
	service.refresh_dense_renderer()
	test.check(adapter._groups[0] != group and adapter._groups[0].material != shared, "Renderer refresh retires previous group resource state")
	adapter.clear()
	test.check(adapter._groups.is_empty() and adapter._outputs.is_empty(), "Scene retirement releases every group and physical binding")
	service.reset_scene_state()
	loader.queue_free()
	var split_loader := GroupLoader.new()
	split_loader.split_materials = true
	get_root().add_child(split_loader)
	await process_frame
	bindings.outputs = split_loader.outputs
	service.install_dense_presentation(split_loader, bindings)
	adapter = service._dense_adapter
	test.check(adapter._groups[0].materials.size() == 5, "Different source appearance, multipass state and lens scaling retain distinct material subgroups")
	_snapshot(adapter, PackedFloat32Array([0.5, 10, 8, 10, 2]), PackedFloat32Array([0.2, 0.4, 0.8, 1]))
	adapter.consume_diagnostics()
	_snapshot(adapter, PackedFloat32Array([0.6, 12, 10, 12, 3]), PackedFloat32Array())
	counters = adapter.consume_diagnostics()
	test.check(counters["actual_beam_dynamic_renderer_writes"] == 1 and counters["actual_lens_material_renderer_writes"] == 5, "Dimmer writes one shaft state and each compatible lens subgroup once")
	# Explicit native light ownership must keep per-light RGB/energy current.
	split_loader._visual_settings["enable_realtime_spotlights"] = true
	service.refresh_dense_renderer()
	test.check(adapter.diagnostics()["grouped_physical_outputs"] == 0, "Realtime light ownership uses the safe individual fallback")
	_snapshot(adapter, PackedFloat32Array([0.7, 14, 11, 14, 3]), PackedFloat32Array([0.9, 0.2, 0.1, 1]))
	test.check(is_equal_approx(split_loader.anchors[0].light_color.r, 0.9), "Fallback preserves independently updated realtime light properties")
	service.reset_scene_state()
	split_loader.queue_free()
	await process_frame
	await process_frame
	test.finish(self)
