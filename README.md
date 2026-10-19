# pasket
A clipboard manager. Collect your contents into a basket.

## Run

Open `pasket.xcodeproj` in Xcode, select the `pasket` scheme and My Mac, and run.
Pasket lives in the menu bar and opens its history panel at launch.

- **Hyper + P** (Control + Option + Shift + Command + P) toggles the panel.
- Search the complete saved content or source app, filter by type, and select with the arrow keys.
- **Return**, double-click, or **Copy** copies the complete item, closes the panel,
  and returns to the previous application. Press **Command + V** there to paste.
- **Escape** dismisses the panel. With the filter menu open, Escape first closes that menu.
- Use **Settings…** to change the global shortcut. Preferences persist; registration failures are shown.
- Pause or resume collection from the panel or menu bar. Use the trash menu to delete the
  selected entry or clear history with confirmation. Rows also have a Delete context menu.

macOS may request permission when Pasket first reads a new clipboard entry. Allow clipboard
access for background collection. If access is denied, the panel offers to open System Settings.
Pasket never changes your system privacy settings.

## Collection and limits

- Clipboard changes are checked every 350 ms while Pasket is running. Copies made and replaced
  between checks can be missed. Starting or resuming collection does not import the existing
  clipboard or replay copies made while paused. The pause state survives relaunch.
- Text is saved verbatim, including whitespace and line breaks, up to **2,000 Unicode characters**
  (extended grapheme clusters). Longer text is skipped with a visible message, never truncated.
  List summaries show up to 120 characters; previews show at most 500 characters. Search and
  copying always use the complete saved text.
- An entire HTTP/HTTPS URL is classified as a link; an entire email address as an email.
  Surrounding whitespace is ignored only for classification. Mixed prose remains text.
- Each entry records its latest copy time and an estimated source app name and bundle ID.
  Source attribution uses the frontmost external app at observation time; clipboard data does not
  provide a reliable source identity. Identical text, normalized image data, or the same ordered
  group of file paths updates one record and moves it to the top. Copying from Pasket also moves
  the entry to the top while retaining its original source metadata.
- Entries marked concealed, transient, or automatically generated are skipped. Other unmarked
  clipboard text is collected normally.
- Images are saved as PNG with a thumbnail, with a **20 MiB** per-image limit (including the incoming
  representation) and a 40-million-pixel decode limit. Image processing happens outside the main
  actor; in-memory thumbnails are bounded to 32. Copying restores the saved image data.
- Up to 100 file references can be recorded together. Pasket retains paths and read-only
  security-scoped bookmarks when the system grants access, allowing those file references to be
  reopened after relaunch. Existing ordinary bookmarks are upgraded when an accessible entry is copied.
  The app-scoped bookmark entitlement is enabled for Debug and Release; App Sandbox and user-selected
  read-only file access remain enabled. Pasket displays original size when known and copies file URLs.
  It does not back up file contents. If an
  original is missing or sandbox access expires, use **Restore File Access…** to select accessible
  originals again, or delete the entry. Deleting history never deletes the original files.
- Keep up to **1,000 entries**, **50 MiB of text bodies**, and **500 MiB of images including thumbnails**.
  Oldest entries are evicted when a limit is reached. Saved image files are removed only after
  updated history is written successfully. Deleting, clearing, and skipping oversized entries leave
  the system clipboard unchanged.

## Local storage

History uses a versioned `history.json` and a separate `Images` directory under the app's
Application Support/Pasket directory inside its sandbox. No third-party dependencies or network
services are used. Writes are serialized and atomic. Quitting waits for queued writes; failed writes
show a retry action and require a choice before quitting with unsaved changes. A damaged or
unsupported history file is left untouched, and collection stops until it can be loaded.

## Validation

Run `swift test` for the core suite. Tests use isolated named pasteboards and temporary fixtures;
they do not read or overwrite the real clipboard. They cover text boundaries, deduplication,
full-body search and copy, classification, source persistence, pause/resume, restart, deletion,
retention, damaged history, images and thumbnails, storage failures, and file references.

For the desktop smoke test:

1. Run Pasket, dismiss its panel, and copy `Pasket interaction check 2000` from a text editor.
2. Press Hyper + P; the search field should accept typing immediately.
3. Search `interaction check`, select the entry, and press Return.
4. Confirm the panel closes and focus returns to the editor; press Command + V and check the text.
5. Repeat with arrow-key selection, type filtering, Escape, and successive invocations.
6. Quit and relaunch to verify persistence; test pause/resume and deletion separately.

Core tests and a successful build do not establish that this desktop smoke test passed.

On October 19, 2026, the user verified the main desktop flow: Hyper + P opened the panel,
search found the entry, Return copied it and returned to the original app, and Command + V
pasted the expected content. The other manual checks above have not yet been reported.

## Structure

- `MyApp.swift`: menu bar entry and application scene.
- `ApplicationController.swift`: panel, settings, focus restoration, and termination handling.
- `ContentView.swift`: search, filters, previews, and history controls.
- `ClipboardModels.swift`: versioned records, classification, fingerprints, and limits.
- `ClipboardMonitor.swift`: polling, sensitive-type exclusions, and source estimation.
- `ClipboardFileAccess.swift`: file bookmarks, availability checks, and scoped access lifecycle.
- `ClipboardPersistence.swift`: atomic storage, image normalization, thumbnails, and cleanup.
- `ClipboardStore.swift`: collection queues, retention, selection, copying, and management actions.
- `GlobalShortcut.swift` and `ShortcutSettingsView.swift`: shortcut registration and settings.
- `Tests/PasketCoreTests`: dependency-free core regression tests, runnable through SwiftPM.
