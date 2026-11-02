extends RefCounted

# Reuses public production fixtures; diagnostics describe cold rejection, never force admission.
static func run(owner: SceneTree) -> void:
	await owner.open_scene(["--shared"],128)
	owner.send(owner.values_for(128,0,true,10),0)
	var adapter: RefCounted = owner.adapter
	owner.test.check(not adapter._lens_batches.counts().gpu_lens_admission_trace_enabled,"Trace-off stores no detailed lens rejection summary")
	owner.runtime.set_performance_trace_enabled(true)
	owner.app._fixture_light_apply_service.set_performance_trace_enabled(true)
	adapter.refresh_renderer()
	var accepted: Dictionary = adapter._lens_batches.counts()
	owner.test.check(accepted.gpu_lens_admission_trace_enabled and accepted.gpu_lens_policy == "eligible" and accepted.allocated_lens_gpu_instances == 128,"Shared aggregate membership does not veto compatible lens admission")
	var index: int = adapter._lens_batches.members.keys()[0]
	var source_mesh: MeshInstance3D = adapter._binding_records[index].lens_material_targets[0].mesh
	var original_resource: Mesh = source_mesh.mesh
	source_mesh.mesh = CylinderMesh.new()
	adapter.refresh_renderer()
	var primitive: Dictionary = adapter._lens_batches.counts()
	owner.test.check(primitive.gpu_lens_rejections.get("mesh_type",0)>0 and primitive.gpu_lens_mesh_type_rejections.get("CylinderMesh",0)>0 and not adapter._lens_batches.members.has(index),"Primitive lenses report their unsupported mesh class and retain exact fallback")
	source_mesh.mesh = original_resource
	adapter.refresh_renderer()
	var material: StandardMaterial3D = adapter._outputs[index].materials[0].material
	var roughness: float = material.roughness
	material.roughness = 0.5
	adapter.refresh_renderer()
	var rejected: Dictionary = adapter._lens_batches.counts()
	owner.test.check(rejected.gpu_lens_rejections.get("material_options",0)>0 and rejected.gpu_lens_material_option_rejections.get("roughness",0)>0,"Cold diagnostic identifies the exact unsupported material option")
	owner.test.check(not adapter._lens_batches.members.has(index),"Diagnostic does not force an ineligible material into a GPU batch")
	material.roughness = roughness
	adapter.refresh_renderer()
	var mesh: MeshInstance3D = adapter._binding_records[index].lens_material_targets[0].mesh
	var original: Vector3 = mesh.scale
	mesh.scale = original*Vector3(2,1,1)
	adapter.refresh_renderer()
	owner.test.check(adapter._lens_batches.counts().gpu_lens_rejections.get("nonconformal_or_reflected_transform",0)>0 and not adapter._lens_batches.members.has(index),"Nonuniform geometry retains its exact reference rendering and reports the rejection")
	mesh.scale = original
	OS.set_environment("PERAVIZ_GPU_LENSES","0")
	adapter.refresh_renderer()
	var disabled: Dictionary = adapter._lens_batches.counts()
	owner.test.check(disabled.gpu_lens_policy == "explicit_disabled" and disabled.allocated_lens_gpu_instances == 0,"A policy-disabled zero-batch scene is distinguished from geometry/material rejection")
	OS.unset_environment("PERAVIZ_GPU_LENSES")
	adapter.refresh_renderer()
	owner.test.check(adapter._lens_batches.counts().allocated_lens_gpu_instances == 128,"Held-state reinstall restores compatible admission without editing source geometry")
	print("TEMPORAL_LENS_ADMISSION ",JSON.stringify({"accepted":accepted,"material_rejection":rejected,"disabled":disabled}))
	await owner.close_scene()
