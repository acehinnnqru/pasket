# Developing Pasket

[Back to the README](../README.md) · [Release guide](RELEASING.md)

Build instructions, detailed behavior, storage design, and regression checks for contributors.

## Run locally

Open `pasket.xcodeproj` in Xcode, select the `pasket` scheme and My Mac, and run.
Pasket lives in the menu bar. At launch, it checks clipboard collection and automatic-paste
permissions before opening history. Missing access is explained in a setup window; use its
permission button to open System Settings. Clipboard collection needs Always Allow for
Paste from Other Apps, and automatic paste needs Accessibility access. The window rechecks
permissions in place as access is granted. Collection starts after setup finishes.
The setup window uses the same borderless material, cards, and buttons as Settings; drag its
header to move it. Clipboard instructions use two short steps and retain a Check Again action.
The window follows the height of the visible sections, keeping its top edge in place as content
changes. Scrolling is enabled only when the guide content exceeds the available body height.
Accessibility instructions show three steps: open System Settings, enable Pasket, and use the
always-visible Quit & Reopen Pasket button to apply access and continue setup. The Accessibility
page has no Check Again action or collapsed restart instructions. Open System Settings appears
to the right of step 1, and Quit & Reopen Pasket appears to the right of step 3. Both actions
are vertically centered in their rows and share the same right edge.
Permissions and shortcut guidance share one setup page. Each missing permission section appears
independently and disappears once access is detected. The shortcut guidance remains on that page;
after permissions are ready, Set Shortcut opens a recording dialog for preview and confirmation.
Saving or cancelling returns to the guide. Continue finishes setup, including when no shortcut
is assigned and the user prefers the menu bar. Never ask again is unchecked by default and only
suppresses future shortcut reminders when confirmed with Continue. Skipping without checking it
only dismisses the current launch; the next launch offers setup again if no shortcut is saved.
Every relaunch rechecks both permissions and the saved shortcut. Opting out never suppresses
missing permission sections, and existing saved shortcuts skip unnecessary shortcut guidance.
Its menu bar icon is a fixed monochrome basket with a P monogram. Settings → Dock icon → Show in Dock
controls whether Pasket appears in the Dock, including while Settings is open. It is off by default,
applies immediately, and persists across relaunch. Clicking the Dock icon opens history or brings
an open Settings window forward. The Dock icon color options
are Space Silver (the default), Orange, Mint, Blue, Lavender, and Graphite. Selecting a color
updates the running app's Dock icon immediately and saves it for the next launch. The bundled
Finder icon stays Space Silver; the menu bar glyph stays monochrome.
Settings → Accent color independently controls interface selections, buttons, and the collection
indicator. Choose System (the default) to follow the macOS accent color, or Blue, Purple, Pink,
Red, Orange, Yellow, Green, or Graphite. Changes apply immediately to history and Settings and
save automatically for the next launch.

Settings → Appearance selects Liquid Glass (the default) or Classic. Liquid Glass uses
the native regular glass material for panels and custom menus and follows the system's
Liquid Glass look and accessibility preferences. Classic preserves the frosted HUD
panel background and regular-material menus. Switching applies immediately to existing
windows and sheets and persists across launches independently of accent and Dock icon colors.
Neither choice overrides the system's light or dark appearance.

The menu bar's Statistics entry opens a separate window with Copies and History opens pages by local date and 7-, 30-, and 90-day
charts, daily counts, and previous/next period navigation. Both pages
include Today, Selected period, and Total summaries. Total covers every recorded date,
including dates outside the selected period. Counts accumulate across launches
and persist in UserDefaults independently of clipboard retention.

Copies initializes once from every saved history item's most recent copy date, before startup
retention cleanup. This is a baseline estimate: deduplicated repeats and already deleted items
cannot be recovered, and old dates are interpreted in the current local time zone. The scan
reads only timestamps from the full database, regardless of the visible page or filter.
An empty baseline also marks initialization complete; a failed history load leaves it pending.
Subsequent accepted external captures and successful writes from history each add one event,
including repeated content. Copying or pasting a combined group counts once; a paste queue
counts each successful item write. The monitor checkpoints Pasket's writes to avoid double
counting. Paused, private, unsupported, oversized, rejected, and missed clipboard changes
are excluded. Metadata updates, save retries, retention, and history deletion do not alter
counts. Clipboard monitoring still polls, so changes overwritten between polls cannot be counted.

History opens starts with its feature version. Each hidden-to-visible
presentation counts once, including startup, shortcuts, menu actions, and Dock reopen.
Focusing an already visible panel, hiding it, or showing setup, Settings, or Statistics does not count.
New events use the local Gregorian calendar when they occur; changing time zones does not
reassign earlier counts. Missing dates display zero, and Today refreshes while the page is open.
Repeatedly choosing Statistics brings the existing window forward. Drag its header to move it;
use its close button, Escape, or Command-W to close it. Settings remains a separate window.

- No global history shortcut is assigned by default. Use **Show Clipboard History** in the menu
  bar or configure **Show Clipboard History** in Settings. Existing saved shortcuts are preserved.
  Recorded combinations remain visible as drafts until **Save Shortcut** is clicked. Recording
  another combination replaces the draft; Cancel or Escape keeps the saved binding unchanged.
  Registration failures leave the dialog open without saving the candidate.
