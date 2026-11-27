# Reserved NDI packaging contract (inactive)

No runtime, SDK, vendor agreement or redistribution approval is included.
The current Windows build and portable archive are core-only. This directory
contains only preparation documents; do not copy it wholesale into packages.

## Inputs for an approved future build

Keep SDK files outside the source tree and public CI. Stage only specifically
authorized redistributables in an isolated staging directory (for example
`out/ndi/approved/windows-x64/`, which is ignored by Git). Do not embed them in
the Godot PCK or package them via a recursive SDK copy.

| Input | Required content |
| --- | --- |
| Runtime files | Exact per-platform approved file list, not a generic SDK folder. |
| NDI-EULA.txt | Final approved end-user agreement, separate from GPL. The adjacent template is never valid for installation. |
| Processing.NDI.Lib.Licenses.txt | Unmodified notices supplied alongside the selected SDK binaries (or documented successor). |
| Other notices | All additional applicable copyright, trademark, codec and third-party terms. |
| Release evidence | SDK version, agreement revision/hash, approved scope, platform, file names and SHA-256 hashes, current compatibility check, rights-holder exception adoption and legal approval reference. |

See [NDI distribution documentation](https://docs.ndi.video/all/developing-with-ndi/sdk/software-distribution),
[third-party rights](https://docs.ndi.video/all/developing-with-ndi/sdk/3rd-party-rights)
and [Peraviz compliance gates](../../docs/NDI_COMPLIANCE.md).

## Later Windows installer change

- Use a separate, explicitly enabled NDI payload input, never the core export
  directory. Keep the core-only ZIP and default installer available.
- Copy only approved payload files to `{app}\components\ndi` after explicit
  consent to the complete, versioned EULA. Keep the GPL license page independent.
- Keep the template and evidence with confidential information out of artifacts.
- Default unattended installations to core-only. Handle updates, withdrawal,
  stale files, local consent records and removal as described in the
  [integration design](../../docs/NDI_INTEGRATION.md).
- Run the full packaging and runtime consent tests before enabling NDI artifacts.

Nothing here accepts the vendor SDK agreement or authorizes its use. The
maintainer must review the selected terms and obtain the necessary permissions.
