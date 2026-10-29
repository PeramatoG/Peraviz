extends RefCounted

const Probe = preload("res://tests/gdscript/helpers/shutter_output_probe.gd")

# Verifies real production parser defaults/ranges and opt-in native diagnostics without GDScript DMX interpretation.
static func run(owner: SceneTree) -> void:
	OS.set_environment("PERAVIZ_SHUTTER_TRACE","50000000-0000-0000-0000-000000000001")
	await owner.open_scene(["--fidelity"],8)
	var primary: PackedByteArray = owner.packet(); primary[0] = 255; primary[1] = 255
	var cells: PackedByteArray = owner.packet(); cells.fill(10)
	owner.send({0:primary,2:cells},0)
	var baseline: Array = Probe.capture(owner.adapter)
	var target: int = owner.adapter._outputs[owner.cell_index(0)].canonical_id
	for pair in [[19,0,-1],[20,2,0],[39,2,1],[40,2,0],[59,2,12],[60,2,20],[79,2,2],[80,2,2],[89,2,10],[90,2,7],[98,2,7],[99,2,12],[100,-1,0]]:
		cells[0] = pair[0]
		var frame: Dictionary = owner.send({2:cells},0)
		var parameters: Dictionary = Probe.parameters(frame,target)
		# Unchanged physical values may legitimately produce no new temporal row.
		if parameters.frequency >= 0:
			owner.test.check(parameters.mode == pair[1],"Production range boundary chooses the declared shutter waveform")
			if pair[2]>=0: owner.test.check_close(parameters.frequency,pair[2],0.0001,"Production raw DMX resolves exact local Hz/defaults/descending/fixed values")
		var evaluations: int = owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated
		var trace: Dictionary = owner.runtime._native_visual_runtime.get_shutter_trace("50000000-0000-0000-0000-000000000001",target)
		owner.test.check(owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated == evaluations,"Diagnostic inspection never evaluates physical sources")
		owner.test.check(trace.available and trace.rows.size()<=64,"Selected-output native trace is opt-in and bounded")
		for row in trace.rows:
			if not row.active: continue
			owner.test.check(row.raw_dmx == pair[0] and row.resolution_bits == 8,"Trace exposes actual raw value and source resolution")
			owner.test.check(row.mvr_break == 1,"Trace preserves the effective reference/MVR break")
			owner.test.check(row.ordered_bytes[0].mvr_universe == 3 and row.ordered_bytes[0].channel == 1,"Trace reveals actual MVR universe and channel")
			if pair[2]>0 and pair[1]==2:
				owner.test.check_close(row.frequency_hz,pair[2],0.0001,"Trace Hz matches the selected function/set")
				owner.adapter._native.advance_shutters(owner.adapter._generation,0.999/pair[2])
				Probe.check(owner,baseline,0,1)
	await owner.close_scene()
	OS.unset_environment("PERAVIZ_SHUTTER_TRACE")
	await random_outputs(owner)
	await split_random(owner)
	await split_random(owner,true)
	await split_random(owner,true,false)
	await conditional_mode_guard(owner)

# Uses all four actual random source families and compares committed shaft/footprint/material/batch output.
static func random_outputs(owner: SceneTree) -> void:
	await owner.open_scene(["--random-modes"],32)
	var primary: PackedByteArray = owner.packet(); primary[0] = 255; primary[1] = 255
	var cells: PackedByteArray = owner.packet(); cells.fill(10)
	owner.send({0:primary,2:cells},0)
	var baseline: Array = Probe.capture(owner.adapter)
	cells[0] = 119; cells[1] = 120; cells[2] = 160; cells[3] = 200; cells[4] = 119; cells[5] = 119
	var frame: Dictionary = owner.send({2:cells},1)
	for cell in range(4):
		var p: Dictionary = Probe.parameters(frame,owner.adapter._outputs[owner.cell_index(cell)].canonical_id)
		owner.test.check(p.mode == cell+9 and p.status == 1,"Every random family reaches its independent native renderer output")
	var source_count: int = owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated
	var previous: PackedFloat32Array
	var changes: int = 0
	var independent: bool = false
	for tick in range(360):
		owner.adapter._native.advance_shutters(owner.adapter._generation,1.0+tick/120.0)
		var values: PackedFloat32Array = owner.adapter._native.shutter_values()
		if not previous.is_empty() and previous != values: changes+=1
		for cell in range(6): Probe.check(owner,baseline,cell,values[owner.cell_index(cell)])
		independent = independent or values[owner.cell_index(4)] != values[owner.cell_index(5)]
		previous = values
	owner.test.check(independent,"Same-waveform multicell strobes retain distinct physical random timing")
	owner.test.check(changes>20,"Held random state continues a deterministic non-steady event sequence")
	owner.test.check(owner.runtime._native_visual_runtime.get_stats().source_programs_evaluated == source_count,"Random hold never evaluates new physical sources")
	owner.adapter._native.advance_shutters(owner.adapter._generation,2.83)
	var held: PackedFloat32Array = owner.adapter._native.shutter_values()
	owner.send({2:cells},4)
	owner.adapter._native.advance_shutters(owner.adapter._generation,2.83)
	owner.test.check(owner.adapter._native.shutter_values() == held,"Identical DMX republishing preserves random timing exactly")
	primary[0] = 0
	owner.send({0:primary},4.1)
	owner.adapter._native.advance_shutters(owner.adapter._generation,2.83)
	owner.test.check(owner.adapter._native.shutter_values() == held,"Dimmer blackout preserves every random phase")
	primary[0] = 255; primary[1] = 0
	owner.send({0:primary},4.2)
	owner.adapter._native.advance_shutters(owner.adapter._generation,2.83)
	owner.test.check(owner.adapter._native.shutter_values() == held,"Color blackout preserves the held random event sequence")
	primary[1] = 255
	owner.send({0:primary},4.3)
	owner.adapter._native.advance_shutters(owner.adapter._generation,2.83)
	for cell in range(6): Probe.check(owner,baseline,cell,held[owner.cell_index(cell)])
	cells[0] = 10; cells[1] = 0; cells[2] = 0; cells[3] = 10
	owner.send({2:cells},5)
	Probe.check(owner,baseline,0,1); Probe.check(owner,baseline,1,0)
	Probe.check(owner,baseline,2,0); Probe.check(owner,baseline,3,1)
	Probe.resources(owner,baseline)
	owner.adapter._native.advance_shutters(owner.adapter._generation,5.183)
	var before_rebind: PackedFloat32Array = owner.adapter._native.shutter_values()
	owner.app._visual_settings["beam_render_mode"] = 1
	owner.app._update_beam_renderer_mode(false)
	owner.adapter.refresh_renderer()
	owner.adapter._native.advance_shutters(owner.adapter._generation,5.183)
	owner.test.check(owner.adapter._native.shutter_values() == before_rebind,"Renderer replacement preserves every held random event position")
	await owner.close_scene()

