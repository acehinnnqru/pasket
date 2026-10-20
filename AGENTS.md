# Repository Agent Instructions

## Commit messages

- Every commit message must follow Conventional Commits: `<type>[optional scope][!]: <description>`.
- Use a lowercase type: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, or `revert`. Choose the type that describes the change; use `feat` for new functionality and `fix` for bug fixes.
- Write the subject and any body or footers in English. Keep the description concise, use the imperative mood, and omit a trailing period from the subject.
- Add a scope when it helps identify the affected area, such as `fix(clipboard): preserve selection after deleting a history item`.
- Mark breaking changes with `!` before the colon or a `BREAKING CHANGE:` footer.
- These message requirements do not waive individual commit approval or GPG signing requirements.

## Build validation

- Validate app changes with an unsigned build. The user authorizes disabling app code signing for this validation command:

  ```sh
  xcodebuild -project pasket.xcodeproj -scheme pasket -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
  ```

- Use this unsigned build from the start; do not first attempt a signed build or test certificate availability.
- Do not create, install, repair, or change signing certificates, provisioning profiles, keychains, or developer account settings unless the user explicitly requests that work.
- Keep the signing override scoped to the build command. Do not change the project's signing settings.
- If Swift macro compilation fails with `sandbox-exec: sandbox_apply: Operation not permitted`, request approval to rerun the same unsigned build outside the sandbox. Do not change the toolchain or signing settings to work around that sandbox restriction.
- Confirm the full app compiles successfully before reporting compilation as passed. Core tests alone do not validate the SwiftUI app, and compilation alone does not establish that UI behavior was manually verified.
- These instructions concern app code signing only. All requirements for GPG-signed Git commits and individual commit approval remain in effect.
