# pasket
A clipboard manager. Collect your contents into a basket.

## Run

Open `pasket.xcodeproj` in Xcode, select the `pasket` scheme and My Mac, and run.
Pasket lives in the menu bar and opens its history panel at launch.

- **Hyper + P** (Control + Option + Shift + Command + P) toggles the panel.
- The search field receives focus whenever the panel opens. Search the complete saved content or
  source app and filter by type. Arrow keys and row clicks change the selected entry while keeping
  the search field focused, so you can continue typing immediately.
- Selecting a specific content type shows **Back To Default** to the left of the type selector.
  Click it to return to **All Types** while keeping your search text.
  The selector and its menu keep the same width across all content types.
- **Return**, double-click, or **Copy** copies the complete item, closes the panel,
  and returns to the previous application. Press **Command + V** there to paste.
- **Escape** dismisses the panel. With the filter or **…** menu open, Escape first closes that menu
  and restores search focus. Both menus use the same custom appearance and support arrow keys and Return;
  clicking outside also closes them. The **…** menu opens above its button.
- The detail preview shows only content. Images fit the available space without scrolling;
  metadata and file access controls sit in the table below, which scrolls independently when needed.
  Long table values are truncated; hover to see the complete value.
- Move the history window using the dotted drag handle in its header. Move Settings by dragging
  its header title or empty header space. Dragging starts after 8 points of movement; clicking
  entries, selecting text, and dragging other content do not move the window.
- Open the **…** menu after **Copy** and choose **Settings…** to change the global shortcut.
  Preferences persist; registration failures are shown.
  Settings opens centered on the history panel's display each time, including when reusing an
  existing settings window. When history is hidden, it uses the display under the pointer.
- **Command + ,** opens Settings from the history panel. Change **Open Settings** in Settings,
  use **Restore Default** to return to Command + comma, or **Clear** to disable it. The menu bar
  uses the same binding. Settings, history, and deletion shortcuts must use different combinations.
  Existing history or deletion bindings take priority if they already use Command + comma.
- Configure **Delete Selected Item** in Settings to assign a shortcut with Command, Control, or
  Option. It only works in the history panel, preserves search focus, and deletes one selected entry
  per key press. No deletion shortcut is assigned by default; use **Clear** in Settings to disable it.
  The delete shortcut must differ from the history and settings shortcuts.
- Click the status light in the panel footer to pause or resume collection, or use the menu bar.
  While collecting, a small dot in the app's accent color gently brightens and dims every 2.8 seconds,
  with the Soft glow treatment: a matching halo strengthens and softens in sync. The icon does not move.
  Pausing turns the light gray and stops the animation. The separate item count and basket icon stay still.
  The animation respects Reduce Motion, and hovering over the light shows **Pause** or
  **Resume**. Use **Delete Selected** to delete one
  entry or **… → Delete All Entries…** to clear history with confirmation.
  Rows also have a Delete context menu. Unmodified **Backspace** and **Delete** only edit the search;
  they never delete history entries, even when the search field is empty.
- Debug builds include a **Debug mode** toggle in the panel footer. Turn it on to show fictional
  text, links, email, an illustration, and a file reference for screenshots. Search, filters, and
  previews use only these samples. Collection pauses and history actions are disabled while it is
  on. Turning it off restores your saved history and previous collection state. Samples and the
  toggle state are never saved; Release builds do not include this control or sample data.

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
  actor; in-memory thumbnails are bounded to 32. History rows fall back to the default image icon
  when a thumbnail is missing or unreadable. The detail pane independently loads a preview from the
  saved original, limited to 1,600 pixels on its longest side; only the current preview is retained.
  Copying restores the saved image data.
- A single copied image file, including a screenshot tool's temporary file, remains a file reference.
  Its thumbnail and detail preview are generated in memory from the original while access is available;
  Pasket does not save a copy. Existing image file entries support the same previews. Once the original
  is removed or access expires, the row falls back to the default image icon and the preview is unavailable.
  These entries appear in both Images and Files filters.