# Typed random split-mode selection uses the same ModeMaster graph and never a generic selector's text.
static func split_random(owner: SceneTree, channel_master: bool = false, random_mode: bool = true) -> void:
	var flags: Array = ["--split"]
	if random_mode: flags.append("--random-modes")
	if channel_master: flags.append("--channel-master")
	await owner.open_scene(flags,8)
	var primary: PackedByteArray = owner.packet(); primary[0] = 255; primary[1] = 255
	var cells: PackedByteArray = owner.packet()
	for cell in range(8): cells[cell*3] = 10; cells[cell*3+1] = 255; cells[cell*3+2] = 51
	owner.send({0:primary,2:cells},0)
	var baseline: Array = Probe.capture(owner.adapter)
	for cell in range(4): cells[cell*3] = [20,120,160,200][cell]
	var frame: Dictionary = owner.send({2:cells},1)
	for cell in range(4):
		var p: Dictionary = Probe.parameters(frame,owner.adapter._outputs[owner.cell_index(cell)].canonical_id)
		owner.test.check(p.mode == cell+(9 if random_mode else 2) and p.status == (1 if random_mode else 0),"Typed split random ModeMaster selects all four waveforms without generic selector override")
	for now in [1.05,1.14,1.38,2.17,8.13]:
		owner.adapter._native.advance_shutters(owner.adapter._generation,now)
		var values: PackedFloat32Array = owner.adapter._native.shutter_values()
		for cell in range(4): Probe.check(owner,baseline,cell,values[owner.cell_index(cell)])
	if channel_master:
		var target: int = owner.adapter._outputs[owner.cell_index(0)].canonical_id
		var initial: Dictionary = Probe.parameters(frame,target)
		cells[0] = 60
		var changed: Dictionary = owner.send({2:cells},10)
		var mode: Dictionary = Probe.parameters(changed,target)
		owner.test.check(mode.mode == initial.mode and mode.activation > initial.activation and mode.phase == 0,"Another typed mode function starts a new activation even with identical waveform/frequency")
		cells[1] = 128
		changed = owner.send({2:cells},10.0375)
		var frequency: Dictionary = Probe.parameters(changed,target)
		owner.test.check(frequency.activation == mode.activation,"Frequency changes preserve the current mode activation and random sequence")
		owner.test.check_close(frequency.phase,0.375,0.0001,"Split frequency change integrates previous 10 Hz phase")
	await owner.close_scene()

# A channel-wide selector cannot bypass a typed candidate's additional activation dependencies.
static func conditional_mode_guard(owner: SceneTree) -> void:
	await owner.open_scene(["--split","--channel-master","--conditional-mode"],8)
	var primary: PackedByteArray = owner.packet(); primary[0] = 255; primary[1] = 255
	var cells: PackedByteArray = owner.packet()
	for cell in range(8): cells[cell*3] = 10; cells[cell*3+1] = 255; cells[cell*3+2] = 51
	owner.send({0:primary,2:cells},0)
	var baseline: Array = Probe.capture(owner.adapter)
	cells[0] = 60
	var frame: Dictionary = owner.send({2:cells},1)
	var p: Dictionary = Probe.parameters(frame,owner.adapter._outputs[owner.cell_index(0)].canonical_id)
	owner.test.check(p.mode == -1 and p.status == 2,"Additional unresolved mode activation chains remain diagnosed instead of ordinary flashing")
	Probe.check(owner,baseline,0,1)
	await owner.close_scene()
