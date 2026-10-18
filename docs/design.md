# voz design

voz has a quiet, editorial look. It borrows from Wispr Flow (warm canvas, white panel, serif numbers) and adds stronger contrast and one brand color.

## Reference notes

- Wispr Flow uses a warm off-white canvas, a sidebar with line icons and a soft gray active pill, and one large rounded white card for content.
- Headlines mix roman and italic serif. Stats are large serif numbers with a small sans unit.
- History is grouped under small uppercase date labels. Rows show a muted time column and the transcript. Actions appear on hover.
- The primary button is warm orange.
- The research used only the product screenshot. The marketing site does not expose CSS values.

## Accent

| Name   | Light   | Dark    | On black |
| ------ | ------- | ------- | -------- |
| Indigo | #5163F9 | #6475FA | #7A8CFF  |

The brand accent is the blue from the app icon. voz uses it for the status dot and the Insights bars.

Controls use the macOS accent color (`Color.accentColor`): toggles, the accent button, checkmarks and the Copied label. They follow the color you pick in System Settings. Everything else is ink and gray.

## Color

| Token               | Light    | Dark     |
| ------------------- | -------- | -------- |
| canvas              | #F6F4EF  | #161618  |
| surface             | #FFFFFF  | #0E0E10  |
| ink                 | #141414  | #F2F0EB  |
| inkSecondary        | #5F5C55  | #A5A29A  |
| inkTertiary         | #7B7870  | #7F7C75  |
| hairline            | black 8% | white 9% |
| selected            | #E9E6DF  | white 9% |
| accent              | #5163F9  | #6475FA  |

The notch and pill stay black. Their recording dot uses the on-black accent. The bars stay white.

## Type

- Display and numbers: New York (`.system(design: .serif)`).
- UI and body: SF Pro.

| Role          | Font                                                      |
| ------------- | --------------------------------------------------------- |
| Page title    | serif 20, semibold                                        |
| Insights line | serif 24, semibold, tabular, numeric text transition      |
| Body          | SF 13, regular                                            |
| Row title     | SF 13, medium                                             |
| Meta          | SF 12.5, regular, inkTertiary                             |
| Section label | SF 12.5, regular, inkSecondary, sentence case             |

## Radii and spacing

- Radii: 8 controls and row highlights, 12 chips, 22 panel.
- Spacing scale: 4, 8, 12, 16.
- Panel width 360, padding 16. Scroll areas cap at 520 so the panel stays on screen.

## Depth

Hairline borders only. The panel has the system window shadow and a hairline border. Settings groups are bordered cards. The home list sits flat on the panel.

## Motion

- Press: scale to 0.97, 120 ms ease-out.
- Hover: background fade, 150 ms ease-out. Row actions fade in.
- Page change: cross-fade, 180 ms.
- Numbers: `.contentTransition(.numericText())` with `.smooth`.
- Indicator timing does not change.
- With Reduce Motion on, scale is removed and fades stay.

## Components

- Page bar: back chevron and serif title. Esc and Cmd+[ go back.
- Group: section label above one card with a hairline border, radius 12. Rows inside are split by hairlines. No fill.
- Row: title and short description left, control right.
- Section label: sentence case, small regular.
- Indicator picker: two tiles side by side, Notch and Pill. Each tile shows a small looping preview. The selected tile has a 2 pt accent border.
- Primary button: ink capsule. Accent button: accent capsule.

## Menu bar panel

voz has no main window. Everything lives in the panel under the menu bar icon.

- Home: status dot, status and shortcut hint, the last 5 transcripts, a stats line, and a footer with the language menu, retry, settings and quit. Search shows once there are more than 5 transcripts and takes focus when the panel opens. Return copies the first result.
- Click a transcript to copy it. Right-click to copy or delete.
- Transcript rows have no dividers. Hover shows a rounded highlight.
- Insights reads as sentences: a serif line with this week's words, then today, total, time saved, pace, streak and filler words. A 30-day chart and top apps follow.
- The stats line opens Insights. The gear opens Settings. Settings links to Dictionary.
- Settings has three groups: Dictation (shortcut, mode, language with model status, clean up, dictionary), Output and General. Permissions shows only while one is missing.
- Inline lists join with commas. No middle dots.
- First launch: the panel opens on its own with a setup checklist for the three permissions, language and usage stats. It stays open while you switch to System Settings. Done closes it and starts the model download.

## Menu bar icon

The icon is the full-color mouth from the app icon, `Resources/MenuBarIcon.png`, shown 16 pt tall. While transcribing, it drops to 45% opacity.

## Copy

- Use plain, short sentences. Write in active voice and present tense.
- Use sentence case for headings, labels, and buttons. Menu items follow macOS title case.
- Use one term per concept: dictate and dictation, transcript, shortcut, Dictionary, insert (for text that voz places in an app), recording.
- Hints that mention the shortcut use the configured shortcut name.
