extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const UUIDS := ["10000000-0000-0000-0000-000000000001","10000000-0000-0000-0000-000000000002","10000000-0000-0000-0000-000000000003"]
var test = TestCase.new()
var app: Node
var adapter: RefCounted

func _initialize() -> void: run.call_deferred()

func generate(case: String = "supported") -> String:
	var path: String = ProjectSettings.globalize_path("user://import_compatibility_%d_%s.mvr" % [OS.get_process_id(),case])
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_import_compatibility_fixture.py"),path,"--case",case])) == 0,"Generate redistributable compatibility archive")
	return path

func geometry(key: String) -> Node3D:
	for node: Node3D in app._node_index.values():
		if node.get_meta("peraviz_gdtf_geometry_key","") == key: return node
	return null

func mesh(node: Node3D) -> MeshInstance3D:
	var visual: Node3D = node.get_meta("peraviz_model_visual")
	if visual is MeshInstance3D: return visual
	return visual.find_children("*","MeshInstance3D",true,false)[0]

func output_values() -> Dictionary:
	var result: Dictionary = {}
	for index in range(adapter._binding_records.size()):
		var record: Dictionary = adapter._binding_records[index]
		result[record.geometry_key] = adapter._native.physical_values(index)
	return result

func apply_packets(packets: Dictionary) -> void:
	var runtime: RefCounted = app._dmx_controller._dmx_fixture_runtime
	for universe in packets: runtime._native_visual_runtime.submit_universe_frame(universe,packets[universe])
	# Initial semantic snapshot through the real native runtime/renderer applier.
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,app._fixture_light_apply_service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)

func packet() -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(512)
	return result

