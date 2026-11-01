# Pasket Design Guidelines

## Purpose and status

Pasket uses compact macOS panels with quiet surfaces, clear hierarchy, and consistent
controls. Equivalent controls should share their geometry and behavior across screens.
Different roles, such as a control and its surrounding container, may use different sizes.
All dimensions in this document are logical points, not screenshot pixels.

This document records the implemented baseline for the history panel, Settings, statistics,
setup, recording and confirmation dialogs, and notifications. The latest shared component
changes still need an in-app visual and interaction review. Treat these values as
the current implementation standard, subject to deliberate revision after review.

## Shared components

Reuse these components when adding or changing equivalent UI. Extend a shared component
when the change belongs to every instance; avoid copying its implementation into a new view.

| Component | Location | Responsibility |
| --- | --- | --- |
| `PasketShape` | [ContentView.swift](pasket/ContentView.swift) | Compact, control, card, and menu shapes |
| `PasketButtonStyle` | [ContentView.swift](pasket/ContentView.swift) | Standard buttons and their interaction states |
| `PasketPicker`, `PasketPickerOverlay` | [ContentView.swift](pasket/ContentView.swift) | Single-selection dropdowns and their window-level presentation |
| `PasketPickerLabel`, `PasketPickerMenu` | [ContentView.swift](pasket/ContentView.swift) | Shared trigger labels and option menus for history, Settings, and statistics |
| `PasketCloseButton` | [ContentView.swift](pasket/ContentView.swift) | Window and notification close controls |
| `PasketMenuItemStyle` | [ContentView.swift](pasket/ContentView.swift) | Custom menu item geometry, colors, feedback, and selected traits |
| `PasketAppearance` | [AppearancePreferences.swift](pasket/AppearancePreferences.swift) | Shared, persisted surface appearance across windows and sheets |
| `PasketSurface` | [ContentView.swift](pasket/ContentView.swift) | Main panel material, outline, and clipping |
| `ClipboardMenuSurface` | [ContentView.swift](pasket/ContentView.swift) | Custom menu material, outline, and shadow |
| `SettingsToggleRow` | [ShortcutSettingsView.swift](pasket/ShortcutSettingsView.swift) | Settings switch size, alignment, title, and explanation |
| `SettingsControlRow`, `SettingsLabel` | [ShortcutSettingsView.swift](pasket/ShortcutSettingsView.swift) | Settings title and explanation layout for switches, pickers, shortcuts, and limits |
| `SettingsTextField` | [SettingsTextField.swift](pasket/SettingsTextField.swift) | Native numeric-input editing and focus, using the Settings window's compatible field editor |
| `SettingsSectionHeader`, `SettingsCard` | [ShortcutSettingsView.swift](pasket/ShortcutSettingsView.swift) | Settings grouping and card appearance |
| `ShortcutKeycap`, `ShortcutKeycaps` | [ShortcutSettingsView.swift](pasket/ShortcutSettingsView.swift) | Individual keycaps and keyboard shortcut groups |

Some helpers are file-private. If another screen needs one, expose or extract the shared
component instead of introducing another independent definition.

## Shape hierarchy

| Role | Radius | Implementation and use |
| --- | --- | --- |
| Compact element | 6 | `PasketShape.compact`: keycaps and small numbered markers |
| Control or selectable item | 8 | `PasketShape.control`: buttons, input outlines, menu items, history rows, and Dock icon options |
| Grouped content | 10 | `PasketShape.card`: Settings cards and shortcut recording area |
| Custom menu container | 14 | `PasketShape.menu`: control radius plus the 6-point `menuInset` |
| Main panel | 20 | Default radius of `PasketSurface` |

Shared shapes use `RoundedRectangle` with `.continuous` corners. Use the same shape
for an element's background, border, and rounded hit region. Hover, focus, selection,
and press states must not change the corner geometry. Dock icon options use the same
control shape for the selected outline and hover background; their full label remains
clickable, including the caption.

Custom menus use `PasketShape.menuInset` on all sides. Keep the outer radius derived
from the item radius and inset so changes preserve the relationship between the curves.

