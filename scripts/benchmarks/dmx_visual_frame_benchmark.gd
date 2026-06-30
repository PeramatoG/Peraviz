extends RefCounted
class_name DmxVisualFrameBenchmark

const FIXTURE_COUNT: int = 80
const STRIDE: int = 24

func run_mass_toggle_apply_smoke(iterations: int = 20) -> Dictionary:
	var frame := PackedFloat32Array()
	frame.resize(1 + (FIXTURE_COUNT * STRIDE))
	frame[0] = float(FIXTURE_COUNT)
	var base: int = 1
	for fixture_id in range(1, FIXTURE_COUNT + 1):
		frame[base] = float(fixture_id)
		frame[base + 1] = 0.0
		frame[base + 2] = 1.0
		frame[base + 15] = 200.0
		frame[base + 16] = 200.0
		frame[base + 17] = 12.5
		frame[base + 18] = 25.0
		frame[base + 19] = 1.0
		frame[base + 20] = 1.0
		frame[base + 21] = 1.0
		frame[base + 22] = 20.0
		frame[base + 23] = 4.0
		base += STRIDE

	var worst_usec: int = 0
	var total_usec: int = 0
	for _i in range(max(iterations, 1)):
		var start_usec: int = Time.get_ticks_usec()
		var fixture_count: int = int(frame[0])
		var read_base: int = 1
		for _fixture_index in range(fixture_count):
			var _fixture_id: int = int(frame[read_base])
			var _dimmer_norm: float = frame[read_base + 2]
			var _beam_energy: float = frame[read_base + 15]
			var _beam_angle: float = frame[read_base + 18]
			read_base += STRIDE
		var elapsed_usec: int = max(Time.get_ticks_usec() - start_usec, 0)
		total_usec += elapsed_usec
		worst_usec = max(worst_usec, elapsed_usec)
	return {
		"fixtures": FIXTURE_COUNT,
		"iterations": max(iterations, 1),
		"average_usec": total_usec / max(iterations, 1),
		"worst_usec": worst_usec,
	}