- The search field receives focus whenever the panel opens. Search the complete saved content or
  source app and filter by type. Arrow keys and row clicks change the selected entry while keeping
  the search field focused, so you can continue typing immediately.
- History is grouped by local calendar dates under **Today**, **Yesterday**, **7 Days** (2–7 days
  ago), and **30 Days** (8–30 days ago). Earlier entries appear under **Older**; empty groups are hidden.
  While searching, a single **Search Results** group preserves relevance order across dates.
- Click to select one entry, Command-click to toggle individual entries, and Shift-click to select
  a range across date groups. Command-Shift-click adds a range to existing selections. Shift-Up/Down
  extends or shrinks a range; plain arrows end the keyboard range while preserving mouse selections
  and Tab marks. Tab toggles a mark on the focused entry; a plain click replaces the selection.
  Search keeps keyboard focus, including its normal Command-A behavior. Search and type filters
  remove hidden entries from selection.
  **Select Recent ⇧Tab** after the footer's navigation hint, or Shift-Tab with search focused, selects the latest batch
  of external copies captured since launch. A batch spans at most five minutes and ends at a gap
  greater than 60 seconds. Duplicate entries are selected once; Pasket's own clipboard writes do
  not enter a batch. Search must be empty and the type filter must be All Types. The first use
  freezes the batch until history reopens; subsequent copies do not expand it. Large batches load
  additional history pages before selecting. Tab and arrow keys can adjust the resulting marks.
  The button appears only while a recent batch contains at least two distinct entries and hides
  when that batch expires. The collection indicator and total history count stay at the footer's left.
  Multiple selections show a numbered summary; inspect an entry without changing the selection.
  **Delete Selected** and the deletion shortcut affect the selection, with confirmation for multiple
  entries. A selected row's Delete context menu uses the full selection; an unselected row uses itself.
- With multiple entries selected, **Paste Together** combines text, links, and emails using a new
  line by default, writes images as separate PNG pasteboard items in one operation, or writes
  file entries as one group of file references. Multiple-image paste requires destination app
  support; the paste queue remains available for pasting images individually. The adjacent arrow opens
  paste options: choose New Line, Space, Blank Line, or None as the text separator, and toggle
  **Reverse Order**. The numbered summary reflects that order. Mixed selections other than
  text/links/emails cannot be combined. All selected content is loaded and all files are resolved before writing;
  an unavailable item stops the action instead of silently pasting a partial selection.
- **Start Paste Queue** freezes the selection in the displayed order and pastes the first item.
  If no Paste Next shortcut is configured, a dialog first prompts you to record one.
  **Save & Start Queue** checks and saves the shortcut, closes the dialog, and pastes the first item.
  **Skip for Now** starts with no shortcut; **Cancel** keeps the selection without starting or pasting.
  Move the caret to the next destination, then use **Paste Next** to paste each remaining item.
  Settings → **Paste Next** provides an optional shortcut with no default binding. Existing custom
  shortcuts skip the prompt. Clearing the shortcut leaves the menu and panel controls available
  and shows the prompt again the next time you start a queue. It does not assign Command-V
  or inspect the destination app's Paste menu.
  A configured shortcut is registered only while a queue is active, temporarily released in Pasket
  Settings, then unregistered on completion or cancellation. A held shortcut triggers only once per
  press. Normal automatic paste and queue delivery send Command-V to the destination application.
  The menu bar shows the remaining count, and the history panel and menu bar show the next item,
  the configured shortcut when present, Paste Next, and Cancel controls.
  Queues support individual text, link, email, image, and file entries without combining their formats.
  Search, type filters, and recency changes do not change the queue order. Each invocation pastes
  into the app active at that invocation; it never inserts Tab or Return automatically.
  Copying new content cancels the queue even when collection is paused. Cancelling, quitting,
  deleting a queued item, an unavailable item, or a failed paste stops the queue without skipping
  ahead or replaying it after a permission change. Opening history alone preserves the queue.
  Progress tracks paste requests sent, not confirmed insertion into the destination: macOS provides
  no general successful-paste receipt, and a pasteboard data request alone is not proof of insertion.
- Selecting a specific content type shows a return arrow and **Reset** to the left of the type selector.
  Click it to return to **All Types** while keeping your search text.
  The selector and its menu keep the same width across all content types.
- Settings → History panel → Remember type filter controls how long a type filter is kept
  after the panel closes: Never, 30 seconds, 1 minute (the default), 5 minutes, or Until Pasket quits.
  Reopening before the interval expires keeps the filter; reopening at or after expiry returns to
  All Types. The filter never resets while the panel is open. This preference saves automatically,
  but the active filter resets when Pasket quits. Search text clears on every open.
- The history panel borrows keyboard focus without activating Pasket, preserving the previous
  application's input focus and caret when it closes.
  It opens on the current desktop, including over full-screen apps. Switching away from its Space
  dismisses history without activating the previous application or following onto the destination desktop.
