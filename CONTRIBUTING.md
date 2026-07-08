# Contributing to Peraviz

Thank you for taking the time to help improve Peraviz.

Peraviz is an open-source real-time 3D DMX visualizer based on MVR and GDTF workflows. It is developed alongside Perastage, but its main goal is different: Peraviz should load a scene, interpret fixture data, receive live control data, and render the result as efficiently, accurately, and predictably as possible.

You do not need to be an experienced developer to contribute. Bug reports, real-world test files, performance feedback, fixture compatibility notes, documentation improvements, translations, and usability feedback are all valuable.

## Ways to contribute

You can help Peraviz in several ways:

- Report bugs or crashes.
- Report performance or latency problems.
- Suggest new features or improvements.
- Test the application with real MVR, GDTF, fixture, truss, scene object, Art-Net, sACN, and DMX data.
- Improve documentation.
- Help with translations or clearer wording.
- Submit code changes through pull requests.
- Share screenshots, logs, profiler data, or simplified example files when possible.

## Before opening an issue

Before creating a new issue, please check whether a similar one already exists.

If it does, feel free to add extra information instead of opening a duplicate. Extra details are especially useful when they come from a different operating system, GPU, fixture file, MVR exporter, lighting console, network configuration, or Godot version.

## Reporting bugs

When reporting a bug, please include as much useful information as possible.

A good bug report usually includes:

- The Peraviz version or commit you are using.
- Your operating system.
- Your GPU and graphics driver version, if the issue may be visual or performance-related.
- The Godot version used, if you built or ran the project from source.
- What you were trying to do.
- What happened instead.
- The steps needed to reproduce the issue.
- Screenshots or screen recordings, if they help explain the problem.
- Any crash report, log file, console output, or error message.
- A simplified MVR, GDTF, or project file, if you are allowed to share it.

If you cannot share the original file because it belongs to a real production, venue, client, designer, manufacturer, or third party, that is completely fine. A simplified test file that reproduces the same problem is also very helpful.

Please do not upload private, confidential, copyrighted, or client-owned show files unless you have permission to share them publicly.

## Reporting performance or latency problems

Peraviz is intended to become a low-latency real-time visualizer, so performance reports are especially valuable.

When reporting a performance issue, please describe:

- Whether the problem concerns FPS, input latency, import time, render quality, memory usage, CPU usage, GPU usage, network processing, or something else.
- The approximate number of fixtures, meshes, universes, patched DMX addresses, and repeated models involved.
- Whether the problem happens with live Art-Net, sACN, or DMX input, manual fixture testing, scene loading, camera movement, or all of them.
- Whether the same scene is smooth when live input is disabled.
- Your CPU, GPU, RAM, operating system, graphics driver, and Godot version.
- Any profiler capture, frame-time log, packet timing, or before-and-after measurement you can provide.

Performance reports do not need to be perfect. Rough numbers and clear reproduction steps can still help identify the bottleneck.

## Suggesting features

Feature requests are welcome.

When suggesting a feature, please describe:

- What problem it would solve.
- How you imagine it working.
- Whether it relates to MVR import, GDTF parsing, live DMX, Art-Net, sACN, fixture attributes, beam rendering, gobos, prisms, color, atmosphere, camera workflow, UI, performance, or another area.
- Whether another application already implements something similar.

The more context you provide, the easier it is to understand the real use case behind the request.

## Code contributions

Code contributions are welcome.

For large or architectural changes, it is usually better to open an issue or discussion first. This helps avoid duplicated work and confirms whether the proposed direction matches the current project architecture.

For small fixes, documentation improvements, tests, or simple corrections, you can open a pull request directly.

Every code contribution must follow the active repository instructions in `AGENTS.md`. When a task is explicitly declared as an architectural replacement, legacy removal, or breaking internal migration, the architectural replacement rules in that file take precedence over the general preference for small, compatibility-preserving changes.

## Development direction

Peraviz has an important native C++ side and an important Godot side.

The intended ownership is:

- Native C++ owns heavy and high-frequency data processing.
- Native C++ owns GDTF parsing, validation, compilation, DMX resolution, physical-state calculation, interpolation, dirty-state generation, and render-data preparation.
- Godot focuses on graphics, scene presentation, UI, cameras, materials, meshes, beams, atmosphere, renderer configuration, and renderer-facing resource updates.
- Godot should receive compact, already-resolved structural data and render-ready live updates.
- Godot should not repeatedly parse or reinterpret raw DMX, GDTF ChannelFunctions, ChannelSets, ModeMaster rules, attribute names, or physical ranges during live playback.