Native switches, checkboxes, and system context menus retain macOS geometry.
Dropdowns use the shared control shape for triggers and option highlights. Their menu
containers use the menu shape and `ClipboardMenuSurface`, sharing the material, outline,
and shadow of paste and more-action menus.
Accent-color swatches remain circular, and status pills may use a capsule. Do not force
these semantic shapes into the rounded-rectangle scale.

Existing specialized surfaces are outside the shared shape migration:
toast cards use 14 points with a 9-point icon background; chart
bars have their own geometry. These are existing local treatments, not additional defaults
for ordinary controls. Reassess them when changing those components and document any
new shared role here.

## Settings layout

| Relationship | Spacing |
| --- | --- |
| Between main Settings sections | 24 |
| Section heading to card | 10 |
| Main scroll content inset | 18 horizontal, 16 vertical |
| Standard card content inset | 12 on each side |
| Between blocks inside a standard card | 12 |
| Setting title or title row to explanation | 4 |
| History limit row inset | 12 horizontal, 10 vertical |
| Main Settings header and footer inset | 18 horizontal, 12 vertical; header close-control trailing inset is 14 |

Align setting titles and explanations to the card's leading content edge. Align trailing
switches to its trailing content edge. Let explanations wrap and increase the row height;
do not truncate essential setting descriptions to force equal card heights.

Use `SettingsToggleRow` for Start at Login, Show in Dock, automatic cleanup, and equivalent
Settings switches. It defines:

- A leading title and a trailing native switch, vertically centered in a title row with
  a minimum height of 24.
- `.toggleStyle(.switch)`, `.controlSize(.small)`, and `.fixedSize()` on the switch.
- A 12-point horizontal stack spacing and a spacer with a minimum length of 12.
- An explanation below the title row, separated by 4 points.
- A full-width layout; the containing card or row supplies the 12-point inset.

Do not mix a standalone labeled switch with a manually aligned switch row for equivalent
settings. Keep native checkboxes for inline choices such as Unlimited; they serve a
different layout role and do not need to become switches.

Use `SettingsControlRow` for a title with a trailing control and an explanation below,
including switches and the type-filter picker. Use `SettingsLabel` for stacked title and
explanation text beside a shortcut or numeric input. Both use 13-point medium titles,
11-point secondary explanations, and a 4-point gap. Additional card-wide notes remain
separate blocks with 12-point spacing. Use `PasketPicker` for dropdown controls.

## Setup and dialog layout

Setup and shortcut-recording panels use the same outer alignment as Settings:

| Region | Insets or spacing |
| --- | --- |
| Header and footer | 18 horizontal, 12 vertical |
| Content | 18 horizontal, 16 vertical |
| Setup sections | 24 between sections |
| Setup introduction, card, and supporting blocks | 16 between blocks |
| Setup card rows | 12 on each side |
| Recording content blocks | 12 between blocks |
| Standalone cleanup confirmation | 18 on each side, 16 between blocks |

The cleanup confirmation has no separate header or footer bands, so its single inset
applies to the title, explanatory content, and actions. Setup permission-row dividers
start at 44 points: 12-point inset plus a 22-point number marker and a 10-point gap.
The recording area's 64-point height remains a deliberate content presentation size.
Setup section introductions may use 18-point headings to explain a step; they are not
ordinary setting labels. Statistics retains its chart-oriented content layout and
18-point content inset, while its navigation actions use the standard button style.
Its Copies and History opens page controls reuse `PasketButtonStyle(isActive:)`, with
selected accessibility traits, a 10-point gap, an 18-point horizontal inset, and a
16-point top inset. Both pages share the same summary, date controls, chart, and daily list
layout; the page controls stay above the scrolling content for stable navigation.

## Typography and control sizing

Use the system font and semantic foreground styles. Use monospaced text for shortcut
keycaps and numeric history-limit inputs where stable character widths help scanning.

