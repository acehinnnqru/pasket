<p align="center">
  <img src="pasket/Assets.xcassets/AppIcon.appiconset/icon-128.png" width="96" alt="Pasket app icon">
</p>

<h1 align="center">Pasket</h1>

<p align="center">A little basket for everything you copy.</p>

<p align="center">
  A clipboard manager for macOS. Find something you copied earlier, preview it,<br>
  and paste it back into your work without losing your place.
</p>

<p align="center">
  <a href="https://github.com/acehinnnqru/pasket/releases/latest">Download for macOS</a> ·
  <a href="#features">Features</a> ·
  <a href="#getting-started">Getting started</a>
</p>

![Pasket clipboard history with date groups and an image preview](docs/images/history.png)

## Features

### Find what you copied

Keep text, links, email addresses, images, and file references in one searchable
history. Search saved text or the source app with multiple keywords or short character sequences
(`hlo` finds `hello`). Continuous matches come first, then word initials (`lp` finds
`LOKI_PHRASE`), then other character sequences with smaller gaps first. Filter by content type and browse
entries grouped by date. Preview text and images before choosing what to paste.

Open Pasket from the menu bar or your own shortcut. Start typing to search, use
the arrow keys to choose an entry, and press **Return** to paste into the app you
were using. **Escape** closes history and takes you back to your work.

### Paste several things together

Select multiple entries with **Command-click**, **Shift-click**, or **Tab**,
or use **Select Recent** (**Shift-Tab**) to select your latest batch of copies,
then choose **Paste Together**. Combine text, links, and emails with a new line,
space, blank line, or no separator. **Reverse Order** is on by default for both
Paste Together and Paste Queue, so items paste from bottom to top. Turn it off
in the paste options menu when needed. You can also paste multiple file entries
as a group. Select several images to paste them together in apps that support
multiple clipboard images. For other apps, use a paste queue.

![Pasket showing a numbered selection ready to paste together](docs/images/paste-together.png)

### Fill one field at a time

Use **Start Paste Queue** to work through a selection in order. Pasket pastes the
first item; move to the next field or app and use **Paste Next** for the next one.
Assign a shortcut for repeated use, or use the panel and menu bar controls.

Queues support text, links, emails, images, and files individually, so a selection
can contain different types. The next item and remaining count stay visible.
Copying something new cancels the queue.

![Pasket showing the next item and remaining count in a paste queue](docs/images/paste-queue.png)

### Keep history on your Mac

History is stored locally, with no account or cloud service required. Pause and
resume collection whenever you need to. Pasket skips clipboard entries marked
as concealed, transient, or automatically generated; unmarked content is
collected normally.

Choose your own retention limits for entry count, age, and text or image storage.
The defaults keep up to **2,026 entries** for **60 days**, within **50 MiB of text**
and **500 MiB of images**. Each limit can also be set to Unlimited.

Files stay in their original locations: history stores references, rather than
backups. Removing an entry from Pasket never deletes the original file.

### Make it feel at home

- **Menu bar access**, with an optional Dock icon and **Start at Login**.
- **Custom shortcuts** for history, Settings, deleting selections, and Paste Next.
- **Light and dark appearance**, with system or custom accent colors and six Dock icon colors.
- **Remembered type filters** for a duration you choose.
- **History cleanup**, including an optional setting to recycle unavailable file references.
- **Daily usage statistics** in a separate window from the menu bar's Statistics entry, with history opens by day and 7-, 30-, or 90-day trends.

## Getting started

Requires **macOS 26 or later**. Release builds support **Apple Silicon and Intel**.

1. Download the DMG or ZIP from [GitHub Releases](https://github.com/acehinnnqru/pasket/releases/latest).
2. Move **pasket.app** to **Applications** and open it.
3. Follow the setup guide to allow clipboard collection and grant **Accessibility**
   access for automatic paste. If prompted, quit and reopen Pasket to apply access.
4. Set a history shortcut, or continue with menu bar access. No history shortcut
   is assigned by default.
5. Copy something, open **Clipboard History** from the menu bar, and press
   **Return** on an entry to paste it.

## Development

For building from source, detailed behavior, storage, and validation, see the
[development guide](docs/DEVELOPMENT.md). Maintainers can find versioning,
signing, notarization, and publishing instructions in the
[release guide](docs/RELEASING.md).

## License

[MIT](LICENSE)

<sub>Screenshots show the app's Debug mode with fictional sample content.</sub>