The C++ and Godot boundary should remain narrow, versioned, schema-driven, batched, and based on stable identifiers.

## Compatibility policy

Peraviz distinguishes between public compatibility and internal implementation compatibility.

Public compatibility includes:

- Supported MVR and GDTF files.
- Supported Art-Net, sACN, and DMX behavior.
- Documented project files and user workflows.
- Supported operating systems and build environments.
- External semantic contracts shared with Perastage.

Internal implementation compatibility includes:

- Temporary bridge APIs.
- Legacy runtime classes.
- Old cache layouts.
- Magic channel-type numbers.
- Obsolete GDScript managers.
- Transitional Dictionaries.
- Deprecated fixed-control buffers.
- Superseded internal call paths.

Contributors must preserve public compatibility unless the change explicitly documents a deliberate behavior change.

Contributors are not required to preserve obsolete internal APIs or legacy implementation details during an approved architectural replacement. Keeping an obsolete internal path alive is not considered safer if it creates two competing sources of truth.

Git history is the reference for removed internal code. Legacy code does not need to remain compiled or callable for reference purposes.

## Development guidelines

Please keep the codebase clean, modular, efficient, testable, and easy to maintain.

General guidelines:

- Keep changes focused and avoid mixing unrelated modifications in the same pull request.
- Prefer clear commits with one understandable purpose.
- Small commits are preferred, but a coordinated multi-file change is acceptable when required for an approved architectural replacement.
- Do not artificially split a structural migration in a way that leaves two active implementations for the same responsibility.
- Avoid creating very large files.
- Split responsibilities into modules when it improves ownership and maintainability.
- Use clear names for classes, functions, variables, resources, protocols, and scripts.
- Add a concise one-line or two-line English comment above every new or substantially changed function definition.
- Write code comments and developer documentation in English.
- Avoid high-frequency node creation and deletion during live playback.
- Reuse meshes, materials, textures, shaders, nodes, RIDs, and other resources whenever possible.
- Consider batching, dirty flags, shared resources, `MultiMeshInstance3D`, packed buffers, native-side snapshots, and shader-side parameters before adding per-fixture or per-channel Godot updates.
- Avoid unnecessary dependencies unless there is a clear and documented reason.
- Keep the project portable across supported platforms whenever possible.
- Do not duplicate the same authoritative runtime state in both C++ and Godot.
- Do not add a compatibility bridge without documenting its owner, purpose, expiration condition, and deletion criteria.
- Do not describe a target architecture as active until the production path and tests prove that it is active.

Please also follow the architecture rules in:

- `AGENTS.md`
- `peraviz_tree.md`
- `docs/architecture.md`
- `docs/godot_performance_guidelines.md`
- `docs/gdtf-runtime-architecture.md`
- `docs/dmx-visual-runtime.md`

If these documents disagree with the actual repository structure or active code path, update the documentation or raise the inconsistency before relying on it.

## Normal refactoring and architectural replacement

### Normal refactoring

For normal maintenance and feature work:

- Refactor incrementally around the affected code path.
- Preserve public behavior.
- Prefer small, focused changes.
- Avoid unrelated rewrites.
- Keep supported formats and workflows compatible.
- Measure performance changes when practical.

### Architectural replacement

An architectural replacement applies when the issue, task, or maintainer explicitly requests a large structural refactor, legacy removal, breaking internal migration, or irreversible pipeline change.

In that case:

- The requested target architecture is authoritative for the affected subsystem.
- Internal APIs may be broken, renamed, or removed.
- Legacy paths should be deleted from the active build instead of being wrapped, adapted, or retained as automatic fallback.
- Temporary bridges are allowed only when strictly necessary for a documented multi-step migration.
- A temporary bridge must not receive new feature development.
- A migration is not complete while the production path still depends on legacy bindings, magic channel codes, duplicate caches, universal fixture-state Dictionaries, or obsolete appliers.
- A migration is not complete merely because new types or new documentation exist.
- Tests must exercise the new production path.
- Large deletions and coordinated multi-file changes are acceptable when required to establish one authoritative implementation.
- Secondary capabilities may remain temporarily unsupported when the new vertical path is real, testable, documented, and no longer routes through the legacy engine.