func run() -> void:
	check_diagnostic_ownership()
	var path: String = generate()
	var original_hash: String = FileAccess.get_sha256(path)
	test.check(FileAccess.get_sha256(generate()) == original_hash,"Repeated generation produces byte-identical archives")
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._user_preferences.auto_load_last_file = false
	app._dmx_controller.set_universe_offset(-1,false)
	var loaded: Dictionary = await app._load_mvr_scene(path,"mvr",false)
	test.check(loaded.get("ok",false),"Real production import, native compilation and Godot setup complete")
	adapter = app._fixture_light_apply_service._dense_adapter
	var compiled: Dictionary = app._loader.compile_visual_runtime_scene(-1)
	test.check(compiled.fixture_count == 3 and compiled.diagnostics.is_empty(),"Supported primary-break modes compile without diagnostics")
	var metrics: Dictionary = app._loader.get_load_metrics()
	test.check(metrics.geometry_definitions == 2 and metrics.geometry_template_hits == 1,"Geometry definitions cache by exact GDTF and selected mode, not fixture UUID")
	test.check(adapter._outputs.size() == 6,"Six canonical physical Beam outputs survive repeated references and fixtures")
	var patches: Array = app._loader.get_fixtures_patch()
	test.check(patches[0].fixture_uuid == UUIDS[0] and patches[1].fixture_uuid == UUIDS[1] and patches[2].fixture_uuid == UUIDS[2],"Source UUIDs survive independently of generated runtime IDs")
	test.check(patches[0].gdtf_path == patches[1].gdtf_path and patches[0].dmx_mode == "Direct" and patches[2].dmx_mode == "References","Shared GDTF source identity does not replace selected-mode identity")
	test.check(patches[0].mvr_universe == 3 and patches[0].mvr_address == 11 and patches[1].mvr_universe == 3 and patches[1].mvr_address == 43,"Dotted and absolute MVR addresses retain exact primary assignments")
	var keys: Dictionary = {}
	var targets: Dictionary = {}
	var components: Dictionary = {}
	var identity: Array = []
	for row: Dictionary in compiled.renderer_targets:
		if row.semantic == "beam_profile":
			test.check(not targets.has(row.target_id) and row.geometry_key.begins_with(row.fixture_uuid+"/"),"Native target identities are unique and fixture-scoped")
			targets[row.target_id] = row.fixture_uuid
			keys[row.geometry_key] = row.target_id
			identity.append([row.geometry_key,row.target_id])
		if row.get("component_id",0) > 0:
			if components.has(row.component_id): test.check(components[row.component_id] == row.fixture_uuid,"Component identity never aliases another fixture")
			components[row.component_id] = row.fixture_uuid
	for row: Dictionary in adapter._binding_records:
		test.check(keys[row.geometry_key] == row.beam_render_target_id and targets[row.beam_render_target_id] == row.fixture_uuid,"Actual native-to-renderer records preserve physical target ownership")
	var left: Node3D = geometry(UUIDS[0]+"/Base/Pan/Tilt/Left")
	var other: Node3D = geometry(UUIDS[1]+"/Base/Pan/Tilt/Left")
	var a: Node3D = geometry(UUIDS[2]+"/Panel/CellA/Cell/Pixel")
	var b: Node3D = geometry(UUIDS[2]+"/Panel/CellB/Cell/Pixel")
	test.check(left != null and other != null and a != null and b != null and a != b,"Reference expansion retains separate canonical nodes and full paths")
	test.check(left.get_parent().get_parent().name.contains("Pan") and a.get_parent() != b.get_parent(),"Mechanical and referenced source hierarchy remain independent")
	test.check(geometry(UUIDS[0]+"/Base").global_position.is_equal_approx(Vector3(1.1,3.3,-2.2)),"MVR millimetres and GDTF metres compose exactly once")
	test.check(geometry(UUIDS[1]+"/Base").global_position.is_equal_approx(Vector3(3.9,3.3,-2.2)) and other.global_basis.determinant() < 0,"Reflected fixture orientation and placement survive")
	test.check(a.position.is_equal_approx(Vector3(0,0.1,0)) and not a.global_position.is_equal_approx(b.global_position),"Distinct reference placements retain original emitter insertion points")
	test.check(mesh(left).mesh == mesh(other).mesh and mesh(a).mesh == mesh(b).mesh,"Immutable source meshes share while instance nodes/transforms remain separate")
	var extracted: Array = []
	for row: Dictionary in compiled.gobo_assets:
		if row.get("media_valid",false) and not str(row.extracted_media_path).is_empty(): extracted.append(row.extracted_media_path)
	test.check(extracted.size() >= 2 and extracted[0] == extracted[1] and FileAccess.file_exists(extracted[0]),"Repeated fixture media use the same live immutable extraction")
	var values := packet()
	# Fixture A starts at 3.11; B at absolute 1067 = 3.43. Offsets are one-based.
	values[10] = 64; values[11] = 128; values[12] = 90
	values[13] = 255; values[14] = 255
	values[17] = 64; values[19] = 255
	values[21] = 255
	values[42] = 0; values[43] = 0; values[44] = 160
	values[45] = 128; values[48] = 255
	values[49] = 0; values[50] = 255
	var panel := packet()
	panel[3] = 192; panel[4] = 255
	var pan_position: Vector3 = geometry(UUIDS[0]+"/Base/Pan").position
	apply_packets({2:values,3:panel})
	var physical: Dictionary = output_values()
	var va: PackedFloat32Array = physical[UUIDS[0]+"/Base/Pan/Tilt/Left"]
	var vb: PackedFloat32Array = physical[UUIDS[1]+"/Base/Pan/Tilt/Left"]
	test.check(is_equal_approx(va[0],1.0) and va[1] > 0.99 and va[3] < 0.01,"First fixture's actual native Left output is full red at its own offsets")
	test.check(is_equal_approx(vb[0],128.0/255.0) and vb[3] > 0.99 and vb[1] < 0.01,"Repeated fixture independently resolves blue/Dimmer from its own start address")
	test.check(is_equal_approx(physical[UUIDS[0]+"/Base/Pan/Tilt/Right"][0],64.0/255.0) and physical[UUIDS[1]+"/Base/Pan/Tilt/Right"][0] == 0.0,"Independent Beam controls and blackout do not alias sibling outputs")
	test.check(is_equal_approx(physical[UUIDS[2]+"/Panel/CellA/Cell/Pixel"][0],192.0/255.0) and physical[UUIDS[2]+"/Panel/CellA/Cell/Pixel"] == physical[UUIDS[2]+"/Panel/CellB/Cell/Pixel"],"Common ancestor control fans out to both repeated physical reference outputs")
	test.check(geometry(UUIDS[0]+"/Base/Pan").position == pan_position and not geometry(UUIDS[0]+"/Base/Pan").basis.is_equal_approx(geometry(UUIDS[1]+"/Base/Pan").basis),"Independent 16-bit native Pan changes orientations without moving pivots")
	test.check_close(geometry(UUIDS[0]+"/Base/Pan").rotation_degrees.y,16512.0/65535.0*180.0,0.001,"Coarse/fine byte order and nonzero fixture start address produce the exact physical Pan angle")
	preload("res://tests/gdscript/helpers/live_settings_probe.gd").check_lenses(self,1.0)
	var held: Dictionary = output_values()
	await process_frame
	test.check(output_values() == held,"DMX hold preserves all independent physical states")
	panel[3] = 0
	apply_packets({3:panel})
	var isolated: Dictionary = output_values()
	test.check(isolated[UUIDS[0]+"/Base/Pan/Tilt/Left"] == va and isolated[UUIDS[1]+"/Base/Pan/Tilt/Left"] == vb,"A packet on another universe retains independently held fixture states")
	test.check(isolated[UUIDS[2]+"/Panel/CellA/Cell/Pixel"][0] == 0.0 and isolated[UUIDS[2]+"/Panel/CellB/Cell/Pixel"][0] == 0.0,"Common reference blackout updates both physical outputs on only their universe")
	preload("res://tests/gdscript/helpers/live_settings_probe.gd").check_lenses(self,1.0)
	var weak: WeakRef = weakref(left)
	left = null; other = null; a = null; b = null
	await app._load_mvr_scene(path,"mvr",false)
	await process_frame
	test.check(weak.get_ref() == null,"Reload retires old Godot instances")
	var reloaded_assets: Array = app._loader.compile_visual_runtime_scene(-1).gobo_assets
	for asset: Dictionary in reloaded_assets:
		if not str(asset.extracted_media_path).is_empty(): test.check(FileAccess.file_exists(asset.extracted_media_path),"Reloaded immutable media have a live generation owner")
	var again: Array = []
	for row: Dictionary in app._loader.compile_visual_runtime_scene(-1).renderer_targets:
		if row.semantic == "beam_profile": again.append([row.geometry_key,row.target_id])
	test.check(again == identity,"Reload preserves canonical identities while rebuilding generation-owned resources")
	app._clear_scene()
	app.queue_free()
	await process_frame
	app = null; adapter = null
	# Parsed compatibility metadata can retain a media lease until the next preparation.
	# The next native begin below owns that existing cache-retirement boundary.
	test.check(FileAccess.get_sha256(path) == original_hash,"Production import/playback/reload never modify source or unknown archive content")
	await check_unsupported(extracted[0])
	await check_partial_production_import()
	await check_multibreak_playback()
	test.finish(self)

