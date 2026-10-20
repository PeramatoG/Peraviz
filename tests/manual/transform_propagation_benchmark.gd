extends SceneTree

# Synthetic CPU probe, not the canonical scene or a GPU/FPS acceptance result.
# Compare normal / mechanical-only / active-only using application arguments.
const Controller = preload("res://scripts/runtime/presentation_transform_controller.gd")

class Anchor extends SpotLight3D:
	var notifications: int = 0
	func _ready() -> void: set_notify_transform(true)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSFORM_CHANGED: notifications += 1

func _init() -> void: call_deferred("run")

func run() -> void:
	var active_count: int = 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--active="): active_count = clampi(int(arg.trim_prefix("--active=")), 0, 1095)
	var scene := Node3D.new()
	root.add_child(scene)
	var controller := Controller.new()
	controller.mode = Controller.from_arguments(OS.get_cmdline_user_args())
	var axes: Array[Node3D] = []
	var anchors: Array[Anchor] = []
	var mesh := BoxMesh.new()
	for fixture in range(43):
		var pan := Node3D.new()
		scene.add_child(pan)
		var tilt := Node3D.new()
		pan.add_child(tilt)
		axes.append(pan)
		axes.append(tilt)
		for output in range(26 if fixture < 20 else 25):
			var source := Node3D.new()
			source.position = Vector3(output * 0.05, 0.0, 0.0)
			tilt.add_child(source)
			var anchor := Anchor.new()
			source.add_child(anchor)
			anchor.light_energy = 0.0
			anchors.append(anchor)
			var beam := MeshInstance3D.new()
			beam.mesh = mesh
			beam.visible = anchors.size() <= active_count
			anchor.add_child(beam)
			var binding = controller.bind(anchor, anchors.size(), anchors.size() - 1)
			controller.set_active(binding, beam.visible, false, false)
	# Drain setup notifications before measuring the recurring motion cost.
	for frame in range(10): await process_frame
	for anchor in anchors: anchor.notifications = 0
	var started: int = Time.get_ticks_usec()
	var mechanical_us: int = 0
	var presentation_us: int = 0
	for frame in range(600):
		var before: int = Time.get_ticks_usec()
		for index in range(axes.size()):
			if index % 2: axes[index].rotation_degrees.x = frame * 0.21
			else: axes[index].rotation_degrees.y = frame * 0.33
		mechanical_us += Time.get_ticks_usec() - before
		before = Time.get_ticks_usec()
		controller.synchronize()
		presentation_us += Time.get_ticks_usec() - before
		await process_frame
	var notifications: int = 0
	for anchor in anchors: notifications += anchor.notifications
	print("[transform-probe] ", JSON.stringify({"mode": controller.mode, "outputs": anchors.size(), "active": active_count,
		"frames": 600, "elapsed_us": Time.get_ticks_usec() - started, "mechanical_us": mechanical_us,
		"presentation_us": presentation_us, "anchor_transform_notifications": notifications,
		"note": "CPU microbenchmark; elapsed includes engine pacing; no canonical FPS or GPU claim"}))
	controller.clear()
	scene.free()
	await evaluate_rid_dispatch()
	quit()

# Separate resource authorities: each backend owns different objects and frees
# its resources explicitly. Never override the transform RID of a live Node.
func evaluate_rid_dispatch() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var nodes: Array[MeshInstance3D] = []
	var rids: Array[RID] = []
	var mesh := BoxMesh.new()
	for index in range(1095):
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.visible = false
		holder.add_child(node)
		nodes.append(node)
		var rid: RID = RenderingServer.instance_create2(mesh.get_rid(), holder.get_world_3d().scenario)
		RenderingServer.instance_set_visible(rid, false)
		rids.append(rid)
	await process_frame
	for backend in ["node", "rid"]:
		var started: int = Time.get_ticks_usec()
		for frame in range(600):
			var pose := Transform3D(Basis(Vector3.UP, frame * 0.01), Vector3(frame * 0.03, 0.0, 0.0))
			if backend == "node":
				for node in nodes: node.global_transform = pose
			else:
				for rid in rids: RenderingServer.instance_set_transform(rid, pose)
		print("[transform-rid-dispatch] backend=%s transforms=657000 dispatch_us=%d" % [backend, Time.get_ticks_usec() - started])
	for rid in rids: RenderingServer.free_rid(rid)
	holder.free()
	print("[transform-rid-dispatch] Dispatch only; excludes deferred notifications, optical child composition, projector alignment and GPU execution. Production retains one Node carrier authority.")
