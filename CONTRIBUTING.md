# Contributing to Peraviz

Thank you for helping improve Peraviz. This guide is for external contributors and summarizes the workflow, project boundaries, and checks expected before opening a pull request.

## Project focus

Peraviz is a real-time lighting visualizer built with native C++ and Godot. The native layer prepares runtime data; Godot presents and renders it.

Before changing runtime behavior, read:

- `docs/architecture.md` for the current architecture and target split.
- `docs/NATIVE_BUILD.md` for native build steps.
- `docs/pvz-project-format.md` for `.pvz` archive behavior.
- `docs/gdtf-support-matrix.md` when touching GDTF semantics.

## Branches and pull requests

- Create a focused branch for each change.
- Keep pull requests small enough to review.
- Separate runtime changes from documentation-only or test-only cleanup when practical.
- Explain user-visible changes first, then internal changes.
- Mention any tests that could not run and why.

## Runtime boundaries

When contributing code, preserve these boundaries:

- Native C++ owns protocol input, high-frequency DMX processing, fixture state resolution, dirty-state generation, and render-ready frame preparation.
- Godot owns UI, scene presentation, renderer resources, interaction, and applying prepared render data.
- Do not add new live GDTF or DMX semantic parsing to Godot.
- Do not reintroduce the removed fixed visual-frame row.
- Do not remove transitional setup APIs unless the task explicitly targets that runtime migration.

The current production setup still uses Godot-built fixture binding data and native setup calls. Do not write documentation or tests that claim parser-owned compiled GDTF programs already drive the visual runtime.

## GDTF, MVR, and `.pvz` data

- Follow official GDTF and MVR specifications for parsing or writing behavior.
- Preserve unknown or unsupported fixture data where possible and report it clearly.
- Do not mutate source GDTF files unless a task explicitly asks for that workflow and defines compatibility rules.
- `.pvz` project archives store Peraviz project state around an MVR; they do not replace MVR or GDTF source ownership.

## Coding style

- Keep changes modular and avoid duplicating logic.
- Prefer small focused helpers with clear ownership.
- Keep generated/build/cache files out of Git.
- For C++ changes, add a concise English comment above each new or substantially changed function definition.
- Add comments in other languages only when they clarify non-obvious behavior.
- Keep comments and developer-facing text in English.
- Do not wrap imports in try/catch blocks.

## Documentation and release notes

Update documentation when behavior, architecture, data flow, supported protocols, import/export behavior, renderer behavior, fixture behavior, or visible UI behavior changes.

Always keep `docs/release-notes-draft.md` release-ready when a change is meaningful to users or maintainers. Use clear sections such as Highlights, Improvements, Fixes, Documentation, and Internal changes. Avoid process notes or raw commit-style wording.

## Tests and checks

Run the most relevant checks for your change. Common commands include:

```bash
tests/check_no_large_files.sh
tests/check_runtime_architecture.sh
git diff --check
```

For native changes, configure and run the native CMake tests described in `docs/NATIVE_BUILD.md`. For GDScript behavior, run the relevant headless Godot scripts under `tests/`.

If a dependency such as Godot or a compiler is unavailable, report the exact command and the reason it could not run.

## Review checklist

Before requesting review, confirm that:

- The change matches the scope described in the pull request.
- Runtime behavior changes are covered by behavior or integration tests where practical.
- Documentation links still point to existing files.
- Release notes summarize the change at the right level for users or maintainers.
- Static guardrails were not relaxed to hide a real regression.
- New test data is small, deterministic, and safe to redistribute.

## Communication

Use clear, concrete language in issues and pull requests. When discussing architectural work, distinguish current implementation from target direction. If a change is intentionally transitional, describe the follow-up condition that will let maintainers remove it later.

## Reporting issues

When filing an issue, include:

- Operating system and Godot version.
- The Peraviz build or commit used.
- Steps to reproduce.
- Expected and actual behavior.
- Relevant logs, screenshots, fixtures, MVR files, or GDTF files when shareable.

Do not include private show files, credentials, or proprietary fixture data unless you have permission to share them.