func check_unsupported(retired_media: String) -> void:
	for case in ["multiple_breaks","duplicate_break","nonprimary_break","gdtf_break","overwrite","ambiguous_reference","reference_offset","copatched"]:
		var path: String = generate(case)
		var hash_before: String = FileAccess.get_sha256(path)
		var loader := PeravizLoader.new()
		test.check(loader.begin_load_mvr(path,-1),"Native production preparation accepts baseline case")
		while not loader.is_load_mvr_ready(): await process_frame
		var nodes: Array = loader.finish_load_mvr()
		if case == "multiple_breaks": test.check(not FileAccess.file_exists(retired_media),"Next preparation retires the prior compatibility media-cache owner")
		var compiled: Dictionary = loader.compile_visual_runtime_scene(-1)
		if case in ["copatched","multiple_breaks","reference_offset"]:
			test.check(compiled.fixture_count == 3 and compiled.diagnostics.is_empty(),"Intentional cross-fixture address overlap retains separate identities")
			var ids: Dictionary = {}
			for row: Dictionary in compiled.renderer_targets:
				if row.semantic == "beam_profile": ids[row.target_id] = true
			test.check(ids.size() == 6,"Co-patched fixtures never collapse their physical output identities")
		else:
			var code: String = "PVZ-MVR-DMX-PATCH-UNSUPPORTED" if case == "duplicate_break" else "PVZ-GDTF-DMX-PATCH-UNSUPPORTED"
			var found: bool = false
			for issue: Dictionary in compiled.diagnostics:
				if issue.code == code and issue.severity == "error": found = true
			test.check(compiled.fixture_count == 2 and found,"Unsupported addressing is explicit and withholds only the affected fixture: "+case)
			var bad: String = UUIDS[1] if case in ["multiple_breaks","duplicate_break","nonprimary_break","gdtf_break"] else UUIDS[2]
			for row: Dictionary in compiled.renderer_manifest: test.check(row.fixture_uuid != bad,"Unsupported fixture publishes no misleading native renderer bindings")
			for row: Dictionary in loader.build_fixture_dmx_bindings(-1).bindings: test.check(row.fixture_uuid != bad,"Compatibility metadata does not bypass the native patch rejection")
		var fixtures: int = 0
		for node: Dictionary in nodes:
			if node.get("type","") == "fixture": fixtures += 1
		test.check(fixtures == 3 and FileAccess.get_sha256(path) == hash_before,"Unsupported patching retains original fixture geometry and source bytes")
		print("IMPORT_COMPATIBILITY ",JSON.stringify({"case":case,"source_fixtures":fixtures,"compiled_fixtures":compiled.fixture_count,"diagnostics":compiled.diagnostics}))
		loader.free()