- **Return**, double-click, or **Paste** copies the complete item, closes the panel,
  and sends Command-V to the original application. Automatic paste requires event-posting
  permission, shown in **System Settings → Privacy & Security → Accessibility**. If permission
  is missing, the item is still copied and a native permission dialog offers **Open System Settings…**;
  press **Escape**, then use the original app's Paste command or paste shortcut. After granting permission, reopen
  history from the intended input and select the item again; permission changes never replay a paste.
  If access is already allowed but the permission dialog persists, choose **Quit & Reopen Pasket**
  in that dialog to refresh the running app. Pending history writes finish before quitting;
  failed writes still require a choice before quitting without saving. The replacement waits
  for the previous process to exit before loading history or registering shortcuts. If macOS
  cannot launch the replacement, Pasket stays open and displays an error.
  If you switch apps, reopen history, or change the clipboard before delivery, the pending paste is
  cancelled. Holding Return or shortcut modifiers delays delivery for up to one second.
- **Escape** dismisses the panel. With the filter, paste-options, or **…** menu open, Escape first
  closes that menu and restores search focus. All menus use the same custom appearance and support
  arrow keys and Return; clicking outside also closes them. Bottom menus open above their buttons.
- Notices appear as floating toast cards above the footer without moving the history list.
  Cleanup confirmations disappear after four seconds; other transient messages after eight seconds.
  Hovering or focusing a toast with accessibility tools pauses its timer. Each card has a dismiss button.
  Storage and history-limit problems retain their recovery action until dismissed or
  resolved. New messages appear first; dismissing one reveals any previous unresolved message.
  Reopening history restores unresolved storage and history-limit reminders.
- Startup checks guide users through missing clipboard and Accessibility permissions before
  shortcut setup. Later, automatic paste requests Accessibility if access was revoked, and
  resuming collection while clipboard access is denied offers to open System Settings.
  Opening history and background checks after setup do not display permission dialogs or toasts.
  Cancelling keeps saved history available; granting permission never replays a previous paste.
- The detail preview shows only content. Images fit the available space without scrolling;
  metadata and file access controls sit in the table below, which scrolls independently when needed.
  Long table values are truncated; hover to see the complete value.
- Move Settings by dragging its header title or empty header space. Dragging starts after
  8 points of movement; clicking entries, selecting text, and dragging other content do not
  move the window.
- Open the **…** menu after **Paste** and choose **Settings…** to change the global shortcut.
  Preferences persist; registration failures are shown.
  Settings opens centered on the history panel's display each time, including when reusing an
  existing settings window. When history is hidden, it uses the display under the pointer.
- **Command + ,** opens Settings from the history panel. Change **Open Settings** in Settings,
  use the reset icon to preview Command + comma, or **Clear Shortcut** in the recording dialog
  to preview disabling it, then confirm with **Save Shortcut**. The menu bar
  uses the same binding. Settings, history, and deletion shortcuts must use different combinations.
  Existing history or deletion bindings take priority if they already use Command + comma.
- Configure **Delete Selected Item** in Settings to assign a shortcut with Command, Control, or
  Option. It only works in the history panel, preserves search focus, and deletes the selected entries
  per key press, with confirmation for multiple entries. No deletion shortcut is assigned by default;
  use **Clear Shortcut** in the recording dialog and **Save Shortcut** to disable it. Clearing any shortcut requires confirmation;
  the global history shortcut can also be cleared to use the menu bar instead.
  The history, settings, deletion, and Paste Next shortcuts must use different combinations.
- Click the status light in the panel footer to pause or resume collection, or use the menu bar.
  While collecting, a small dot in the app's accent color gently brightens and dims every 2.8 seconds,
  with the Soft glow treatment: a matching halo strengthens and softens in sync. The icon does not move.
  Pausing turns the light gray and stops the animation. The separate item count and basket icon stay still.
  The animation respects Reduce Motion, and hovering over the light shows **Pause** or
  **Resume**. Use **Delete Selected** to delete one
  entry or a confirmed selection, or **… → Delete All Entries…** to clear history with confirmation.
  Rows also have a Delete context menu. Unmodified **Backspace** and **Delete** only edit the search;
  they never delete history entries, even when the search field is empty.
  Deleting the selected entry selects the next entry in the current list, or the previous entry
  if there is no next entry. Deleting the only entry clears the selection.
- Debug builds include a **Debug mode** toggle in the panel footer. Turn it on to show fictional
  text, links, email, an illustration, and a file reference for screenshots. Each date group has two
  samples, with dates refreshed whenever Debug mode is enabled. Search, filters, and
  previews use only these samples. Collection pauses and history actions are disabled while it is
  on. Turning it off restores your saved history and previous collection state. Samples and the
  toggle state are never saved; Release builds do not include this control or sample data.

macOS may request permission when Pasket first reads a new clipboard entry. Allow clipboard
access for background collection. If access is denied, use the collection control or
**Allow Clipboard Access…** in the menu bar to open the permission dialog and System Settings.
Pasket never changes your system privacy settings.

## Collection and limits

- Clipboard changes are checked every 350 ms while Pasket is running. Copies made and replaced
  between checks can be missed. Starting or resuming collection does not import the existing
  clipboard or replay copies made while paused. The pause state survives relaunch.
