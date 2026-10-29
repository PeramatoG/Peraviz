extends RefCounted

# Forward native decisions at setup, without adding a Godot semantic fallback.
static func attach(summary: Dictionary, diagnostics: Array) -> void:
	summary["compile_diagnostics"] = diagnostics
	var subjects: Dictionary = {}
	var counts: Dictionary = {}
	for issue: Dictionary in diagnostics:
		var code: String = str(issue.get("code",""))
		if code not in ["PVZ-MVR-DMX-PATCH-UNSUPPORTED","PVZ-GDTF-DMX-PATCH-UNSUPPORTED"] and not code.begins_with("PVZ-SHUTTER-"): continue
		counts[code] = int(counts.get(code,0)) + 1
		if not subjects.has(code): subjects[code] = []
		if subjects[code].size() < 3: subjects[code].append(str(issue.get("subject","")))
	for code in counts:
		if str(code).begins_with("PVZ-SHUTTER-"):
			push_warning("%s: %d unsupported shutter function/context(s). Examples: %s. Details: native setup compile_diagnostics." % [code,counts[code],str(subjects[code])])
			continue
		push_warning("%s: DMX bindings withheld for %d fixture(s); source geometry retained. Examples: %s. Details: native setup compile_diagnostics." % [code,counts[code],str(subjects[code])])