- Up to 100 file references can be recorded together. Pasket retains paths and read-only
  security-scoped bookmarks when the system grants access, allowing those file references to be
  reopened after relaunch. Existing ordinary bookmarks are upgraded while accessible entries are
  checked, previewed, or copied; refreshed bookmarks are saved with history.
  The app-scoped bookmark entitlement is enabled for Debug and Release; App Sandbox and user-selected
  read-only file access remain enabled. Pasket displays original size when known and copies file URLs.
  Groups of files and other file types remain references without a backup of their contents. If an
  original needs permission, use **Authorize Folder…** in its detail pane to select a containing
  folder once. Pasket saves a read-only folder grant and reuses it for current and future entries
  in that folder and its subfolders, including after relaunch. This does not copy the original files
  or replace the selected history entry. Groups spanning multiple folders may need a grant for
  each folder, or one for a shared parent. Settings → File Access lists saved folders and lets
  users add or remove them. Removing a saved folder grant does not delete files or history, and
  independent file grants may still provide access. Deleted originals remain unavailable; granting
  folder access cannot restore deleted files. Deleting history never deletes the original files.
- Keep up to **1,000 entries**, **50 MiB of text bodies**, and **500 MiB of images including thumbnails**.
  Oldest entries are evicted when a limit is reached. Saved image files are removed only after
  updated history is written successfully. Deleting, clearing, and skipping oversized entries leave
  the system clipboard unchanged.

## Local storage

History uses a versioned `history.json` and a separate `Images` directory under the app's
Application Support/Pasket directory inside its sandbox. No third-party dependencies or network
services are used. Read-only folder bookmarks are stored in `history.json` and kept when history
is cleared; they can be removed separately in Settings. Writes are serialized and atomic. Quitting
waits for queued writes; failed writes show a retry action and require a choice before quitting
with unsaved changes. A damaged or
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
6. With the search field focused, test Backspace, Delete, and Fn + Backspace with both empty and
   nonempty text; verify they only edit the search and never remove history. Press an arrow key
   or click a row, then verify the search caret stays visible and typing and deletion still edit
   the search. Use Delete Selected to remove one entry, and test both Cancel and Clear History
   in the **… → Delete All Entries…** confirmation. Check that **… → Settings…** opens Settings.
   Confirm typing resumes after each action and Return still copies. Check the custom **…** menu's
   placement above its button, hover feedback, arrow-key navigation, Return selection, outside-click
   dismissal, and Escape dismissal. Disabled Delete All Entries must be skipped by keyboard navigation.
7. In Settings, record a Delete Selected Item shortcut. Verify it deletes one selected entry
   while preserving the search text and caret, does not repeatedly delete when held, and does
   nothing in Settings or while a filter menu or confirmation is open. Test recording cancellation,
   rejecting the global history shortcut, and clearing the binding. Relaunch to verify persistence.
   Press Command + comma in the history search field to open Settings. Change Open Settings,
   verify the new binding works and the previous one stops working, then test clearing, restoring
   the default, conflict rejection, and persistence after relaunch. Recording and confirmation
   dialogs must not invoke the settings shortcut.
   Press Escape in Settings with different controls focused and after reopening the window;
   it must close Settings. While recording a shortcut or choosing a folder, Escape must cancel
   only that operation and leave Settings open.
   Close Settings with its × button, move the pointer away, and reopen it with Command + comma.
   The close button must not flash or retain its previous hover highlight. Repeat by hovering
   another button and closing with Escape or Command + W; only the control currently under the
   pointer should highlight after reopening, and saved shortcuts and folder grants must remain.
   With multiple displays, open history on each display and invoke Settings with both its shortcut
   and the **…** menu. Settings must follow history even if it was previously opened on another
   display. With history hidden, open Settings from the menu bar and check the pointer's display.
8. Quit and relaunch to verify history persistence; test pause/resume separately.
9. Using a trackpad, click and slightly drag both selected and unselected rows, select preview text,
   and interact with search, filters, and footer controls; the window should stay in place. Move the
   dotted header handle less than 8 points and release; the window should stay still. Drag it farther
   to move the window. In Settings, repeat these checks by dragging the header title and empty
   header space. The close button and settings controls must still work without moving the window.
10. Copy two image files from one folder and a third from a nested folder. Use **Authorize Folder…**
    in a file's detail pane and select their shared parent. Confirm all three entries can preview and
    copy, then quit and relaunch and repeat. Copy a new image file into the same history from that
    folder and confirm it also works without another authorization. Canceling the picker or choosing
    an unrelated folder must leave the entry unchanged. Delete an original and confirm its preview
    becomes unavailable even though the folder is authorized.
11. In Settings → File Access, add a folder, reauthorize it without creating a duplicate, and remove
    its saved grant. Confirm original files and history remain intact and the folder list persists
    after relaunch. Check grant creation failure feedback on a folder the app cannot authorize.

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
