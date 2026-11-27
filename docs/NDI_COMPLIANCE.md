# NDI compliance and release gate

**Status: proposed architecture; SDK use and NDI-bearing distribution are not
approved by this document.** Reviewed 2026-11-27; implementation preparation updated 2026-11-28. The core remains GPLv3.
This is an engineering compliance record, not a legal opinion or an NDI
agreement. The project owner must review and accept any actual SDK agreement.

## Decision

Use the official Standard SDK for optional discovery and receive on general-purpose
desktop systems. Prefer a self-contained installer with an app-local authorized
runtime. Do not make the core subject to an NDI EULA. Sending, embedded,
fixed-purpose appliances and restricted hosted environments are outside this phase.
A GPL-only build must remain fully available and independently reproducible.

## Public source basis

- [NDI Standard SDK license agreement](https://downloads.ndi.tv/SDK/NDI_SDK/NDI%20SDK%20License%20Agreement.pdf)
- [NDI licensing](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing)
- [Software distribution](https://docs.ndi.video/all/developing-with-ndi/sdk/software-distribution)
- [Dynamic loading](https://docs.ndi.video/all/developing-with-ndi/sdk/dynamic-loading-of-ndi-libraries)
- [Third-party rights](https://docs.ndi.video/all/developing-with-ndi/sdk/3rd-party-rights)
- [GPLv3, especially sections 1, 6, 7, 10 and 12](https://www.gnu.org/licenses/gpl-3.0.html)
- [FSF GPL FAQ: linking exceptions](https://www.gnu.org/licenses/gpl-faq.html)

The public PDF was reviewed, but the exact terms inside a selected downloaded SDK
and its runtime have not been inspected or accepted. Public web documentation may
change; record the actual agreement revision, SDK version, provenance and SHA-256
in release evidence. Do not assume old public documents control a newer SDK.

## Rights audit

Baseline main commit: 3c51e6648ad0fcccb1959459c5b3554361527804. The GitHub commit listing previously reviewed
contained 507 commits from 2026-05-18 onward, all associated with PeramatoG;
no other account was identified in that listing. This is author metadata, not
proof of ownership or an assignment of copyright. LICENSE.txt and README.md
identify GPLv3; no NDI exception existed at the baseline. The prepared exception is now available for explicit adoption, but no blanket grant is asserted. No GitHub release was
listed, but the repository is public and has a fork; prior GPL grants remain valid.

The native manifest names libzip, tinyxml2 and mdns, and CMake uses godot-cpp.
The repository also includes separate UI icon and shader notices. The original MIT designation of the UI icons is retained, with its full license text restored. The
[preliminary inventory](../THIRD_PARTY_NOTICES.md) records known evidence and gaps.
Before adopting the exception, audit imported code (especially shared Perastage
code), generated/copied code, all contributor/co-author provenance and applicable
third-party licenses. Obtain permission from all relevant copyright holders or
exclude/replace affected GPL-only code. An author account or maintainer role does
not establish these rights. No full file-by-file provenance audit was completed.

## Contract review and open issues

| Reference | Compliance question / required evidence |
| --- | --- |
| 1(b), 2(a), 3(b), 3(j) | Confirm desktop visualizer and professional theatre use, receive/discovery scope and written purpose; clarify any limits on future sending. |
| 2(b), 3(h) | Confirm latest-version and complete-interoperability duties, including existing release downloads, update cadence and intended receive-only capability. |
| 2(d), 3(a) | Confirm file-specific redistribution and confidentiality; never publish confidential samples, SDK docs or support material. |
| 3(d), 3(i), GPLv3 7/10/12 | Obtain written NDI confirmation that required downstream EULA, protocol restrictions and third-party developer obligations apply only to NDI-bearing use/distribution and do not restrict independent GPL code, forks or GPL-only builds. A click-through and linking exception alone cannot resolve incompatible obligations. |
| 2(g), 10 | Obtain appropriate legal review of enforceability, mandatory local law and the Swedish-law/jurisdiction provision before accepting. |
| 3(c), 3(f), 3(g) | Export compliance, current brand rules, attribution and copyright notices; no implied certification. |
| 4, 5, 7–9 | Defect reporting, updates, indemnity, liability, termination and withdrawal plan. Confirm continued distribution rights for already shipped versions and treatment of MIT headers on termination. |
| Third-party rights | Obtain actual redistributable notices and verify codec/patent rights (including H.264, H.265 and AAC where used). Do not assume receive-only removes obligations. |

The public distribution guide describes app-bundled binaries and a redistributable
installer, conditional on appropriate terms and attribution. It also identifies
MIT headers eligible for open-source distribution. Neither statement by itself
establishes GPL compatibility or permits unrestricted SDK redistribution.

## Adopt the prepared exception before integration

The text in [LICENSE-NDI-EXCEPTION.txt](../LICENSE-NDI-EXCEPTION.txt) is ready for rights-holder review and adoption. It is not a blanket relicensing. Once ownership is verified, record the owner approval and place the following notice in the relevant source files, preserving their existing copyright and GPL notices:

    Additional permission under GNU GPL version 3, section 7:
    see LICENSE-NDI-EXCEPTION.txt at the repository root.

Record the covered paths, approval commit and any excluded third-party code. For new files, obtain express grant from contributors who own or can license the relevant rights. A copyright-holder may decline or remove the permission as allowed by GPLv3. No requirement for acceptance of NDI terms applies to contributions to the GPL-only core.

This adoption can occur before any SDK is introduced. It does not grant rights to NDI software or resolve its downstream contract. The future integration PR must verify coverage of every relevant GPL component; do not rely on the presence of the exception file alone.

## Required release gates (all initially open)

- [ ] Rights audit signed off and linking exception expressly adopted by authorized
  copyright holders; applicable source-file notices, scope and approval record verified.
- [ ] Written NDI response / agreement confirms intended use and resolves the
  downstream restrictions and release/version questions above; owner accepts it.
- [ ] Selected SDK and runtime agreements reviewed; final user-facing terms approved
  for the specific release, with no additional conditions on GPL-only code.
- [ ] Exact runtime file allowlist, platform/architecture, version, hash, origin,
  third-party notices and codec/patent review completed.
- [ ] Only explicitly permitted files staged; no full SDK, confidential materials
  or credentials in Git, public logs, caches, PR artifacts or AI tools.
- [ ] Corresponding Source, build/install scripts and required third-party notices
  offered for every distributed GPL build; separate core-only artifact verified.
- [ ] Installer, silent installs, portable builds, updates, refusal, removal and
  multi-user scenarios pass the acceptance tests in [integration](NDI_INTEGRATION.md).
- [ ] Maintainer checks the current SDK/license before each NDI-bearing release;
  release pipeline fails closed if approval evidence is missing or outdated.

Until these gates are satisfied, public build/release jobs must remain NDI-free.
Do not download or accept an SDK agreement on another person's behalf. Keep private
contract evidence outside public Git, with only a non-confidential status/reference
in the release record. If terms change or rights terminate, stop NDI-bearing
distribution and remove affected artifacts as legally required; the GPL-only
release path remains available.

## Written questions for NDI

Describe Peraviz as a GPLv3 desktop lighting/stage visualizer receiving live video
from media servers into virtual screens/projections. Ask for confirmation of:
Standard SDK coverage for professional/commercial desktop use; app-local runtime
bundling and user acceptance; downstream scope of 3(d)/3(i) for GPL code and forks;
receive-only compatibility and 2(b) update duties; codec rights; permitted files,
notices, and any registration or separate written agreement. No request has been
sent and no response has been obtained by this PR.

## Prepared packaging inputs

The [NDI packaging contract](../packaging/ndi/README.md) defines the future app-local payload, license text and release evidence. The [EULA template](../packaging/ndi/NDI-EULA.template.txt) is a drafting checklist, not an agreement for acceptance. Use the exact approved end-user terms and the vendor-supplied `Processing.NDI.Lib.Licenses.txt` (or its documented successor) for the selected SDK. Never show or ship the template as a binding EULA. The public SDK developer agreement alone is not a substitute for the approved end-user terms.
