# Peraviz Runtime Storage Policy

Peraviz stores runtime-only extracted archive assets below one application-owned root in the operating-system temporary directory:

```text
<SystemTemp>/Peraviz/
  sessions/<session-id>/
    operations/
    cache/v1/
```

Persistent user data, projects, downloaded fixtures, and Godot `user://` data remain outside this policy and must not be deleted by runtime cleanup.

Operation workspaces are move-only RAII directories. They are deleted recursively on success, failure, cancellation, or exception unless ownership is explicitly transferred to a shared runtime lease.

Scene/session resources use shared leases. MVR and GDTF assets extracted from a source archive remain available while the loaded `SceneModel`, copied model snapshots, or any other owner still references them. The final lease release removes the directory; raw cache paths are compatibility strings only and are not authoritative ownership.

Session caches are regenerable and versioned with `cache/v1`. They are scoped to the current process session instead of being persistent cross-run caches, so failed or erased entries release their extracted files and clean shutdown can remove the session directory. The cache key includes the source filename and a content hash to avoid reusing stale extracted files within the session.

Cleanup is containment-checked before deletion. Runtime storage refuses to remove paths that are not lexically inside the Peraviz runtime root and logs cleanup failures instead of throwing from destructors.

Archive entries continue to use the native ZIP archive normalization path and are written under sanitized relative cache paths, preserving root-level MVR/GDTF compatibility while avoiding direct writes from archive names to arbitrary filesystem locations.