- Text is saved verbatim, including whitespace and line breaks, up to **2,000 Unicode characters**
  (extended grapheme clusters). Longer text is skipped with a visible message, never truncated.
  List summaries show up to 120 characters. The detail view displays the complete saved text,
  with scrolling for longer entries. Search and copying also use the complete saved text.
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
- **Delete Unavailable Files** in the bottom-right More menu checks file references across the entire
  history, regardless of the current search or filter. It removes an entry if any referenced file is
  missing or inaccessible, while keeping original files, readable file entries, text, and saved images.
- **Auto Recycle Unavailable Items** in Settings → History performs the same check when you close
  the history window, at most once every **5 minutes** during an app session. It is off by default, including for existing
  installations. Toggle it and choose **Apply** to save; the first check runs on the next close.
  Copying, startup, and hourly or wake maintenance do not trigger this file scan. Checks cover the
  entire history, regardless of search or filter. Manual **Delete Unavailable Files** remains available
  during the cooldown. History age, count, and storage limits keep their existing cleanup schedule.
  This also removes references to temporarily inaccessible files, such as files on disconnected drives.
- Up to 100 file references can be recorded together. Pasket retains paths and read-only
  security-scoped bookmarks when the system grants access, allowing those file references to be
  reopened after relaunch. Existing ordinary bookmarks are upgraded while accessible entries are
  checked, previewed, or copied; refreshed bookmarks are saved with history.
  The app-scoped bookmark entitlement is enabled for Debug and Release; App Sandbox and user-selected
  read-only file access remain enabled. Pasket displays original size when known and copies file URLs.
  Groups of files and other file types remain references without a backup of their contents. If an
  original is deleted or can no longer be read, the entry is marked **File unavailable** and cannot
  be copied. Its name and path remain visible; copy the original file again or delete the history
  entry. Access is handled automatically, without folder authorization settings or a restore-access
  prompt. A readable file that cannot be previewed shows **Preview unavailable** and can still be
  copied. Deleting history never deletes the original files.
- By default, keep up to **2,026 entries**, **50 MiB of text bodies**, **500 MiB of images including
  thumbnails**, and **60 days of history**. Settings → History lets you change each limit or choose
  Unlimited independently. All four settings are shown together, with current record count and
  text/image usage beside their inputs. Custom input fields align numbers and units in fixed columns;
  the entire input surface, including its unit label and padding, can be clicked to start editing.
  Clicking outside an input or pressing Return dismisses input focus. Unsaved edits are labeled,
  and Apply uses a solid accent background whenever valid changes are ready to save.
  Text storage includes text, links, and email bodies. File groups count as one entry; their original
  file sizes are excluded. Single-entry collection limits still apply.
- Cleanup first removes expired entries, then the oldest text entries when text storage is over its
  limit, then the oldest images when image storage is over its limit, and finally the oldest remaining
  entries when the record count is over its limit. Age and eviction order use the latest copy time;
  copying an entry renews its age, while searching or viewing it does not. Days are elapsed 24-hour
  periods. An incoming image that cannot fit its entire image budget, including its thumbnail, is
  skipped with a notice without evicting existing history.
- History limit edits remain drafts until **Apply**. If applying would delete anything, a second
  confirmation shows the number of entries and estimated storage to release, with both numbers in
  bold accent color. **Cancel** keeps the draft and leaves saved settings and history unchanged;
  **Apply and Delete** saves the settings and deletes the confirmed entries in one transaction.
  If the affected entries or storage estimate change before confirmation, review and confirm the
  updated impact again. Restore Defaults only changes the draft and also requires Apply.
- Cleanup runs at startup, after history writes, when limits are applied, every hour while running,
  and after waking from sleep, including while collection is paused. Upgrades without saved history
  limits keep existing entries and ask for review in Settings if adopting the defaults would delete
  anything; automatic cleanup remains disabled until limits are applied. If no deletion is needed,
  the defaults are adopted automatically.
- Saved image files are removed only after updated history is written successfully. Deleting,
  clearing, and skipping oversized entries leave the system clipboard unchanged. Folder grants and
  original files are retained. Text and image quotas measure saved content; database metadata,
  indexes, and free pages add overhead. Cleanup estimates include saved database record contents
  and existing image files, excluding original files, shared images, and in-flight imports. Substantial
  database free space is compacted after successful writes.

## Local storage

History uses a versioned SQLite database (`history.sqlite`) and a separate `Images` directory under
the app's Application Support/Pasket directory inside its sandbox. The system SQLite library is
used without third-party dependencies or network services. The list initially reads an ordered
identity/date index for all matches and 50 summaries, with at most 500 characters of text per row.
`ClipboardHistoryLayout` reserves the complete document height, including date headers, before
further summaries load. The view creates only rows near the viewport, with equal-sized placeholders
for unloaded items. Dragging the native scrollbar to an unloaded position reads the corresponding
50-item pages directly; it does not read every earlier page or expand the document as data arrives.
Concurrent requests for the same page share one read, cancelled viewport tasks do not cancel that
shared read, and results from obsolete queries or writes are discarded. Failed rows offer Retry.
Selection uses the full result order, so keyboard navigation and Shift-selection include unloaded
gaps. Selected ranges load their summaries before batch actions become available; copying resolves
all selected identities against full saved records. Reloads refresh retained summaries by identity.
A new search or filter starts with 50 summaries. Reopening resets the viewport and starts with the
first page, reusing the current result and its first-page summaries when they already match the
opening query and filter and are up to date. The layout is reused across view updates while the
ordered references, grouping mode, and local date boundaries stay the same.
Search runs against all saved records and their complete bodies, including records outside the
loaded pages. Whitespace separates keywords; every keyword must match, in any order, across the
title, body, source app name, or bundle identifier. Literal matching remains Unicode-aware and
ignores case and diacritics. Fields are split at Unicode newline boundaries before any matching;
a single keyword cannot combine characters from different fields or lines. Multiple keywords may
match different lines or fields. This applies equally to text and newline-separated file paths.

