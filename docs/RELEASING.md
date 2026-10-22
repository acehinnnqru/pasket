# Releasing Pasket

[Back to the README](../README.md) · [Development guide](DEVELOPMENT.md)

Use **Actions → Bump version and release → Run workflow** on the default branch.
Choose `patch`, `minor`, or `major`: from `1.2.3`, these produce `1.2.4`, `1.3.0`,
or `2.0.0`, respectively. The workflow updates `MARKETING_VERSION` in every Xcode
configuration and increments `CURRENT_PROJECT_VERSION` by one. The Xcode project
is the source of truth for both values; release builds do not override them.

Clicking **Run workflow** authorizes that one predictable CI version commit and
its tag. The workflow displays the exact diff and commit message, runs version
tooling tests and core tests, and compiles the complete universal app without
signing. If validation fails, it creates neither a commit nor a tag. After
validation, it creates an unsigned commit such as
`chore(release): bump version to 1.2.4` and the corresponding lightweight tag
`v1.2.4`, then pushes the default branch and tag atomically. If the default branch
has moved since the run started, the job stops; start a new run on the latest
code. It never force-pushes or moves existing tags. This unsigned-commit exception
applies only to this manually requested CI version update.

[Bump version and release](../.github/workflows/bump-version.yml) then calls
[Release macOS app](../.github/workflows/release.yml) automatically. The release
workflow checks that the tag matches the version stored in the project, runs
tests, builds a universal Release app for Apple Silicon and Intel, signs with
Developer ID, submits it to Apple's notary service, staples the ticket, and
publishes these GitHub Release assets (using `v1.2.4` as an example):

- `pasket-v1.2.4-universal.zip`: contains the signed, notarized `pasket.app`.
- `pasket-v1.2.4-universal.dmg`: contains the same app and an Applications shortcut
  for drag-and-drop installation. The disk image is also signed, notarized, and stapled.

There is no separate `.app` asset: an app is a directory bundle, and the ZIP
preserves its structure, signature, and notarization ticket for downloading.
Both downloads require macOS 26 or later. The workflow uses the preinstalled
Xcode 27.1 on GitHub's `xcode-27` hosted runner, matching the local project
toolchain; it does not install a toolchain.

Add these **repository secrets** under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` export containing one **Developer ID Application** certificate and its private key. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The nonempty password chosen when exporting the `.p12`. |
| `APPLE_TEAM_ID` | The Apple Developer team ID associated with the certificate. |
| `APPLE_API_KEY_ID` | The key ID of an App Store Connect **team API key** for notarization. |
| `APPLE_API_ISSUER_ID` | The issuer UUID for that team API key. |
| `APPLE_API_PRIVATE_KEY` | The complete `.p8` private key contents, including the BEGIN/END lines and real line breaks. |

Export the certificate **with its private key** from Keychain Access and encode
the `.p12` locally with `base64 -i /path/to/DeveloperID.p12 | pbcopy`. Paste the
result into `DEVELOPER_ID_CERTIFICATE_BASE64`; keep the original file private.
Use a **Developer ID Application** certificate for distribution outside the
Mac App Store, rather than an Apple Development, Apple Distribution, or
Developer ID Installer certificate. The current app does not need a provisioning
profile for its capabilities.

Create the notarization team API key in **App Store Connect → Users and Access →
Integrations → App Store Connect API**, using the Developer role or another role
with notarization access. Download its `.p8` file and use the key ID and issuer
ID shown there. Use credentials from the same Apple Developer team as the signing
certificate. This workflow expects a team key with an issuer ID.

Merge these workflows into the default branch before using the manual action.
GitHub supplies `GITHUB_TOKEN` automatically; no personal access token or GPG
key is needed. The bot needs permission to push to the default branch and create
tags. If repository rules require signed commits or pull requests, they must
allow this intended automation; the workflow does not bypass those rules.
The bump workflow calls the release workflow directly because
[pushes made with `GITHUB_TOKEN` do not trigger another push workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow-run).

You can also push a tag manually, as long as it matches the checked-in project
version. For example, the current project version `1.0.0` can be released with
`v1.0.0` without first incrementing it. Tags such as `v1.0.0-rc.1` create
prereleases from project version `1.0.0`. Neither route changes project signing
settings.

The signing keychain and decoded credentials exist only on the ephemeral hosted
runner and are deleted when the packaging script exits. Credentials are not
uploaded as artifacts. The workflow requires an `Accepted` result for both the
app and DMG, validates stapled tickets, and checks Gatekeeper before publishing.
Notarization rejection or a 30-minute submission timeout fails the job and leaves
the release unpublished; submission IDs and available Apple diagnostics appear
in the job log. For signing, notarization, or upload failures, fix the cause and
use **Actions → Release macOS app → Run workflow**, entering the existing tag.
This retries that version without another bump or commit. An interrupted upload
can resume while the release is still a draft. Published releases are never
overwritten. If a failure requires a code change, fix the code and run a new
patch bump; keep the old tag for traceability. Local changes do not affect builds
of an existing tag.

See Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
and GitHub's [certificate handling guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
for the underlying signing and notarization requirements. The first real signed
release must be verified in Actions after these secrets are configured; local
unsigned builds do not exercise Apple's notarization service or Gatekeeper.
