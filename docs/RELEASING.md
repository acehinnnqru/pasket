# Releasing Pasket

[Back to the README](../README.md) · [Development guide](DEVELOPMENT.md)

Use **Actions → Bump version and release → Run workflow** on the default branch.
Choose a release **channel**: `alpha`, `beta`, `rc`, or `stable`. Choose a **bump**
of `patch`, `minor`, or `major` when starting a new cycle after a stable release.
The channel defaults to `alpha`; the bump defaults to `patch`. The workflow
calculates the exact next tag from existing Git tags instead of accepting a
manually entered version.

Every release automatically publishes GitHub ZIP/DMG assets and uploads the same
version to TestFlight. No upload checkbox is required. Configure both the GitHub
release signing secrets and the TestFlight signing secrets described below before
starting a release.

For example, after releasing `1.0.0`:

| Current tag | Channel | Bump | Next tag |
| --- | --- | --- | --- |
| `v1.0.0` | alpha | patch | `v1.0.1-alpha.1` |
| `v1.0.1-alpha.1` | alpha | ignored | `v1.0.1-alpha.2` |
| `v1.0.1-alpha.2` | beta | ignored | `v1.0.1-beta.1` |
| `v1.0.1-beta.1` | rc | ignored | `v1.0.1-rc.1` |
| `v1.0.1-rc.1` | stable | ignored | `v1.0.1` |
| `v1.0.1` | stable | minor | `v1.1.0` |

Within a prerelease cycle, selecting the same channel increments its sequence;
advancing to another channel starts at `.1`. Channels may be skipped, including
releasing stable directly, but cannot move backward. Finishing a prerelease
cycle keeps its base version: `v1.0.1-rc.1` becomes `v1.0.1`, not `v1.0.2`.
Finish the current cycle before starting a different base version. With no
existing release tags, the first release uses the project's current version
(currently `1.0.0`), so the bump choice is ignored for that first release.

The workflow updates `MARKETING_VERSION` in every Xcode configuration and
increments `CURRENT_PROJECT_VERSION` by one for every release, including same-base
prereleases and the final stable release. Apple bundle versions stay numeric:
the tag and asset names include `alpha`/`beta`/`rc`, while the unique build number
distinguishes installations of the same base version. Existing tags identify
the release stage; no separate release-state file is maintained.

Before changing anything, the workflow checks that project version/build values
agree across configurations and match the latest tag's committed project. It
also checks canonical tag names, contiguous sequence and build numbers, valid
stage progression, and that release commits follow the same Git ancestry.
New stable cycles must be the next patch, minor, or major version; duplicate
or inconsistent release history stops the workflow. Tags reserve versions even
if signing or publication failed; retry the reserved tag rather than deleting it.

Clicking **Run workflow** authorizes that one predictable CI version commit and
its tag. The workflow displays the exact diff and commit message, runs version
tooling tests and core tests, and compiles the complete universal app without
signing. If validation fails, it creates neither a commit nor a tag. After
validation, it creates an unsigned commit such as
`chore(release): bump version to 1.0.1-alpha.1` and the corresponding lightweight
tag `v1.0.1-alpha.1`, then pushes the default branch and tag atomically. If the default branch
has moved since the run started, the job stops; start a new run on the latest
code. It never force-pushes or moves existing tags. This unsigned-commit exception
applies only to this manually requested CI version update.

[Bump version and release](../.github/workflows/bump-version.yml) pushes over SSH
using a dedicated writable deploy key. Its tag push automatically starts
[Release macOS app](../.github/workflows/release.yml) as a separate workflow run.
That run starts GitHub packaging and the reusable TestFlight workflow in parallel,
using the same tag for both. The bump workflow does not upload separately, so each
bump starts one GitHub release and one TestFlight upload.
The release workflow checks that the tag matches the version stored in the project, runs
tests, builds a universal Release app for Apple Silicon and Intel, signs with
Developer ID, submits it to Apple's notary service, staples the ticket, and
publishes these GitHub Release assets (using `v1.2.4` as an example):

- `pasket-v1.2.4-universal.zip`: contains the signed, notarized `pasket.app`.
- `pasket-v1.2.4-universal.dmg`: contains the same app and an Applications shortcut
  for drag-and-drop installation. The disk image is also signed, notarized, and stapled.