func check_partial_production_import() -> void:
	var path: String = generate("duplicate_break")
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var result: Dictionary = await app._load_mvr_scene(path,"mvr",false)
	test.check(result.get("ok",false),"Unsupported fixture patch does not prevent valid fixtures/static geometry from importing")
	test.check(geometry(UUIDS[1]+"/Base/Pan/Tilt/Left") != null,"Actual Godot hierarchy retains the unsupported fixture's source geometry")
	var summary: Dictionary = app._dmx_controller._dmx_fixture_runtime._native_setup_summary
	test.check(summary.compile_diagnostics.size() == 1 and summary.compile_diagnostics[0].code == "PVZ-MVR-DMX-PATCH-UNSUPPORTED","Normal setup forwards native incompatibility diagnostics without a semantic fallback")
	test.check(app._fixture_light_apply_service._dense_adapter._outputs.size() == 4,"Actual Godot bindings contain only supported physical outputs, without legacy fallback")
	app._clear_scene()
	app.queue_free()
	await process_frame
	app = null

func check_diagnostic_ownership() -> void:
	var factory := NodeFactory.new()
	var cache := PeravizRuntimeAssetCache.new()
	var holder := Node3D.new()
	root.add_child(holder)
	var dummy: MeshInstance3D = factory._create_dummy_mesh(false,1.0,cache)
	factory._force_double_sided_materials(dummy)
	holder.add_child(dummy)
	var source: WeakRef = weakref(dummy.mesh)
	cache.derived_lods.record(dummy,{},"primitive","fallback")
	holder.free()
	test.check(source.get_ref() == null,"Optional geometry diagnostics must not extend a retired fallback mesh's lifetime")
	test.check(cache.derived_lods.report(root).mesh_resources == 0,"Diagnostics handle expired mesh provenance without touching invalid materials")