| Role | Size and weight |
| --- | --- |
| Main panel heading | 16, medium |
| Settings section heading | 12, medium, secondary foreground |
| Settings title | 13, medium |
| Settings explanation | 11, regular, secondary foreground |
| Standard button label | 12, regular, supplied by `PasketButtonStyle` |
| Menu item label | 13, medium |
| History row title / metadata | 13 regular / 11 regular, secondary metadata |
| Shortcut keycap | 12, medium, monospaced |

History uses a reserved document height calculated from the complete matching identity/date
index for the discovered search levels. A search starts with ordinary matches and expands to
initials and fuzzy results only when requested at the end; an empty level advances automatically.
A **Find broader matches** footer uses `PasketButtonStyle` and reserves one existing 50-point row
outside the identity index. It provides a keyboard and accessibility alternative to scrolling past
the end, shows progress during expansion, and preserves earlier rows and selection when appended.
The scrollbar grows when a broader level is discovered, while loading summaries within a level
keeps its range fixed. `ClipboardHistoryLayout` defines 50-point item rows, a 3-point gap, and an 8-point
outer inset. Date headers reserve 24 points for the first group and 38 for later groups,
matching their existing top and bottom padding. These fixed roles let the native scrollbar
represent all matches before summaries or thumbnails load. Loading and retry placeholders
occupy the same 50-point row as their eventual content; thumbnail arrival must not resize it.
Only rows near the viewport are instantiated. Keep the title and metadata on one line each,
and preserve selection, hover, focus, keyboard navigation, and accessible labels in loaded rows.

Standard buttons use 9-point horizontal and 6-point vertical padding through
`PasketButtonStyle`. Settings scroll content uses `.controlSize(.small)`: the shared button
style uses 9-point horizontal and 4-point vertical padding with a minimum height of 26.
This keeps text actions and picker triggers aligned with the numeric inputs without
reducing label sizes. Shortcut buttons retain their 22-point keycaps and grow to 30 points
with this padding. Native inline checkboxes also use the small control size; Settings
header controls retain their regular geometry.

History-limit inputs are 108 by 26, with 8-point horizontal padding, regular-weight
13-point monospaced values, and the existing 11-point units. Their compact outline reduces
visual weight beside the two-line labels; row insets and explanation spacing stay unchanged.
Use `PasketButtonStyle(isProminent: true)` for the History Apply button, matching other
primary actions such as Paste. It uses the standard small sizing: minimum height 26,
horizontal padding 9, and a 12-point regular label, matching Restore Defaults in height.
Primary actions share a subtle accent fill and outline instead of a separate solid-fill style.

Custom menu items have a minimum height of 32 and 8-point horizontal content padding.

Use `PasketPicker` for the statistics date range, Settings type-filter memory, and equivalent
single-selection dropdowns. All three screens, including the history type filter, share
`PasketPickerLabel` and `PasketPickerMenu`. Triggers use `PasketButtonStyle(isActive:)`:
opening the menu applies the accent fill and outline and turns the chevron upward.
The shared label uses 13-point medium text, an 8-point gap, a 10-point semibold chevron,
5-point horizontal inset inside standard button padding, and an 18-point minimum label
height. Optional content-type icons occupy 16 points. Reserve the longest option's width
to prevent layout shifts. The history trigger retains its 130-point label width for the
search bar layout; other selectors size to their option text.
Use tabular digits in selector labels. The statistics date-range selector aligns values
to the trailing edge of the text column in both the trigger and menu. Its shared `days`
suffix stays in one position, with 7, 30, and 90 aligned by their units digit. Other
selectors retain leading alignment; the numeric alignment does not move the indicator column.

