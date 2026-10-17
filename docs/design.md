# voz design

voz is calm, editorial and premium. It takes the structure of Wispr Flow (warm canvas, sidebar, white content card, black hero card, serif numbers) and makes it bolder: larger type, stronger contrast, one confident accent.

## Reference notes

- Wispr Flow uses a warm off-white canvas, a sidebar with line icons and a soft gray active pill, and one large rounded white card for content.
- Headlines mix roman and italic serif. Stats are big serif numbers with a small sans unit.
- History is grouped under small uppercase date labels. Rows show a muted time column and the transcript. Actions appear on hover.
- The primary button is a single warm orange.
- Research was limited to the product screenshot. The marketing site exposes no CSS values.

## Accent

Two candidates:

| Name      | Light   | Dark    | Notes                                                                       |
| --------- | ------- | ------- | --------------------------------------------------------------------------- |
| Vermilion | #DC3E42 | #F0555A | Warm red. Matches the recording dot. White text passes 4.5:1 in light mode. |
| Clay rose | #CF4A6C | #E8648A | Cooler pink-red. Reads softer, less tied to recording.                      |

Chosen: Vermilion. It is clearly different from Wispr's orange, stays warm, and the recording dot, active states and primary actions share one color. It is used for the recording dot, the active sidebar marker, chart bars, switch tint, the hero accent word and the accent button. Everything else is ink and gray.

## Color

| Token               | Light    | Dark     |
| ------------------- | -------- | -------- |
| canvas              | #F6F4EF  | #161618  |
| surface             | #FFFFFF  | #0E0E10  |
| ink                 | #141414  | #F2F0EB  |
| inkSecondary        | #5F5C55  | #A5A29A  |
| inkTertiary         | #7B7870  | #7F7C75  |
| hairline            | black 8% | white 9% |
| hover               | #F7F5F1  | white 4% |
| selected (nav pill) | #E9E6DF  | white 9% |
| hero                | #0D0D0E  | #26262A  |
| accent              | #DC3E42  | #F0555A  |

The notch and pill stay black. Their recording dot uses the dark accent. Bars stay white.

## Type

- Display and numbers: New York (`.system(design: .serif)`).
- UI and body: SF Pro.

| Role          | Font                                                      |
| ------------- | --------------------------------------------------------- |
| Page title    | serif 40, semibold, tracking -0.8                         |
| Hero headline | serif 34, regular, italic accent word                     |
| Big number    | serif 44 to 72, regular, tabular, numeric text transition |
| Section title | serif 22, semibold                                        |
| Body          | SF 14, regular                                            |
| Row title     | SF 14, medium                                             |
| Meta          | SF 12.5, regular, inkTertiary                             |
| Date label    | SF 11.5, semibold, tracking 1.2, uppercase                |

## Radii and spacing

- Radii: 8 controls, 12 rows and chips, 16 inner cards, 22 content card and hero.
- Spacing scale: 4, 8, 12, 16, 24, 32, 44.
- Window 1100 x 720, minimum 900 x 600. Sidebar 232. Content card inset 12 from the window edge. Content padding 44.

## Depth

Hairline borders only. No drop shadows. The content card sits on the canvas with a hairline.

## Motion

- Press: scale 0.97, 120 ms ease-out.
- Hover: background fade, 150 ms ease-out. Row actions fade in.
- Section change: cross-fade, 180 ms.
- Numbers: `.contentTransition(.numericText())` with `.smooth`.
- Indicator timing is unchanged.
- Reduce motion drops scale and keeps fades.

## Components

- Sidebar item: icon, label, soft pill when active, accent dot marker.
- Card: surface fill, hairline, radius 16.
- Stat number: serif number plus sans unit.
- Section label: uppercase tracked date style.
- Primary button: ink capsule. Accent button: accent capsule. Hero button: white capsule.
- Setting row: title and description left, control right, hairline between rows.

## Windows

One main window with a sidebar: Home, Insights, Dictionary, Settings. The menu items History, Stats and Settings open the matching section. Onboarding uses the same canvas, serif headlines and ink button, one step per screen.

## Menu bar icon

A template glyph of four level bars drawn in code. Recording draws the bars in the accent color. Transcribing draws short flat bars.