func check_multibreak_playback() -> void:
	for case in ["multibreak","numbered_references","multibreak_async"]:
		var worker: bool = case == "multibreak_async"
		OS.set_environment("PERAVIZ_NATIVE_EVALUATION","parallel" if worker else "serial")
		var path: String = generate(case)
		var source_hash: String = FileAccess.get_sha256(path)
		app = load("res://test.tscn").instantiate()
		root.add_child(app)
		await process_frame
		app._dmx_controller.set_universe_offset(-1,false)
		var loaded: Dictionary = await app._load_mvr_scene(path,"mvr",false)
		test.check(loaded.get("ok",false),"Multi-break production scene loads: "+case)
		adapter = app._fixture_light_apply_service._dense_adapter
		var compiled: Dictionary = app._loader.compile_visual_runtime_scene(-1)
		test.check(compiled.fixture_count == 3 and compiled.diagnostics.is_empty(),"All resolved multi-break/reference fixtures compile without fallback diagnostics")
		test.check(adapter._outputs.size() == 6,"Independent references retain all six actual renderer outputs")
		var patches: Array = app._loader.get_fixtures_patch()
		test.check(patches[1].addresses.size() == 2 and patches[1].addresses[1].mvr_break == 1 and patches[1].addresses[1].universe == 5,"Public patch metadata retains exact secondary break identity")
		for row: Dictionary in app._loader.build_fixture_dmx_bindings(-1).bindings:
			test.check(row.fixture_uuid == UUIDS[0],"Legacy single-universe metadata cannot override multi-break/reference routing")
		var primary := packet()
		primary[45] = 255 # Split Left Dimmer: address 43 + offset 4 - 2.
		var secondary := packet()
		secondary[100] = 128; secondary[101] = 64 # Fine/coarse order is declared as 2,1.
		secondary[104] = 255 # Left red, break 2 offset 5.
		secondary[107] = 64; secondary[109] = 255 # Right Dimmer/green.
		secondary[112] = 128; secondary[114] = 64; secondary[113] = 32 # Ordered 24-bit Tilt.
		var cells := packet()
		cells[0] = 255; cells[1] = 255; cells[29] = 0
		var other := packet()
		var other_start: int = 108 if case != "numbered_references" else 8
		other[other_start] = 128; other[other_start+3] = 255
		if case == "numbered_references":
			cells[8] = 128; cells[11] = 255
		await apply_routed_packets({2:primary,4:secondary,3:cells,5:other},worker)
		var actual: Dictionary = output_values()
		var left: String = UUIDS[1]+"/Base/Pan/Tilt/Left"
		var right: String = UUIDS[1]+"/Base/Pan/Tilt/Right"
		var a: String = UUIDS[2]+"/Panel/CellA/Cell/Pixel"
		var b: String = UUIDS[2]+"/Panel/CellB/Cell/Pixel"
		test.check(actual[left][0] == 1.0 and actual[left][1] > 0.99,"Dimmer on break 1 composes with red on break 2 on the actual output")
		test.check_close(actual[right][0],64.0/255.0,0.001,"Second break independently drives sibling Dimmer")
		test.check(actual[right][2] > 0.99,"Second-break green reaches its own physical output")
		test.check(actual[a][0] == 1.0 and actual[a][1] > 0.99 and actual[a][3] < 0.01,"Reference A emits red at its own effective source")
		test.check_close(actual[b][0],128.0/255.0,0.001,"Reference B resolves its own remapped Dimmer")
		test.check(actual[b][3] > 0.99 and actual[b][1] < 0.01,"Reference B emits independent blue without last-instance aliasing")
		test.check_close(geometry(UUIDS[1]+"/Base/Pan").rotation_degrees.y,16512.0/65535.0*180.0,0.001,"Explicit-break noncontiguous/coarse-fine order drives native Pan")
		test.check_close(geometry(UUIDS[1]+"/Base/Pan/Tilt").rotation_degrees.x,8405024.0/16777215.0*90.0,0.001,"Ordered 24-bit explicit-break source drives native Tilt")
		preload("res://tests/gdscript/helpers/live_settings_probe.gd").check_lenses(self,1.0)
		await process_frame
		test.check(output_values() == actual,"Held multi-universe state is stable without new packets")
		var before_a: Basis = geometry(a).global_basis
		var before_b: Basis = geometry(b).global_basis
		cells[29] = 128
		await apply_routed_packets({3:cells},worker)
		var changed: Dictionary = output_values()
		test.check(changed[left] == actual[left] and changed[right] == actual[right],"Updating one break preserves held values on every other break")
		test.check_close(geometry(UUIDS[2]+"/Panel").rotation_degrees.y,128.0/255.0*180.0,0.001,"Common ancestor Pan retains its own source addressing")
		test.check(not geometry(a).global_basis.is_equal_approx(before_a) and not geometry(b).global_basis.is_equal_approx(before_b),"Common ancestor motion affects both referenced descendants through the preserved hierarchy")
		cells[0] = 0
		await apply_routed_packets({3:cells},worker)
		test.check(output_values()[a][0] == 0.0 and output_values()[b] == actual[b],"Instance blackout preserves sibling output and its held break")
		cells[0] = 255
		await apply_routed_packets({3:cells},worker)
		test.check(output_values()[a] == actual[a] and output_values()[b] == actual[b],"Blackout restore preserves independently held colors and intensities")
		var routed: PackedByteArray = other if case != "numbered_references" else cells
		routed[other_start] = 96; routed[other_start+2] = 255; routed[other_start+3] = 0
		await apply_routed_packets({5 if case != "numbered_references" else 3:routed},worker)
		var worker_values: Dictionary = output_values()
		test.check_close(worker_values[b][0],96.0/255.0,0.001,"Native asynchronous evaluation resolves the same instance/break mapping")
		test.check(worker_values[b][2] > 0.99 and worker_values[b][3] < 0.01 and worker_values[a] == actual[a],"Worker publication preserves independent held sources across universes")
		app._visual_settings["beam_render_mode"] = 1
		app._update_beam_renderer_mode(false)
		adapter.refresh_renderer()
		await apply_routed_packets({},worker)
		test.check(output_values()[b] == worker_values[b],"Renderer replacement replays held multi-break physical state")
		preload("res://tests/gdscript/helpers/live_settings_probe.gd").check_lenses(self,1.0)
		# Restore the original input snapshot before verifying the next scene generation.
		routed[other_start] = 128; routed[other_start+2] = 0; routed[other_start+3] = 255
		var retired: WeakRef = weakref(geometry(b))
		await app._load_mvr_scene(path,"mvr",false)
		await process_frame
		adapter = app._fixture_light_apply_service._dense_adapter
		test.check(retired.get_ref() == null and adapter._outputs.size() == 6,"Multi-break reload retires old nodes and reinstalls independent native targets")
		await apply_routed_packets({2:primary,4:secondary,3:cells,5:other},worker)
		test.check(output_values()[b] == actual[b],"Reloaded renderer receives identical remapped physical state")
		test.check(FileAccess.get_sha256(path) == source_hash,"Multi-break import/playback/reload leaves the original archive byte-identical")
		app._clear_scene()
		app.queue_free()
		await process_frame
		app = null; adapter = null
		OS.unset_environment("PERAVIZ_NATIVE_EVALUATION")

func apply_async_packets(packets: Dictionary) -> void:
	var runtime: RefCounted = app._dmx_controller._dmx_fixture_runtime
	var service: RefCounted = app._fixture_light_apply_service
	for universe in packets: runtime._native_visual_runtime.submit_universe_frame(universe,packets[universe])
	var generation: int = runtime._sectioned_visual_frame_applier.schema_generation()
	var frame: Dictionary = service.consume_native_snapshot(runtime._native_visual_runtime,generation)
	var deadline: int = Time.get_ticks_msec()+5000
	while frame.get("pending",false) and Time.get_ticks_msec()<deadline:
		await process_frame
		frame = service.consume_native_snapshot(runtime._native_visual_runtime,generation,true)
	test.check(not frame.get("pending",false),"Multi-break native worker completes through the normal nonblocking poll")
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	test.check(adapter._native.get_sizes().get("native_async_active",false),"Multi-break playback uses the production native asynchronous owner")

func apply_routed_packets(packets: Dictionary, worker: bool) -> void:
	if worker: await apply_async_packets(packets)
	else: apply_packets(packets)
