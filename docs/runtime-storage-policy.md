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

Session caches are regenerable and versioned with `cache/v1`. They are scoped to the current process session instead of being persistent cross-run caches, so failed or erased entries release their extracted files and clean shutdown can remove the session directory. The cache key uses an ASCII-only 128-bit non-cryptographic content fingerprint and byte length. Equivalent archives share a lease regardless of their source filename; different content gets a new generation. The original UTF-8 source path is retained separately in scene metadata and load diagnostics. This fingerprint is a cache identity, not an integrity/security check.

Cleanup is containment-checked before deletion. Runtime storage refuses to remove paths that are not lexically inside the Peraviz runtime root and logs cleanup failures instead of throwing from destructors.

Archive entries continue to use the native ZIP archive normalization path and are written under sanitized relative cache paths, preserving root-level MVR/GDTF compatibility while avoiding direct writes from archive names to arbitrary filesystem locations.

Static gobo media uses the same RAII/content-lease ownership. Resources are installed for the active scene generation and consumed through the native static-selection and `NativeGoboResourceRegistry` path; repeated fixtures share the retained content cache. Replacing the scene releases the old generation only after its final owner releases it. Fixture-binding dictionaries and control-offset caches that remain in compatibility code are transitional and are not authoritative resource ownership for the production static gobo path.

## Import resource resolution

Native path strings and XML/ZIP metadata use UTF-8. Godot receives these strings through explicit UTF-8 decoding. C++17 readers open `std::filesystem::u8path` paths; embedded GDTF XML is read through a native-path stream and parsed from bytes. The ASCII cache identifier supplements these conversions; resource filenames and Unicode temporary/source parent directories remain supported.

ZIP lookups retain the original entry spelling for libzip reads after separator and `./` normalization. Unsafe absolute/traversal names, duplicate normalized names and ASCII case collisions are rejected. Sanitized extraction-path collisions are also rejected, preventing unrelated resources from sharing an output file. Companion textures and binary dependencies retain their relative directories and are extracted once per model directory. The archive handle/index remains scoped to the existing cache owner.

Exact normalized model paths take priority. ASCII case-insensitive lookup and a unique nested basename are compatibility fallbacks, not MVR/GDTF requirements. An explicit extension is respected; an ambiguous basename fails rather than selecting an unrelated same-stem model. Standard extensionless GDTF model names retain the existing format preference. No archive or incoming identifier is rewritten.

Renderer diagnostics report unique asset failures once, retain their reason in the runtime asset cache, and summarize successful asset instances, failed asset instances and fallback decisions per scene build. Resolution failures retain their original resource reference on the native node. A node count does not establish mesh success. The lifetime smoke test requires actual surfaces for every expected embedded model, including repeated fixture instances.

The Perastage reference uses explicit filesystem conversions, package path remapping and collision checks. Peraviz keeps its existing lazy cache/lease architecture and now retains original ZIP spellings and rejects ambiguous identities. It does not adopt Perastage's long-path remapping workspace. Very long paths remain subject to platform/filesystem limits; extraction failures are reported. Existing 3DS winding, units and coordinate mapping are unchanged. The reader validates chunk/payload bounds, finite vertices and per-object indices, and distinguishes missing/open/invalid/empty data. Existing merged-material presentation and unsupported 3DS local-transform/keyframe variations are unchanged; arbitrary legacy encodings in 3DS string fields are not inferred.