## Working with MVR, GDTF, and live control data

Peraviz works with formats and protocols used in real productions, manufacturer libraries, consoles, CAD applications, and visualization workflows.

When contributing changes related to MVR, GDTF, DMX, Art-Net, sACN, fixture attributes, gobos, color, prisms, strobe, pan, tilt, beam rendering, emitters, filters, shapers, or media:

- Follow the official format or protocol structure as closely as possible.
- Preserve public compatibility and report intentional deviations.
- Avoid assumptions that only work with one exporter, console, manufacturer, fixture library, or application.
- Test with more than one representative file when possible.
- Keep imported, compiled, runtime, and renderer data predictable.
- Preserve unknown or unsupported GDTF information in diagnostics rather than silently guessing or discarding it.
- Represent repeated GDTF families with stable IDs and collections instead of one fixed member per fixture.
- Keep expensive per-frame work out of Godot scripts unless profiling and documentation justify it.
- Keep parser-owned and compiler-owned GDTF semantics in native code.
- Do not reconstruct GDTF meaning from names, strings, or magic values in the live Godot path.
- Review semantic model changes for compatibility with the Peraviz and Perastage GDTF contract.

If you are unsure whether a behavior is correct according to a standard or common lighting workflow, mention it clearly in the issue or pull request instead of silently choosing an interpretation.

## Testing requirements

Tests should verify architecture and behavior, not only implementation names.

When adding or changing runtime behavior:

- Prefer end-to-end or vertical tests that use the real parser, compiler, runtime, bridge, and applier path when practical.
- Do not use manually constructed legacy bindings as the only proof that a GDTF-first runtime works.
- Test schema version and schema-generation validation.
- Test invalid and unsupported data paths.
- Test dirty-state behavior and unchanged-frame suppression.
- Test that unused universes and irrelevant channel changes are ignored early.
- Test repeated GDTF families and stable ID handling.
- Test that Godot does not reinterpret raw protocol or GDTF semantics in the live path.
- Add or update architecture guardrails when changing an important boundary.
- Ensure guardrails inspect the real repository paths.
- A missing expected source directory must fail the check instead of silently passing.

## Pull request checklist

Before opening a pull request, check the following:

- The native extension builds successfully when the change touches native code.
- The Godot project opens and runs when the change touches viewer, UI, scene, or rendering code.
- The change has been tested locally with a representative scene or test fixture when possible.
- The pull request has a clear description.
- The change is related to a specific issue, discussion, or architectural task when possible.
- The PR states whether it is a normal refactor or an architectural replacement.
- Performance-oriented changes include a short before-and-after note when practical.
- Architectural changes explain the old ownership, the new ownership, and any removed legacy path.
- New behavior and changed architecture are documented.
- Documentation distinguishes target architecture from currently active implementation.
- UI changes include screenshots when useful.
- The code follows the existing project style.
- The change does not introduce unrelated formatting changes.
- Available checks under `tests/` have been run.
- Native tests relevant to the changed pipeline have been run.
- The intended production path is tested.
- Any check that could not run is listed with the reason and the closest equivalent that was run.
- Temporary bridges, fallbacks, or incomplete migration steps are documented with deletion criteria.
- The PR does not claim that a migration is complete while legacy runtime paths remain active.

## Documentation contributions

Documentation improvements are very welcome.

This includes:

- Fixing typos.
- Improving explanations.
- Adding screenshots.
- Clarifying installation and build steps.
- Explaining workflows.
- Updating outdated information.
- Correcting project structure diagrams.
- Separating target architecture from current implementation status.
- Documenting migration state and deletion criteria.
- Making the documentation easier for contributors from the live events, lighting, stage design, visualization, and software development communities.

Documentation must reflect the real repository and active production path. Do not copy future plans into sections that describe current behavior.

## Be friendly and constructive

Please keep discussions respectful and constructive.

It is completely fine to disagree about how something should work, but explain the reasoning behind your position. The goal is to make Peraviz more accurate, efficient, maintainable, and useful.

## New to GitHub?

No problem.

If you are new to GitHub and only created an account to report something, you are still welcome.

Open an issue and explain the problem as clearly as you can. Screenshots, steps to reproduce the problem, sample files, logs, and simple observations are often more useful than technical language.

## License

By contributing to Peraviz, you agree that your contributions will be released under the same license as the project.

Only contribute code, files, images, models, fixture data, documentation, or test files that you have the right to share.