Dropdowns use the matching-option-size design (option B): options form one vertical
column with a 2-point gap, using the picker variant of `PasketMenuItemStyle`.
Every option matches its trigger's measured width and height (26 points high in Settings,
normally 30 elsewhere), rather than the 32-point grouped-menu row. A 14-point horizontal
content inset matches the trigger's combined 9 + 5 inset.
Use `ClipboardMenuSurface` for the continuous background around the options: native regular
Liquid Glass in the Liquid Glass appearance, or regular material with a subtle outline and
shadow in Classic. The background covers the spaces between options as well
as the rows. Keep labels, icons, selection highlights, and hit regions sharp, and the
decorative outline noninteractive.
The menu has a 6-point inset on all sides, so its background is 12 points wider than the
trigger while each option remains exactly trigger-sized. Offset the menu 6 points toward
the leading edge to align the option column with the trigger, subject to window bounds.
Selected options have accent text, a 0.08 accent fill, and a right-aligned checkmark.
Picker options also use accent text and icons on hover, with an additional 0.12 accent
fill (0.18 while pressed). Selection remains distinguishable by its persistent checkmark.
Do not substitute a native menu for these dropdowns. Keep accessible titles, values, and
selected traits. Up/Down move the highlight, Return selects, and Escape dismisses before
the containing window can close. Clicking outside dismisses without changing selection.

Apply `PasketPickerOverlay` to the containing window after `PasketSurface`, outside scroll
views, so option menus are not clipped by cards or scroll content. Place the menu 4 points
below its trigger, or above when space below is insufficient. Restore focus to the trigger
after dismissal. History retains its existing overlay and search-focus handling while
using the same label, menu, and interaction styles as the other screens.

On opening, the menu and its backdrop fade in together from 94% vertical scale and a
6-point offset toward the trigger, with a spring response of 0.28 seconds and damping
fraction 0.88. Anchor this motion to the nearest edge of the trigger. The chevron rotates
over 0.18 seconds. With Reduce
Motion enabled, both changes happen immediately without movement. The final geometry and
keyboard selection behavior are independent of the animation.

Use `PasketCloseButton` in Settings, statistics, and notifications. It has a 12-point medium
close icon in a 14-by-16 label frame; standard button padding makes the control 32 by 28.
Provide a context-specific accessible label and help text. Window callers add Command-W;
notifications do not acquire a window-close shortcut.

Use `ShortcutKeycap` for both shortcut groups and inline navigation hints. Each keycap uses
12-point medium monospaced text, a minimum content width of 12, horizontal padding of 5,
height 22, the compact shape, a primary fill at 0.045 opacity, and a primary border at 0.08.
`ShortcutKeycaps` groups these with a 4-point gap and a combined accessible shortcut name.

Keep specialized emphasis intentional. A primary action may differ in fill or weight,
but equivalent controls should not acquire unrelated sizing or alignment per screen.

## Color, surfaces, and interaction states

Use `Color.accentColor` for selection, active controls, and focus feedback so the user's
accent preference applies consistently. Use primary and secondary semantic colors for
content hierarchy, red for destructive actions even at rest, and explanatory text with warning colors.
Do not rely on color alone to communicate state.

Reuse `PasketSurface` for main panels and `ClipboardMenuSurface` for custom menus.
Settings exposes one Appearance picker, using `SettingsControlRow` and `PasketPicker`,
with Liquid Glass (the default) and Classic options. The selection applies immediately,
persists across launches, and is independent of accent and Dock icon colors.

Liquid Glass uses the native `.glassEffect(.regular, in:)` on the complete panel or menu,
so the system handles both its material and foreground legibility. Preserve the existing
20-point panel and 14-point menu shapes. Let the native material respond to the system's
Liquid Glass look, Reduce Transparency, and Increase Contrast preferences; do not map
Clear and Tinted to hard-coded opacity values or read private system preference keys.
Do not add the Classic white wash, decorative border, or custom menu shadow over native
glass. These would obscure its adaptive material and duplicate its edge treatment.
History rows, cards, and buttons retain their subtle content and interaction fills instead
of acquiring individual glass layers. Floating menus remain outside `PasketSurface` so
their material and option labels are not part of the main panel's glass content.

Classic retains the existing behind-window HUD material, white wash, and panel outline.
Its custom menus use `.regularMaterial` without an additional solid color fill or tint,
with the existing outline and shadow. Both appearances preserve view identity when
switching, so changing the material does not rebuild content, reset scroll positions,
or discard input focus. Reserve accent fills for option selection and interaction feedback.
Settings and equivalent setup cards use `SettingsCard`. In Liquid Glass, use a
primary-color fill at 0.08 opacity to separate grouped content from the glass panel.
Classic keeps the 0.035 primary fill. Both appearances use the same card shape and
geometry, with fill alone defining the group boundary. The shortcut-recording target
shares this fill through `SettingsCard` and retains its existing dashed outline as
a distinct recording affordance.
Reuse the existing state treatments in `PasketButtonStyle` rather than choosing new
opacity values for each button. Decorative outlines must not intercept input.