There is no separate `.app` asset: an app is a directory bundle, and the ZIP
preserves its structure, signature, and notarization ticket for downloading.
Both downloads require macOS 26 or later. The macOS jobs use the runner's selected
Xcode and verify that it reports version `27.1`. The signing jobs use the
`MACOS_SIGNING_RUNNER` repository variable as their runner label, falling back
to `xcode-27` when it is unset. A label routes jobs to a runner; it does not
install or select a toolchain. Installation paths
are configured on the runner, as described in the
[runner setup guide](DEVELOPMENT.md#runner-setup).

GitHub-hosted runners use a temporary signing keychain. Self-hosted macOS
Actions runners can reuse a persistent, repository-specific CI keychain with
the setup described under [Persistent signing on self-hosted runners](#persistent-signing-on-self-hosted-runners).
Both scripts reject ordinary local execution and unknown runner environments.

Add these **repository secrets** under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `RELEASE_DEPLOY_KEY` | Complete private SSH key for the repository's writable release deploy key, including its header/footer and real line breaks. This is separate from Apple's `.p8` API key and P12 signing certificate. |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` export containing one **Developer ID Application** certificate and its private key. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The nonempty password chosen when exporting the `.p12`. |
| `APPLE_TEAM_ID` | The Apple Developer team ID associated with the certificate. |
| `APPLE_API_KEY_ID` | The key ID of an App Store Connect **team API key** for notarization. |
| `APPLE_API_ISSUER_ID` | The issuer UUID for that team API key. |
| `APPLE_API_PRIVATE_KEY` | The complete `.p8` private key contents, including the BEGIN/END lines and real line breaks. |
| `CI_KEYCHAIN_PASSWORD` | Self-hosted runners only: a stable password for the dedicated CI keychains. This is independent of the Mac login password and the P12 export passwords. |

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
Configure the release deploy key before dispatching a bump:

1. Generate a dedicated SSH key pair for this repository outside the checkout.
   Use a key without a passphrase for this unattended checkout action.
2. Add its public key under **Settings → Deploy keys → Add deploy key** and enable
   **Allow write access**. Store the complete private key in the
   `RELEASE_DEPLOY_KEY` Actions Secret; do not Base64-encode it.
3. If main is protected, use **Settings → Rules → Rulesets** and configure the
   ruleset targeting main to allow **Deploy keys** in its bypass list with
   **Always allow**. The bypass must cover rules that prevent the intended direct
   unsigned version commit, such as required PRs, signed commits, and status
   checks. If another ruleset or legacy branch protection rule still blocks the
   push, that rule also needs to permit this automation. Protected release tags
   must likewise permit creation by the deploy key.

Ruleset bypass is granted to the **Deploy keys** actor category, not an individual
key or a specific version file. Other writable deploy keys on this repository
share that bypass. The workflow itself stages only the version project file,
compares it with the validated tree, checks that main has not moved, and performs
one atomic push without force. The deploy key is used only by the commit job;
tests and app builds do not receive it. Checkout removes its SSH credentials
in the post-job cleanup.

GitHub supplies `GITHUB_TOKEN` automatically for publishing release assets; no
personal access token or GPG key is needed. The commit job's token has read-only
contents permission and Git pushes use the SSH deploy key. A missing deploy key
fails the job instead of falling back to token authentication. Unlike
[pushes made with `GITHUB_TOKEN`](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow-run),
SSH tag pushes trigger the normal release workflow. A successful bump run confirms
the commit and tag were pushed; inspect the separate **Release macOS app** run
for GitHub packaging, publication, and TestFlight upload status.

See GitHub's [deploy key guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)
and [ruleset bypass actor reference](https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset)
for the repository-side setup. These settings are configured by the repository
owner; the workflows do not change protection rules or register deploy keys.

You can also push a tag manually, but its committed project version and build
number must follow the same progression rules. With no existing tags, project
version `1.0.0` can be released as `v1.0.0`, `v1.0.0-alpha.1`, `v1.0.0-beta.1`,
or `v1.0.0-rc.1`. Prerelease numbers must start at 1, increase by one within a
channel, and use only `alpha`, `beta`, or `rc`. All `v*` tags are treated as
release records, so keep unrelated tags outside this namespace. Pre-release
tags are marked as GitHub prereleases and never become the Latest release.
Neither route changes project signing settings.

On GitHub-hosted runners, the signing keychain is deleted when the packaging
script exits. On self-hosted runners, a successfully initialized CI keychain
is locked and retained for reuse. Both modes restore the original keychain
search list and remove decoded P12/API-key files and temporary build files.
Credentials are not uploaded as artifacts. The workflow requires an `Accepted` result for both the
app and DMG, validates stapled tickets, and checks Gatekeeper before publishing.
Notarization rejection or a 30-minute submission timeout fails the job and leaves
the release unpublished; submission IDs and available Apple diagnostics appear
in the job log. For signing, notarization, or upload failures, fix the cause and
rerun the failed jobs in the **Release macOS app** run. To start both distribution
jobs again, use **Actions → Release macOS app → Run workflow**, entering the
existing tag. This retries that version without another bump or commit. Avoid
restarting a successful TestFlight upload; use the dedicated TestFlight workflow
below when only that upload needs a retry. An interrupted GitHub asset upload
can resume while the release is still a draft. Published releases are never
overwritten. If a failure requires a code change, fix the code and request another
release. For alpha/beta/rc, select the same channel to increment its sequence;
after stable, select the desired channel and a patch bump. Keep the old tag for
traceability. Old tags remain retryable after newer releases. Local changes do
not affect builds of an existing tag.

See Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
and GitHub's [certificate handling guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
for the underlying signing and notarization requirements. The first real signed
release must be verified in Actions after these secrets are configured; local
unsigned builds do not exercise Apple's notarization service or Gatekeeper.

## Persistent signing on self-hosted runners

Use a dedicated macOS release runner that executes trusted release code. Keep
untrusted pull-request builds in a separate environment; a separate keychain
file does not isolate jobs running as the same macOS user. Give the release
runner a distinct label such as `pasket-signing`, set the repository variable
`MACOS_SIGNING_RUNNER` to that label, and keep the PR CI label `xcode-27` off
that runner. Select Xcode 27.1 as described in the
[runner setup guide](DEVELOPMENT.md#runner-setup).

Run the runner as a macOS user whose Xcode/keychain setup is already initialized:
`~/Library/Keychains` must exist and the user keychain search list must be readable
and nonempty. The helper does not create or repair a login keychain. The runner
also needs Python 3 for validation and the GitHub CLI (`gh`) for publishing release
assets; Xcode alone does not provide the GitHub CLI.

Set `CI_KEYCHAIN_PASSWORD` as an Actions Secret. On the first run, also supply
the existing P12 certificate and password secrets for the distribution channel.
The API-key secrets remain required on every run, and TestFlight still needs
`APP_STORE_PROVISIONING_PROFILE_BASE64` on every run. An Xcode account login
does not replace these inputs.

The shared [keychain helper](../.github/scripts/signing-keychain.sh) stores only
its dedicated keychains and initialization metadata under:

```text
~/Library/Keychains/pasket-ci/<owner>/<repository>/<APPLE_TEAM_ID>/
  developer-id.keychain-db
  app-store.keychain-db
```

Each keychain has adjacent `.ready` metadata. The helper does not import into
the login keychain, change the default keychain, or renew certificates in the
developer portal. It temporarily adds the selected CI keychain to the existing
search list and restores the original list at exit.

The self-hosted flow is:

1. Validate the Actions runner environment and required settings, then acquire
   the per-user signing lock before reading or changing the keychain search list.
2. If the dedicated keychain is missing, create it, import the channel's P12,
   and configure access for signing tools. If it is already initialized, unlock
   and reuse it without importing certificates or changing key permissions.
3. Check for valid certificate/private-key identities of the required types for
   `APPLE_TEAM_ID`. TestFlight additionally checks the profile's team, platform,
   bundle identifier, expiration, and certificate membership. File existence
   alone is not a successful validation.
4. Build, sign, and notarize or upload using the checked identities. The separate
   `.p8` API key is still supplied from Secrets as a temporary file.
5. Remove temporary credentials and any profile copies installed by this run,
   restore the original search list, lock the persistent keychain, and release
   the signing lock. An identical preinstalled provisioning profile is reused
   and left in place; conflicting profiles are rejected.

After initialization, P12 certificate/password secrets may be omitted when
reusing that keychain. If a P12 is supplied, its fingerprint must match the one
used at initialization. A changed P12, invalid identity, or wrong keychain
password stops the job; the script never silently replaces an existing keychain.
To rotate credentials, stop signing jobs and deliberately retire only the
affected managed keychain and its `.ready` metadata, then initialize it from the
new certificate secrets. Changing `CI_KEYCHAIN_PASSWORD` alone does not change
the password of an existing keychain.

Setup failures delete only a keychain and initialization metadata newly created
by that run. Existing initialized keychains survive failures; any persistent
keychain the job attempted to unlock is locked during cleanup. Cleanup
failure also fails an otherwise successful script. HUP, INT, and TERM trigger
cleanup, but a forced process kill or host failure can prevent it: inspect and
recover the managed state before the next release.

One shared lock protects the macOS user's keychain search list across both
distribution channels and all repositories using this helper. Concurrent jobs
fail with a clear lock error rather than changing each other's state. Use one
runner process per release user, or schedule signing jobs sequentially. Release
packaging and TestFlight are otherwise independent jobs; if multiple runner
processes share a user, retry a job rejected by the lock after the active one
finishes. A leftover lock is not automatically broken: confirm that no signing
job remains active and restore/lock any affected keychains before removing it.

This flow applies only to release tags containing the updated scripts and
helper. Retrying an older tag uses that tag's original signing behavior. Local
mock tests exercise lifecycle and failure handling without accessing a real
keychain; a real signed release still needs separate validation on the configured
runner.

## TestFlight uploads

[Upload macOS app to TestFlight](../.github/workflows/testflight.yml) is a reusable
workflow that archives the universal macOS app and uploads it to App Store Connect
using Xcode. Its upload job runs independently of GitHub ZIP/DMG packaging, so either
channel can succeed or be retried independently. It uses the same release tag, numeric
marketing version, and unique build number. Xcode's automatic build-number changes
are disabled to preserve the version reserved by the tag.

Every **Release macOS app** run automatically calls this workflow for the release
tag, including tag pushes, manual runs for an existing tag, and reusable workflow
calls. This applies to alpha, beta, rc, and stable releases. There is no upload
opt-in checkbox or enablement variable. **Bump version and release** starts the release
workflow through its tag push; it does not call TestFlight separately.

For a first upload or a retry, use **Actions → Upload macOS app to TestFlight →
Run workflow**, select the default branch, and enter an existing version tag.
This dedicated workflow uploads only the selected tag to TestFlight, without
rebuilding GitHub Release assets. Merge the workflow and scripts before creating
the release tag: the selected tag must contain them.
The workflow validates the tag and tooling before importing credentials. Core
tests also run unless a reusable-workflow caller sets `core_tests_verified: true`
after validating the exact release content. This input defaults to false and is
not exposed by the manual entry point, so standalone manual uploads always run
core tests. Calls from the release workflow also retain core tests. The workflow
never creates a version commit or tag itself.

### Certificates and provisioning profile

The GitHub release's **Developer ID Application** certificate signs downloads
distributed outside the Mac App Store. TestFlight uses separate store distribution
credentials from the same Apple Developer team:

1. An **Apple Distribution** certificate (or **Mac App Distribution**, whose
   installed identity is `3rd Party Mac Developer Application`) and its private key
   to sign the app.
2. A **Mac Installer Distribution** certificate (installed as
   `3rd Party Mac Developer Installer`) and its private key to sign the package
   Xcode uploads. A Developer ID Installer certificate does not serve this purpose.
3. A **Mac App Store Connect** distribution provisioning profile for the explicit
   App ID `com.acehinnnqru.pasket`, containing the app distribution certificate from
   step 1. Download the `.provisionprofile` from the developer portal. Development,
   wildcard, and Developer ID profiles are rejected by the upload script.

Create certificates and profiles in **Apple Developer → Certificates, Identifiers
& Profiles** with an authorized account. In Keychain Access, export both signing
identities **with their private keys together into one password-protected `.p12`**.
The export must contain exactly one app distribution identity and one installer
distribution identity. A `.cer` download alone does not contain a private key.
When renewing the app certificate, regenerate the matching profile and update
both secrets. See Apple's [certificate types](https://developer.apple.com/help/account/certificates/certificates-overview/)
and [App Store Connect profile guide](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/).

Here, a **signing identity** means a certificate paired with its matching private
key. Both certificates must have their matching private key available in the
export; neither the P12 password nor the App Store Connect `.p8` API key replaces
these signing keys. The private key is created when generating the certificate
signing request (CSR), and is not included in the `.cer` downloaded from Apple.

To check the export in **Keychain Access**:

1. On the Mac where the signing requests were created, open **My Certificates**
   in the keychain containing the distribution certificates.
2. Expand each of the two certificates and confirm that a private key appears
   beneath it. If a key is missing, obtain the exported identity from the Mac or
   person that created the CSR. Downloading the `.cer` again cannot recover it.
3. Select both certificate entries and export them together as one
   password-protected `.p12`, then update `APP_STORE_CERTIFICATES_BASE64` and
   `APP_STORE_CERTIFICATES_PASSWORD`.

The upload script reports the number of valid app and installer signing identities
when either count is not one. Zero matches does not prove that a private key is
missing: the certificate may also be absent, invalid (for example, expired or
untrusted), or of the wrong type. More than one match means the export contains
extra identities of that type; export only the intended pair. See Apple's
[signing identity export guide](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates).

If the export contains only `Developer ID Application`, it is the credential for
`DEVELOPER_ID_CERTIFICATE_BASE64`, not `APP_STORE_CERTIFICATES_BASE64`. Export the
App Store app and installer distribution identities listed above for TestFlight.

### Actions Secrets

Add these three **repository secrets** alongside the existing release secrets:

| Secret | Value |
| --- | --- |
| `APP_STORE_CERTIFICATES_BASE64` | Base64 of the combined `.p12` containing the app and installer distribution certificates and both private keys. |
| `APP_STORE_CERTIFICATES_PASSWORD` | The nonempty password for that `.p12`. |
| `APP_STORE_PROVISIONING_PROFILE_BASE64` | Base64 of the downloaded Mac App Store Connect `.provisionprofile`. |

Encode the files outside the checkout and paste the results into Actions Secrets:

```sh
base64 -i /path/to/AppStoreDistribution.p12 | pbcopy
base64 -i /path/to/Pasket.provisionprofile | pbcopy
```

Run each command separately and save its clipboard contents to the corresponding
secret before running the next command. Keep the original private files outside
the repository.

The workflow also uses the existing `APPLE_TEAM_ID`, `APPLE_API_KEY_ID`,
`APPLE_API_ISSUER_ID`, and `APPLE_API_PRIVATE_KEY`. The team API key needs permission
to upload builds to this app; Apple's upload guide lists Developer, App Manager,
Admin, and Account Holder as eligible roles. The existing Developer-role team key
can be reused if it has the required access. The `.p8` value remains the complete
key with real line breaks, not Base64. No Apple ID password, app-specific password,
or additional deploy key is needed by this workflow.

The script uses a temporary keychain on GitHub-hosted runners or the dedicated
persistent CI keychain on configured self-hosted runners. It validates profile
platform, team, bundle identifier, expiration, and certificate membership and
uses manual signing without automatic provisioning updates. On exit it removes
only profile copies installed by that run and decoded credentials, restores the
original keychain search list, and deletes the temporary keychain or locks the
persistent one. It does not create or renew certificates or profiles in the developer portal.

### App Store Connect setup and upload status

Create a **macOS app record** in App Store Connect using bundle ID
`com.acehinnnqru.pasket`, and ensure the membership and required agreements are
current. The bundle ID is the app's unique identifier, configured as
`PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project. The app record, explicit App ID,
provisioning profile, and built app must all use this identifier. It is separate
from the display name and version number.

The project already enables App Sandbox and declares
`ITSAppUsesNonExemptEncryption=NO`; review that declaration if encryption features
change. Select an Xcode version Apple currently accepts for uploads if the pinned
runner toolchain becomes ineligible.

A successful workflow means Xcode completed its upload, not that Apple finished
processing or approved beta distribution. Inspect **App Store Connect → Pasket →
TestFlight** for processing errors, compliance questions, and build availability.
Configure an internal testing group with automatic distribution if internal
testers should receive new builds automatically. External testing also requires
test information, a tester group, and any required TestFlight App Review. This
workflow uploads builds; it does not submit them for external beta review or
publish an App Store release. See Apple's [upload guide](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
and [internal testing guide](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).

After an interrupted upload, check App Store Connect before retrying: Apple may
already have accepted that version/build, and duplicate uploads are rejected.
Retry the same tag only if its build was not accepted. If Apple accepted it and a
replacement binary is needed, create the next release using the existing bump
workflow. Do not move the old tag or reuse its build number. Actual signing and
upload must be verified in Actions after the credentials are configured.
