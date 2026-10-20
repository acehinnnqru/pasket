# Repository Agent Instructions

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