Keep history selection, focus, and hover distinct: selected rows use an accent fill;
the focused row receives an accent outline; hover feedback must not obscure selection.
Preserve menu checkmarks, selected accessibility traits, and disabled interaction behavior.
When changing state appearance, review all states of the component together.

History image previews and loaded thumbnails have no added background fill, so image
transparency and aspect-fit margins reveal the surrounding panel or row surface.
Keep the preview's 12-point content inset and the thumbnail's 30-point frame for stable
layout. Icon tiles retain their muted control-shaped fill when no thumbnail is available;
row selection, hover, and focus treatments remain independent of image presentation.

Custom picker, paste, and more-action menus share `PasketMenuItemStyle`. Grouped menus
use a primary hover fill at 0.04 opacity and a pressed fill at 0.08; picker
options use the accent interaction treatment described above. Selected options also have an
accent fill at 0.08, accent text, a checkmark, and the selected accessibility trait.
Disabled rows use 0.35 opacity and do not show hover or press feedback. Mouse exit clears
the highlighted row in these menus; arrow keys can establish a highlight again.
The paste menu retains the last active row for Return and continued arrow navigation after
mouse exit, so clearing a hover cannot unexpectedly switch the action to Paste Together.
The filter and more-action menus retain their existing selection/default fallbacks. Keep number shortcuts
and Escape dismissal intact. Menu separators use the same 8-point horizontal inset.

Prominent buttons use accent text, a 0.08 accent fill, and a 0.12 accent outline at rest.
Hover increases the fill to 0.12 and the outline to 0.2; pressing increases the fill to 0.2.
Disabled prominent and active buttons use secondary gray instead of the accent color and
the shared 0.35 disabled opacity, with no hover or press feedback. Destructive actions
retain their red tint. Apply is disabled until valid changes or a required history-limit
review can be saved; loading, storage restrictions, and an in-progress apply also disable it.
Ordinary buttons retain their existing subtle fill and outline treatments. All buttons
share hover tracking, press handling, corner geometry, and Reduce Motion behavior.

Use the existing short button transitions (0.12 seconds for interaction and 0.08 seconds
for press feedback). Respect Reduce Motion. Visual changes must preserve keyboard focus,
menu navigation and dismissal, and the ability to select text inside inputs.

## Accessibility and validation

Preserve accessible names, values, hints, and stable identifiers when extracting controls.
An icon-only control needs an accessible label. A switch whose visible native label is
hidden must retain its accessible title; `SettingsToggleRow` also supplies its explanation
as a hint. Disabled controls must remain visibly distinguishable and noninteractive.

For UI changes, build the full app using the unsigned command in [AGENTS.md](AGENTS.md).
Compilation is separate from visual and interaction validation. When UI inspection is
available, review affected components in light and dark appearance, including hover,
pressed, selected, focused, and disabled states as applicable. Check wrapping, keyboard
operation, accessible labels, and Reduce Motion when the change affects them.
For surface changes, also review both app appearances and the system's Clear/Tinted,
Reduce Transparency, and Increase Contrast settings. Check that switching appearances
keeps open-window content and keyboard focus intact, and that menus remain readable.

Report which checks were actually performed and any remaining visual or interaction checks.
Do not describe a layout as visually verified based only on compilation. Documentation-only
changes need a consistency and link review, not another app build.

## Evolving the guidelines

Before adding a new visual value, check whether an existing role and component fit.
For a justified new role or a deliberate change to the baseline, update the shared
implementation and this document in the same change. Record the role and rationale for
exceptions. Do not copy unrelated legacy values into new controls or silently establish
a competing standard. Keep behavioral details in [DEVELOPMENT.md](docs/DEVELOPMENT.md).
