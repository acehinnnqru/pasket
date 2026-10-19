# pasket
A clipboard manager. Collect your contents into a basket.

## Running the skeleton

Open `pasket.xcodeproj` in Xcode, select the `pasket` scheme and My Mac,
and run. Pasket lives in the menu bar and opens its history panel at launch.

- Press **Control + Option + Shift + Command + P** (Hyper + P) to toggle the panel.
- Press **Escape** to dismiss it and return to the previous app.
- Search by content or source app, filter by type, and use the arrow keys to select an item.
- Press **Return**, double-click a row, or click **Copy** to copy a text, link, or email sample.
- Open **Settings…** from the menu bar or the panel's gear button to record a different
  global shortcut. The shortcut is saved locally. Registration failures are shown in settings
  and in the menu bar menu; canceling a recording restores the previous shortcut.

## Current scope

This is a native macOS interface and application lifecycle skeleton, built with SwiftUI,
AppKit, and the system hot-key API. It has no third-party dependencies.

The history uses sample data. Text samples can be copied to the real clipboard;
image and file samples are preview placeholders and cannot be copied.
Live clipboard monitoring, automatic classification, history persistence, retention,
and deletion are not connected yet. Only shortcut preferences persist between launches.

## Structure

- `MyApp.swift`: menu bar entry and application scene.
- `ApplicationController.swift`: floating panel, settings window, and app focus lifecycle.
- `ContentView.swift`: glass history panel, filtering controls, and previews.
- `ClipboardStore.swift`: sample records, search, selection, and copy actions.
- `GlobalShortcut.swift`: shortcut registration, conflict reporting, and saved preferences.
- `ShortcutSettingsView.swift`: shortcut settings and recording interface.
