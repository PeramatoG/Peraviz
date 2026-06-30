# Contributing to Peraviz

First of all, thank you for taking the time to help improve Peraviz.

Peraviz is an open-source real-time 3D DMX visualizer based on MVR/GDTF workflows. It is developed alongside Perastage, but its main goal is different: Peraviz should load a scene, interpret fixture data, receive live control data, and render the result as efficiently and predictably as possible.

You do not need to be an experienced developer to contribute. Bug reports, real-world test files, performance feedback, fixture compatibility notes, documentation improvements, and usability feedback are all useful.

## Ways to contribute

You can help Peraviz in several ways:

- Report bugs or crashes.
- Report performance or latency problems.
- Suggest new features or improvements.
- Test the application with real MVR, GDTF, fixture, truss, scene object, and DMX/Art-Net data.
- Improve documentation.
- Help with translations or clearer wording.
- Submit code changes through pull requests.
- Share screenshots, logs, profiler data, or simplified example files when possible.

## Before opening an issue

Before creating a new issue, please check if a similar one already exists.

If it already exists, feel free to add extra information there instead of opening a duplicate. Extra details are especially helpful when they come from a different operating system, GPU, fixture file, MVR exporter, or lighting console setup.

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
- A simplified MVR/GDTF/project file, if you are allowed to share it.

If you cannot share the original file because it belongs to a real production, venue, client, designer, or manufacturer, that is completely fine. A simplified test file that reproduces the same problem is also very helpful.

Please avoid uploading private, confidential, copyrighted, or client-owned show files unless you have permission to share them publicly.

## Reporting performance or latency problems

Peraviz is intended to become a real-time visualizer, so performance reports are very valuable.

When reporting a performance issue, please describe:

- Whether the problem is FPS, input latency, import time, render quality, memory usage, CPU usage, GPU usage, or something else.
- The approximate number of fixtures, meshes, universes, and patched DMX addresses involved.
- Whether the problem happens with live Art-Net/DMX input, manual fixture testing, scene loading, camera movement, or all of them.
- Whether the same scene is smooth when live input is disabled.
- Your CPU, GPU, RAM, operating system, and graphics driver version.
- Any profiler capture, frame-time log, or before/after measurement you can provide.

Performance reports do not need to be perfect. Even rough numbers and clear reproduction steps can help identify bottlenecks.

## Suggesting features

Feature requests are welcome.

When suggesting a feature, please describe:

- What problem it would solve.
- How you imagine it working.
- Whether it is related to MVR import, GDTF parsing, live DMX, Art-Net, sACN, fixture attributes, beam rendering, gobos, camera/viewer workflow, UI, performance, or something else.
- If another application already does something similar, feel free to mention it.

The more context you provide, the easier it is to understand the real use case behind the request.

## Code contributions

Code contributions are welcome, but for large changes it is usually better to open an issue first. This helps avoid duplicated work or changes that do not fit the current direction of the project.

For small fixes, documentation improvements, or simple corrections, you can open a pull request directly.

## Development guidelines

Please keep the codebase clean, modular, efficient, and easy to maintain.

Peraviz has an important C++ side and an important Godot side. The intended direction is:

- Native C++ / GDExtension should own heavy data processing.
- Godot should focus on graphics, scene presentation, UI, cameras, materials, and renderer configuration.
- Live protocol handling, DMX frame processing, fixture patch lookup, attribute resolution, interpolation, and high-frequency state preparation should remain on the native side whenever possible.
- Godot should receive compact, already-resolved render data instead of repeatedly parsing or resolving raw control data in scripts.

General guidelines:

- Keep changes focused and avoid mixing unrelated modifications in the same pull request.
- Prefer small, clear commits over very large commits.
- Avoid creating very large files. Split code into smaller modules when it makes sense.
- Keep responsibilities separated by module.
- Use clear names for classes, functions, variables, resources, and scripts.
- Add a concise one- or two-line English comment above every new or substantially changed function definition.
- Comments inside the code should be written in English.
- Avoid high-frequency node creation/deletion during live playback.
- Reuse meshes, materials, textures, and resources whenever possible.
- Consider batching, dirty flags, shared resources, `MultiMeshInstance3D`, and native-side frame snapshots before adding per-fixture/per-channel updates in Godot.
- Avoid unnecessary dependencies unless there is a clear reason to add them.
- Keep the project portable across supported platforms whenever possible.

Please also follow the architecture rules in:

- `AGENTS.md`
- `peraviz_tree.md`
- `docs/architecture.md`
- `docs/godot_performance_guidelines.md`

## Pull request checklist

Before opening a pull request, please check the following:

- The native extension builds successfully when the change touches native code.
- The Godot project opens and runs when the change touches viewer/UI/rendering code.
- The change has been tested locally with a representative scene when possible.
- The pull request has a clear description.
- The change is related to a specific issue when possible.
- Performance-oriented changes include a short before/after note when practical.
- New behavior is documented if needed.
- UI changes include screenshots when useful.
- The code follows the existing project style.
- The change does not introduce unrelated formatting changes.
- Available checks under `tests/` have been run, or the reason they could not be run is documented.

## Working with MVR, GDTF, and live control data

Peraviz works with formats and protocols used in real productions, manufacturers' libraries, and lighting workflows.

When contributing changes related to MVR, GDTF, DMX, Art-Net, sACN, fixture attributes, gobos, color, prism, strobe, pan/tilt, or beam rendering:

- Try to follow the official format/protocol structure as closely as possible.
- Be careful with compatibility.
- Avoid assumptions that only work with one specific exporter, console, manufacturer, or fixture library.
- Test with more than one file when possible.
- Keep imported and runtime data predictable.
- Avoid adding expensive per-frame work to Godot scripts unless there is a measured reason.

If you are not sure whether a behavior is correct according to a standard or common lighting workflow, mention it in the issue or pull request. Discussion is welcome.

## Documentation contributions

Documentation improvements are very welcome.

This includes:

- Fixing typos.
- Improving explanations.
- Adding screenshots.
- Clarifying installation/build steps.
- Explaining workflows.
- Updating outdated information.
- Making the documentation easier for new users.

Clear documentation is especially important because many Peraviz users may come from the live events, lighting, stage design, or visualization world rather than from software development.

## Be friendly and constructive

Please keep discussions respectful and constructive.

It is completely fine to disagree about how something should work, but try to explain the reason behind your opinion. The goal is to make Peraviz better for everyone using it.

## New to GitHub?

No problem.

If you are new to GitHub and only created an account to report something, you are still very welcome here.

Just open an issue and explain the problem as clearly as you can. Screenshots, steps to reproduce the problem, and example files are often more useful than technical language.

## License

By contributing to Peraviz, you agree that your contributions will be released under the same license as the project.

Please only contribute code, files, images, models, fixture data, documentation, or test files that you have the right to share.
