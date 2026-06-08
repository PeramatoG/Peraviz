# Peraviz versioning policy

Peraviz uses the root `VERSION` file as the canonical source for the application version. The file must contain only a semantic version in `MAJOR.MINOR.PATCH` format, without a leading `v`.

Official Git tags should use `vMAJOR.MINOR.PATCH`, matching the value in `VERSION` with a leading `v` added only for the tag name.

## Version numbers

- `MAJOR` is reserved for major public milestones or incompatible project/runtime changes.
- `MINOR` is used for public releases.
- `PATCH` is used for accumulated main-branch development builds, fixes, improvements, and testable builds.

## Releases and artifacts

GitHub Actions artifacts from `main`, if any, are test builds and are not official releases. Official releases should be created only by an explicit release workflow.

`docs/release-notes-draft.md` is the curated release body draft for the next expected Peraviz release and must stay release-ready.
