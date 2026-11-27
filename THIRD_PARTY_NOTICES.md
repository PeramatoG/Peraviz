# Third-party notices and inventory

This is a preliminary source-level inventory, not a complete distribution
notice bundle. The exact versions, copyright notices, transitive dependencies,
license texts and source obligations must be recorded for each shipped artifact.
Peraviz's license is [GPLv3](LICENSE.txt).

| Component | License / evidence | Distribution action |
| --- | --- | --- |
| Godot engine and godot-cpp | MIT; upstream [Godot license](https://godotengine.org/license/), [godot-cpp](https://github.com/godotengine/godot-cpp) | Include notices for the exact engine/export templates and pinned bindings, including bundled third parties. |
| tinyxml2 | zlib; [upstream](https://github.com/leethomason/tinyxml2) | Verify selected revision and retain notices. |
| libzip | BSD-3-Clause; [upstream](https://libzip.org/) | Retain notices; enumerate compression/crypto dependencies actually linked. |
| mdns | Verify the resolved vcpkg port's source/license; [manifest](native/vcpkg.json) | Record exact upstream, revision and license before publishing binaries. |
| zlib and other transitive dependencies | Determine from build/package graph | Record versions, licenses, notices and any source obligations. |
| UI icons | [Local notice](assets/ui/LICENSE.txt) states MIT, but points to the GPL text | Resolve the missing/incorrect MIT license reference with the rights holder before release; do not silently reinterpret it. |
| Custom footprint shader references | [Local notice](scripts/shaders/custom_footprint.LICENSE.txt) records CC0 and MIT references | Retain local attribution and MIT notice. |
| Fixture/scene test data, artwork and imported resources | Per-file provenance not established by this review | Audit origin and redistribution permissions. |

## NDI (planned, not present)

NDI is proprietary third-party software. No SDK, runtime, or NDI headers are
introduced by this change. If approved, keep the SDK-authorized MIT headers
with their original notices and the runtime's official notices and end-user
terms separately. Do not use this inventory as a substitute for those terms.

NDI® is a registered trademark of Vizrt NDI AB (verify the exact current
required trademark and copyright notices against the selected SDK).
No affiliation, certification or endorsement is claimed.

See [NDI compliance](docs/NDI_COMPLIANCE.md) for the distribution gate.
