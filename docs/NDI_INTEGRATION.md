# Optional NDI video reception (design only)

Status: planned. No SDK download, runtime, build option or video functionality
is introduced here. [Compliance gates](NDI_COMPLIANCE.md) precede SDK use and
distribution. Start with official Standard SDK receive/discovery, not sending.

## Ownership and runtime

Native C++ owns discovery, receive workers, frame lifetimes, format conversion
and bounded queues. Godot owns textures, materials and scene presentation;
workers never mutate scene nodes. Expose a transport-neutral video source
contract (source identity, resolution, pixel format, timestamps, state and
latest-frame acquisition). A mock provider supports tests without NDI.
Do not couple this to the DMX or fixture semantic pipeline.

Builds without NDI must work on all existing platforms. An optional adapter
dynamically loads an approved runtime from a deterministic app-local location,
using the SDK-documented API and platform-specific safe library search rules.
No implicit system search or loading before authorized opt-in. Version/API
mismatch or missing files must fail gracefully without affecting MVR/GDTF/DMX.

Initialize only when enabled and needed; stop discovery and workers on disable
or shutdown. Share one receiver/texture per source across scene surfaces, reuse
buffers, bound queues (latest-frame policy), and avoid blocking the render thread.
Measure idle load, FPS, latency, dropped frames and resource use at 1080p60 and
multiple streams. Validate color/alpha, resolution change and reconnection.

Video routing is Peraviz project data unless an official MVR/GDTF representation
is verified. Preserve canonical MVR/GDTF and unknown fields; document any
nonstandard association in PVZ/project state and do not invent standard fields.

## Packaging proposal (Windows first)

Current Inno Setup script: [peraviz.iss](../packaging/windows/peraviz.iss).
It has a GPL LicenseFile and a recursive SourceDir file rule. That rule would
copy an NDI payload unconditionally; future packaging must explicitly exclude
it from the core copy and stage it only under the approved optional component.
The current Windows CI packages remain core-only, copy the prepared license
notices, and reject an app-local NDI payload or known NDI runtime filenames.
This is a preliminary filesystem guard, not a full dependency/PCK audit.
See [packaging inputs](../packaging/ndi/README.md).
Existing portable ZIP export must remain core-only unless a separately reviewed
NDI-bearing distribution implements the same legal and consent requirements.

Proposed app-local layout (names illustrative; derive exact files from approved SDK):

    Peraviz/
      Peraviz.exe
      bin/peraviz_native.dll
      LICENSE.txt
      LICENSE-NDI-EXCEPTION.txt
      THIRD_PARTY_NOTICES.md
      components/ndi/
        <approved runtime files>
        NDI-EULA.txt
        Processing.NDI.Lib.Licenses.txt
        <other approved notices/files>

No NDI binaries or SDK are committed to Git. A controlled packaging job may stage
only approved redistributable files after compliance gates pass. Windows/Linux/
macOS each need platform-specific packaging and license verification.

## User consent and lifecycle

- Offer optional NDI support in the installer; no prechecked acceptance.
- Display complete approved NDI end-user terms before installing or loading NDI,
  with a distinct affirmative action; no acceptance of proprietary terms required
  for core installation, launch, source access, modifications or redistribution.
- Refusal or cancellation skips NDI without blocking core installation. Do not
  load any previously installed NDI provider after refusal; remove stale app-owned
  optional files on an upgrade when the user opts out.
- Store local consent evidence (agreement identifier/hash, component version,
  explicit decision and timestamp) without telemetry or unnecessary identity data.
  A missing, invalid or superseded acceptance disables the official provider.
  Determine per-user vs machine-wide semantics with the approved agreement.
- Silent/unattended install defaults to core-only; any NDI opt-in must use an
  explicit approved acceptance mechanism tied to the exact terms, not a generic
  silent flag. Portable builds must not bypass consent.
- Allow later opt-in and component installation through a reviewed flow, with no
  manual runtime hunt and no network download without informed user action.
- Offer disable/removal; release resources, preserve project routing as unavailable
  and do not remove shared runtimes of unrelated applications.
- This consent gate governs the distributed NDI provider, not users' GPL rights.
  No DRM, account requirement or mandatory online validation for the core.

## Verification for later PRs

Test clean core-only and approved NDI-enabled builds; accept/decline/cancel;
missing/corrupt runtime; upgraded agreement; silent core-only install;
portable and multi-user paths; disable/uninstall/reinstall; stale library removal;
no NDI initialization or network discovery on refusal; no core regression.
Verify artifact allowlists, notices, source availability and hashes.
Do not claim NDI support in current release notes or UI until implemented and tested.