Search loads progressively: first literal phrases and keyword matches, then word initials, then
bounded ordered subsequences (`hlo` matches `hello`). Each level scans the complete filtered history
before pagination. An empty level automatically falls through to the next nonempty level. Otherwise,
scrolling to the end, pressing Down past the last result, or choosing **Find broader matches** loads
the next nonempty level. Earlier identities keep their order and selection, and stronger matches
are not duplicated. Changing the query, filter, or reopening starts again with literal matches.
The reserved scrollbar range covers the levels discovered so far, not undiscovered broader matches.

Word initials recognize whitespace, punctuation (including underscores and hyphens), camelCase,
and acronym boundaries: `lp` matches `LOKI_PHRASE` or `lokiPhrase`, and `xp` matches `XMLParser`.
Initials may skip words, but total skipped source characters cannot exceed 12 times the keyword
length, and no step may skip more than 24 source characters. Ordinary subsequences may skip at
most as many characters as the keyword contains (at least 50% match density), with no individual
step skipping more than three characters. Counts use Unicode grapheme clusters after folding for
ordinary subsequences; initials retain their positions in the original line. These limits apply
to every field and every query, including punctuation, without file-specific matching rules.

Whole-query literal matches rank first, then literal keyword matches, initials, and ordinary
subsequences ordered by their smallest total skipped-character count. Each keyword uses its best
match across fields and lines; the weakest keyword determines the record's level. Equal scores
keep newest copies first. Ranking happens before pagination. Search adds no persistent index or
schema changes; matching runs on existing text with a matcher held for the connection's lifetime.

Collection, deletion, copy-time updates, and settings changes update individual database records
in serialized transactions. Retention limits apply to the complete database. File bookmarks are
stored with their history entries; legacy folder grants are ignored and omitted when settings are
saved. Quitting waits for queued writes; failed writes show a retry action and require a choice before quitting
with unsaved changes. Media cleanup runs only after database changes commit successfully.

On first use, an existing version-1 `history.json` is validated and imported in one transaction,
including identities, timestamps, source metadata, image references, and pause state.
The original JSON is left unchanged, and subsequent launches use the database without reimporting
it. This retained JSON describes the history at migration time; image files continue to follow the
active database's retention and deletion rules. A damaged or unsupported database or legacy history
is left intact, and collection stops until it can be loaded. An existing database is never replaced
by a fallback import from JSON.

## Validation

[CI](../.github/workflows/ci.yml) runs on every pull request and can also be
started manually. It checks release tooling, runs the core suite,
and compiles the complete Debug app without signing using Xcode 27.1. New commits
cancel older runs for the same pull request or branch. The workflow uses read-only
repository permissions and does not require signing credentials. To require a
passing CI result before merging, select **Build and test** as a required status
check in the default branch's protection rule or ruleset.

### Runner setup

