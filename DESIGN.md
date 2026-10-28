# Pasket Design Guidelines

## Purpose and status

Pasket uses compact macOS panels with quiet surfaces, clear hierarchy, and consistent
controls. Equivalent controls should share their geometry and behavior across screens.
Different roles, such as a control and its surrounding container, may use different sizes.
All dimensions in this document are logical points, not screenshot pixels.

This document records the implemented baseline for the history panel and Settings.
The shared corner shapes and Settings switch rows compile successfully in the full app.
Their latest visual changes still need an in-app visual review. Treat these values as
the current implementation standard, subject to deliberate revision after review.

## Shared components

Reuse these components when adding or changing equivalent UI. Extend a shared component
when the change belongs to every instance; avoid copying its implementation into a new view.

| Component | Location | Responsibility |
| --- | --- | --- |
| `PasketShape` | [ContentView.swift](pasket/ContentView.swift) | Compact, control, card, and menu shapes |
| `PasketButtonStyle` | [ContentView.swift](pasket/ContentView.swift) | Standard buttons and their interaction states |
| `PasketSurface` | [ContentView.swift](pasket/ContentView.swift) | Main panel material, outline, and clipping |
| `ClipboardMenuSurface` | [ContentView.swift](pasket/ContentView.swift) | Custom menu material, outline, and shadow |
| `SettingsToggleRow` | [ShortcutSettingsView.swift](pasket/ShortcutSettingsView.swift) | Settings switch size, alignment, title, and explanation |
| `SettingsSectionHeader`, `SettingsCard` | [ShortcutSettingsView.swift](pasket/ShortcutSettingsView.swift) | Settings grouping and card appearance |
| `ShortcutKeycaps` | [ShortcutSettingsView.swift](pasket/ShortcutSettingsView.swift) | Keyboard shortcut presentation |

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

Native switches, checkboxes, menu pickers, and system context menus retain macOS geometry.
Accent-color swatches remain circular, and status pills may use a capsule. Do not force
these semantic shapes into the rounded-rectangle scale.

Existing specialized surfaces are outside the shared shape migration: the image preview
uses a 12-point radius; toast cards use 14 points with a 9-point icon background; chart
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
| Switch title row to explanation | 4 |
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

## Typography and control sizing

Use the system font and semantic foreground styles. Use monospaced text for shortcut
keycaps and numeric history-limit inputs where stable character widths help scanning.

| Role | Size and weight |
| --- | --- |
| Main panel heading | 16, medium |
| Settings section heading | 12, medium, secondary foreground |
| Settings switch title | 13, medium |
| Settings switch explanation | 11, regular, secondary foreground |
| Standard button label | 12, regular, supplied by `PasketButtonStyle` |
| Menu item label | 13, medium |
| History row title / metadata | 13 regular / 11 regular, secondary metadata |
| Shortcut keycap | 12, medium, monospaced |

Standard buttons use 9-point horizontal and 6-point vertical padding through
`PasketButtonStyle`. Custom menu items have a minimum height of 32 and 8-point horizontal
content padding. History-limit inputs are 118 by 34. The History Apply button uses its
existing specialized style: height 32, horizontal padding 18, and a 12-point semibold label.
It still shares `PasketShape.control` with ordinary buttons and inputs.

Keep specialized emphasis intentional. A primary action may differ in fill or weight,
but equivalent controls should not acquire unrelated sizing or alignment per screen.

## Color, surfaces, and interaction states

Use `Color.accentColor` for selection, active controls, and focus feedback so the user's
accent preference applies consistently. Use primary and secondary semantic colors for
content hierarchy, red for destructive actions, and explanatory text with warning colors.
Do not rely on color alone to communicate state.

Reuse `PasketSurface` for main panels and `ClipboardMenuSurface` for custom menus.
Settings cards use a primary-color fill at 0.035 opacity through `SettingsCard`.
Reuse the existing state treatments in `PasketButtonStyle` rather than choosing new
opacity values for each button. Decorative outlines must not intercept input.

Keep history selection, focus, and hover distinct: selected rows use an accent fill;
the focused row receives an accent outline; hover feedback must not obscure selection.
Preserve menu checkmarks, selected accessibility traits, and disabled interaction behavior.
When changing state appearance, review all states of the component together.

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

Report which checks were actually performed and any remaining visual or interaction checks.
Do not describe a layout as visually verified based only on compilation. Documentation-only
changes need a consistency and link review, not another app build.

## Evolving the guidelines

Before adding a new visual value, check whether an existing role and component fit.
For a justified new role or a deliberate change to the baseline, update the shared
implementation and this document in the same change. Record the role and rationale for
exceptions. Do not copy unrelated legacy values into new controls or silently establish
a competing standard. Keep behavioral details in [DEVELOPMENT.md](docs/DEVELOPMENT.md).