Unsigned macOS jobs use a runner with the `self-hosted` label. Signing jobs use
`MACOS_SIGNING_RUNNER` when configured, otherwise `self-hosted`. Install full Xcode 27.1
and complete its first-launch setup on the runner. Select that installation as
the machine's default command-line toolchain; for example, if it is installed
at `/Applications/Xcode.app`:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun swift --version
```

Use the actual installation path on that runner. This is a machine setup step,
not a workflow step. The workflows do not set `DEVELOPER_DIR` or install Xcode;
they verify that the selected Xcode reports version `27.1` before running tests
or compiling. Swift tests use `xcrun swift test` to resolve Swift through the
selected Xcode. If the runner environment already sets `DEVELOPER_DIR`, that
value overrides the machine's default and must point to the intended Xcode.

When replacing a runner, select Xcode on the new machine and assign the
appropriate job label. Its installation path can differ without changing the
workflows. A deliberate Xcode version upgrade also requires updating the
version checks in all four macOS workflows.

Self-hosted macOS runners can run unsigned checks or use a dedicated persistent
CI keychain for trusted signing jobs. Keep release runners separate from untrusted
PR builds. See [self-hosted signing setup](RELEASING.md#persistent-signing-on-self-hosted-runners)
for runner labels, secrets, reuse, and cleanup behavior.

### Profiling history opens

Record the Pasket process in Instruments with Time Profiler and a Points of Interest track.
Filter the signposts to subsystem `com.acehinnnqru.pasket`. Open and dismiss the panel one time
per sample, leaving enough time for background work to settle. Record the first opening separately
from repeated openings of an existing panel. Keep the history and build configuration consistent
across runs, and compare reopening unchanged history with reopening after a search, filter change,
or new copy.

- `History Panel Show` measures the synchronous AppKit opening path through the return of
  `makeKeyAndOrderFront`. `newPanel` distinguishes construction from reuse of the panel instance.
  Later SwiftUI rendering and asynchronous store work can continue after this interval.
- `History Presentation Result` records the store's decision when opening. The status is
  `reused`, `reload`, `debug`, or `unavailable` while startup or storage prevents a reload.
- `History Layout Build` measures the construction of scroll geometry and records the reference
  count. A view update that reuses geometry produces no build interval.
- `History Result Snapshot` measures one database result read, including its identity/date index,
  summary reads, and counts. Its end records the number of references read and the outcome.
  The interval starts when the persistence actor starts executing the read.

For each opening, count layout and snapshot intervals in the same observation window and compare
their durations alongside the Time Profiler samples. An interval reports elapsed time. CPU time and
first visible frame latency require separate measurements. Signpost details contain counts and
operational status fields.

### Local checks

Run `swift test` for the core suite. Tests use isolated named pasteboards and temporary fixtures;
they do not read or overwrite the real clipboard. They cover text boundaries, deduplication,
full-body search and copy, classification, source persistence, pause/resume, restart, deletion,
retention, damaged history, images and thumbnails, storage failures, and file references. SQLite
coverage includes legacy migration, transaction rollback, incremental writes, pagination, searches
of unloaded bodies, Unicode matching, and stable identities when repeating an unloaded entry.
Retention coverage includes category-specific eviction, overlapping limits, unlimited settings,
confirmation previews, changed victims with identical counts and sizes, expiry during confirmation,
copy renewal, upgrade review, paused maintenance, and rollback that preserves settings and images.
Settings input tests repeatedly switch and edit four fields in isolated AppKit and SwiftUI-hosted
windows. History limits use `SettingsTextField`, a native text field bridged into SwiftUI, so the
Settings window's shared TextKit 1 field editor handles editing. SwiftUI's `TextField` bypasses
the window's editor delegate and uses TextKit 2, where mouse selection while switching numeric
inputs has caused a main-thread hang. Other windows and secure text fields retain their normal editors.
Paste tests inject permissions, target state, keyboard release, and event delivery; they never send
real keystrokes. They cover dismissal order, held keys, permission denial and revocation, target exit,
app switches, clipboard changes, reopening, task cancellation, and timeout.
Dock icon preference tests cover the defaults, unknown saved colors, persistence across relaunch,
applying a selection only after its preference has been saved, and independent Dock visibility.
Accent color preference tests cover the system default, unknown saved values, every color's
persistence across relaunch, returning to System, and independence from the Dock icon preference.

For the desktop smoke test:

- Open history, then switch desktops with a trackpad gesture and Control-Left/Right. The panel
  must not remain over the destination desktop during the transition, return when switching back,
  or pull focus back to the previous application. Repeat between desktops showing windows from
  the same app, with a history menu or sheet open, and with separate Spaces on multiple displays.
  Switching only another display's desktop must leave history on the unchanged desktop open.
  Reopen history on each desktop and over a full-screen app; it must appear on the invoking display
  without switching desktops, accept search input, and preserve normal Escape and paste behavior.
  Repeat with Reduce Motion enabled. A paste pending during a desktop switch must be cancelled.
- With at least 600 history entries spanning several date groups, drag the scrollbar directly
  near the bottom before scrolling through earlier pages. Its thumb size and range should already
  reflect all matches; loading summaries or thumbnails must not shorten it or move the visible
  rows. Loading placeholders should be replaced in place. Jump back and forth quickly and verify
  only nearby pages load, Retry recovers a failed row, and search/type-filter changes cannot show
  old results. Repeat with search results, a type filter, light/dark appearance, and Reduce Motion.
  Navigate up and down across an unloaded gap with arrows and Shift-arrows, and Shift-click across
  the gap; copying and deletion must include every selected entry. Confirm the focused row stays
  visible, date headers stay aligned, accessible row names remain readable, and reopening starts
  at the top. Resize the panel while scrolled near the end and check that the viewport stays usable.
- Choose **… → Delete Unavailable Files** and verify a green cleanup toast appears above
  the footer without moving the list or covering its controls. Repeat after it disappears, and
  while it is still visible, to check that the notification restarts. Verify hover pauses dismissal,
  the close button works, and light/dark appearance and Reduce Motion remain readable.
  Without paste permission, verify attempting to paste displays a native permission dialog with
  **Cancel** and **Open System Settings…**, and the latter opens Accessibility settings.
  Cancel and reopen history: no permission dialog or toast should appear until another paste attempt.
  Choose **Quit & Reopen Pasket** and verify the app returns with saved history intact and a single
  working global shortcut. If history cannot be saved, Cancel must keep the app running without
  launching a replacement. Granting access and relaunching must not replay the previous paste.
  With clipboard collection denied, verify opening history remains quiet and the collection control
  or **Allow Clipboard Access…** menu action opens the permission dialog. Background polling must
  not reopen it after Cancel. Retry a failed history save and confirm its toast clears when storage recovers.
- In Settings → Accent color, select each swatch and verify selections, buttons, the Dock icon
  preview outline, and the history collection indicator use that color. Reopen history and Settings,
  then relaunch to check persistence. Select System to restore the macOS accent and check light
  and dark appearance. Changing the accent must preserve the selected Dock icon.
- Open Settings and verify Show in Dock is off and no Dock entry appears on a fresh installation.
  Turn it on and verify the Dock entry appears immediately with Space Silver.
  Select each of the six icon previews; the Dock icon and selected preview should update immediately.
  Close Settings with Escape, Command + W, or the close button and verify the Dock entry remains.
  Click the Dock icon to open history; with Settings open, clicking it should bring Settings forward.
  Repeatedly turn Show in Dock off and on and verify the Dock entry updates immediately while
  the same Settings window remains visible, focused, and usable without losing its scroll position
  or unsaved history limit edits. Close Settings immediately after toggling; it must stay closed.
  Close and reopen Settings, then relaunch with each visibility option to confirm both visibility
  and the selected color persist. The P menu bar glyph
  must remain monochrome in light and dark appearance, including while changing icon colors.

1. On a fresh installation, verify missing clipboard access appears before missing Accessibility
   access, and already granted permissions are skipped. Deny access or return from System Settings
   without enabling it: the corresponding permission section must remain visible. Missing permission
   sections must be independent, and the shortcut guide must stay on the same page. Allow access
   and reopen: verify permissions and the saved shortcut are checked again, granted permission
   sections disappear, and shortcut setup is offered when no binding is saved and reminders are
   enabled. No clipboard collection should occur before setup finishes.
   Check the setup window in light and dark appearance: it must have no system title bar, use the
   same material and button styling as Settings, and move only when its header is dragged.
   Accessibility must show the reopen step and button without expanding anything, with no
   Check Again action. Enable access, reopen, and verify setup continues. Expand the clipboard
   permission help and verify all instructions and recovery controls fit without clipping.
   Record a combination and verify its keycaps stay visible without saving. Record another to replace
   the draft, then click Save Shortcut. Test registration conflicts and recovery without losing the
   draft. Saving or cancelling recording must return to the same guide without completing it.
   Continue without a shortcut and without checking Never ask again: confirm no binding is saved,
   and the guide returns after relaunch. Check Never ask again and Continue: confirm shortcut
   reminders stop after relaunch, while revoked permissions still show their sections.
   Existing saved shortcuts must be preserved and skip unnecessary shortcut guidance.
   Dismiss history and copy `Pasket interaction check 2000` from a text editor.
2. Use your configured history shortcut or the menu bar; the search field should accept typing immediately.
3. Search `interaction check`, select the entry, and press Return.
4. With event-posting permission granted, confirm the panel closes, the item is pasted exactly once
   at the original caret or selection, and continued typing stays in that input without clicking.
   Repeat with double-click and **Paste**. Without permission, confirm the permission message appears,
   **Open System Settings…** opens Accessibility settings, and Cancel followed by Escape and Command + V still works.
   Grant permission and reopen history from the editor to retry; no delayed paste should occur.
5. Repeat with arrow-key selection, type filtering, Escape, and successive invocations. Escape and
   shortcut dismissal must restore the original input without pasting. Repeat in a browser input,
   a native text editor, and a full-screen app. Hold Return or modifiers, then switch apps or reopen
   history before releasing them; no stale paste should occur.
   Command-click separated rows, Shift-click across date groups, and Command-Shift-click to append
   a range. Extend and shrink with Shift-Up/Down, including across the first 50 loaded rows. Confirm
   plain arrows preserve mouse selections and Tab marks while moving focus, filtering drops hidden
   selections, and the numbered summary follows Reverse Order. Check every separator with text,
   links, and emails, and paste multiple file
   entries into Finder. Paste three images together into an app that supports multiple clipboard
   images and check normal and reversed order; also verify Paste Queue remains available.
   A missing file or image must leave the clipboard unchanged. Mixed types must offer
   Start Paste Queue as the primary action and explain why Paste Together is disabled.
   Start a queue in a text editor without a Paste Next shortcut: verify a shortcut prompt appears
   without changing the clipboard or editor. Cancel must preserve the selection without starting.
   Record a shortcut and choose Save & Start Queue: history must close and the first item must paste
   exactly once after the editor regains focus. Conflicts must keep the prompt open without saving
   or pasting. Reopen or dismiss history during the prompt: no pending queue may start later.
   Skip for Now must also paste the first item and leave the shortcut unset. With a saved shortcut,
   Start Paste Queue must paste the first item directly without a prompt. Move between fields,
   then use Paste Next from the shortcut, menu bar, or reopened panel to paste the second item.
   Verify one item per press with no repeats while held. Switch apps and confirm the configured
   trigger stays the same.
   Clear the shortcut during an active queue: the old trigger must stop working, normal Command-V
   must remain unchanged, and menu/panel Paste Next controls must still work. Verify Settings has
   no automatic app-following or paste-fallback controls. Confirm completion and cancellation release
   the configured shortcut, progress and the next title update, and changing search or selection does
   not reorder the queue.
   Verify Cancel, copying new content while collection is paused, deleting a queued entry, quitting,
   missing files, and revoked Accessibility all stop the queue without skipping or delayed replay.
   Check multi-selection and paste-options layouts at minimum panel size in light and dark appearance.
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
   rejecting the global history shortcut, and clearing the binding. Every recording, clearing, and
   settings-default restoration must wait for Save Shortcut; Cancel must retain the previous binding.
   Clear the history shortcut and verify menu bar access still works. Relaunch to verify persistence.
   Press Command + comma in the history search field to open Settings. Change Open Settings,
   verify the new binding works and the previous one stops working, then test clearing, restoring
   the default, conflict rejection, and persistence after relaunch. Recording and confirmation
   dialogs must not invoke the settings shortcut.
   Press Escape in Settings with different controls focused and after reopening the window;
   it must close Settings. While recording a shortcut, Escape must cancel only recording and leave
   Settings open.
   Close Settings with its × button, move the pointer away, and reopen it with Command + comma.
   The close button must not flash or retain its previous hover highlight. Repeat by hovering
   another button and closing with Escape or Command + W; only the control currently under the
   pointer should highlight after reopening, and saved shortcuts must remain.
   With multiple displays, open history on each display and invoke Settings with both its shortcut
   and the **…** menu. Settings must follow history even if it was previously opened on another
   display. With history hidden, open Settings from the menu bar and check the pointer's display.
8. Quit and relaunch to verify history persistence; test pause/resume separately.
9. Using a trackpad, click and slightly drag both selected and unselected rows, select preview text,
   and interact with search, filters, and footer controls; the window should stay in place.
   In Settings, drag the header title and empty header space less than 8 points and release;
   the window should stay still. Drag farther to move Settings. The close button and settings
   controls must still work without moving the window.
10. Copy image files from different folders, preview and copy them, then quit and relaunch and repeat
    while access remains available. Confirm Settings and the file detail pane have no folder
    authorization or restore-access controls. Delete an original and confirm its preview becomes
    **File unavailable**, copying is disabled, and the entry's name and path remain visible. Delete
    that history entry and confirm other original files remain untouched.
11. Copy a readable file with an image extension whose contents cannot be decoded as an image.
    Confirm its detail pane shows **Preview unavailable**, copying still works, and no permission
    picker or restore-access prompt appears.
12. In Settings → History, verify all four settings are visible with their default values (2,026 entries,
    50 MiB text, 500 MiB images, 60 days), independent Unlimited controls, and active usage. Enter
    zero, a negative number, a fraction, or an overflowing value and verify Apply is disabled.
    Reduce a limit enough to delete history and click Apply: verify the confirmation displays the
    entry count and estimated storage in bold accent color. Cancel with both the button and Escape;
    saved limits and history must stay unchanged, with the draft still present. Confirm with Apply
    and Delete, verify matching cleanup and persistence after relaunch, and test Restore Defaults.
    While confirmation is open, copy content that changes which entries would be deleted; the next
    confirmation must show the updated impact before anything is deleted under the new limits.
    Click inside each input and edit a value: valid changes must immediately highlight Apply with
    a solid accent background and show Unsaved changes, without requiring focus to leave the input.
    Click blank space inside the card, between cards, and in the header/footer; the input must lose
    its caret and focus border. Clicking another input must transfer focus normally, and clicking
    within an input must still support caret placement and text selection. Return dismisses input
    focus without applying changes. Restore Defaults remains a draft until Apply is clicked.
    Verify that numbers line up across all four inputs despite their different units. Clicking a
    unit label or input padding must focus that row's input; disabled Unlimited inputs stay inactive.
    Repeatedly switch directly between the four inputs, select and drag over digits, and click their
    unit labels and padding. Editing and selection must remain responsive without a spinning cursor.

Core tests and a successful build do not establish that this desktop smoke test passed.

On October 19, 2026, the user verified the main desktop flow: Hyper + P opened the panel,
search found the entry, Return copied it and returned to the original app, and Command + V
pasted the expected content. That check predates automatic paste and the nonactivating focus fix;
the updated desktop checks above have not yet been reported.

## Structure

- `MyApp.swift`: menu bar entry and application scene.
- `AppSetup.swift`: permission ordering and persisted shortcut setup completion.
- `PasketMenuIcon.swift`: resolution-independent monochrome basket and P menu bar glyph.
- `DockIconPreferences.swift`: saved Dock visibility and icon color selection.
- `ApplicationController.swift`: panel, settings, focus restoration, and termination handling.
- `AppRelaunch.swift`: launches the current app again and waits for the previous process to exit.
- `ContentView.swift`: search, filters, previews, and history controls.
- `PasketToast.swift` and `PasketToastView.swift`: shared notifications, recovery actions, and floating toast presentation.
- `SystemAccessController.swift`: permission dialogs requested by blocked user operations.
- `ClipboardModels.swift`: versioned records, classification, fingerprints, and limits.
- `ClipboardMonitor.swift`: polling, sensitive-type exclusions, and source estimation.
- `ClipboardFileAccess.swift`: file bookmarks, availability checks, and scoped access lifecycle.
- `ClipboardPersistence.swift`: SQLite history, migration, paged queries, image normalization, thumbnails, and cleanup.
- `ClipboardDatabase.swift`: system SQLite connection, bound statements, transactions, and Unicode search.
- `ClipboardStore.swift`: collection queues, retention, selection, copying, and management actions.
- `GlobalShortcut.swift` and `ShortcutSettingsView.swift`: shortcut registration and settings.
- `Tests/PasketCoreTests`: dependency-free core regression tests, runnable through SwiftPM.
