# Notch indicator: look and motion

Date: 2026-10-15. Scope: how the best notch apps and the Dynamic Island get their look and motion, and what to change in voz. This extends section 9 of [stack.md](stack.md). It does not repeat the window recipe or the spring table there.

Labels: "verified" means I read the source text. "Unverified" means a secondary source, memory, or a judgment. Judgments are marked "judgment".

Code reviewed in voz: `Sources/Voz/Indicator/*`, `Sources/VozCore/IndicatorLayout.swift`, `Sources/Voz/LevelTap.swift`, `Sources/VozCore/AudioLevel.swift`. Target is macOS 26.

## Summary

voz already matches boring.notch and VoiceInk on shape and springs. The gap is in the content, not the shell. The shell grows well. The content fades in as a flat opacity change, swaps between states with no transition, and the bars step at about 22 Hz. Polished notch apps enter content with blur, scale and opacity together, and drive bars from the display clock.

## (a) Principles with sources

1. Motion needs a purpose, and frequent actions need less of it. Emil Kowalski: UI animations "generally stay under 300ms", keyboard-initiated actions should not animate, and Raycast has none ([emilkowal.ski](https://emilkowal.ski/ui/you-dont-need-animations), verified). Rauno Freiberg: repeated animation "starts to feel more like cognitive burden after seeing the same animation for the hundredth time" ([rauno.me](https://rauno.me/craft/interaction-design), verified). voz opens on a hotkey that a user may press hundreds of times a day. Keep the open fast, and keep decoration small.
2. Use springs, and keep bounce low. Apple: default to bounce 0, add bounce for playful or physical motion, take care above about 0.4, and pick duration first ([WWDC23 10158](https://developer.apple.com/videos/play/wwdc2023/10158/), verified). Retargeting a spring keeps the current velocity, so interruptions stay smooth (same source). voz's open spring has about 20 percent bounce by the damping 0.8 setting (the damping-to-bounce mapping is unverified).
3. Make motion interruptible. Rauno: "Great interactions are modeled after properties from the real world, like interruptability" ([rauno.me](https://rauno.me/craft/interaction-design), verified). voz can be re-triggered during the close, so every change must retarget, not restart.
4. Keep content concentric with the container and keep margins even. Apple's Dynamic Island design session: content stays concentric with the island shape, with even margins, and does not poke into the corners ([WWDC23 10194](https://developer.apple.com/videos/play/wwdc2023/10194/), verified from a summary of the transcript). DynamicNotchKit states the same rule for code: "Outer Radius = Inner Radius + Padding" ([DynamicNotchStyle.swift L19-L21](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift#L19-L21), verified).
5. The island is elastic against a fixed hardware shape. Apple says it is "designed to feel like a living organism" with "deliberate elasticity" ([WWDC23 10194](https://developer.apple.com/videos/play/wwdc2023/10194/), verified from summary). Compact is the common view, and it should be as narrow as possible with content snug against the sensor region (same source).
6. Do not fake a second object during a swap. Emil: when a crossfade looks wrong, add a small blur (about 2 px for buttons, under 20 px always) so the eye reads one transforming object, not two overlapping ones ([emil-design-eng skill](file:///Users/joel/.claude/skills/emil-design-eng/SKILL.md), local skill, which paraphrases Emil's writing; I did not find the same text on emilkowal.ski).
7. Enter and exit asymmetrically. Slow where the user decides, fast where the system responds (emil-design-eng skill, same caveat). Exit should be faster than enter.
8. Delight goes where frequency is low. Benji Taylor on Family: "Delight-Impact Curve", frequent features get subtle touches, and persistent elements should not duplicate during a transition ([benji.org/family-values](https://benji.org/family-values), verified). A dictation indicator is frequent, so it gets subtle touches only.
9. Sound, haptics and visuals fire on the same frame, and only for meaningful events. This comes from the apple-design local skill, which cites "Designing Audio-Haptic Experiences". I did not fetch that session (unverified).
10. Honor Reduce Motion with a cross-fade, not zero feedback. Apple design skill and stack.md section 9d. voz already does this in `IndicatorView.swift`.

I could not read Apple's Live Activities HIG page (the fetch returned only the title). The "always black, content floats inside" rule is therefore unverified as a written Apple rule. The shipped behavior is clear: the hardware is black and the apps draw black.

## (b) Per-app technique notes

### DynamicNotchKit (MIT, 463 stars)

- Concave top corners: quad curve from the top-left to `(minX + topR, minY + topR)` with control point `(minX + topR, minY)`. Same shape as boring.notch and voz ([NotchShape.swift](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchShape.swift), verified via the boring.notch copy that credits it).
- Radii: compact top 6, bottom 14 ([NotchView.swift L28-L30](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchView.swift#L28-L30)). Expanded default top 15, bottom 20 ([DynamicNotchStyle.swift L45](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift#L45)).
- Content enters with three effects combined. Compact side content: `.blur(intensity: 10)`, then `.scale(x: 0, anchor: .trailing)` (leading side) or `.leading` (trailing side), then `.opacity` ([NotchView.swift L112, L125](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchView.swift#L112)). Expanded content: blur 10, scale y 0.6 anchored top, opacity ([L145](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchView.swift#L145)). The scale anchor points toward the notch, so content grows out of the hardware.
- The blur is a plain `.blur(radius:)` modifier used as a transition ([BlurModifier.swift](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Utility/BlurModifier.swift)).
- Springs: opening `.bouncy(duration: 0.4)`, closing `.smooth(duration: 0.4)`, conversion `.snappy(duration: 0.4)` ([L66-L79](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift#L66-L79)).
- Seam: the black background is padded by -50 so overshoot stays black, and the mask shape has 0.5 pt horizontal padding ([L61-L68](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchView.swift#L61-L68)). The reason for the 0.5 pt is not stated (unverified).
- Compact content gets an 8 pt side inset and 4 pt top and 8 pt bottom insets ([L108-L110](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchView.swift#L108-L110)).

### boring.notch (GPL-3.0, 11.0k stars). Read only, do not copy code

- Radii: closed top 6, bottom 14. Open top 19, bottom 24 ([sizing/matters.swift L18](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/sizing/matters.swift#L18)).
- Springs: open `spring(response: 0.42, dampingFraction: 0.8)`, close `spring(response: 0.45, dampingFraction: 1.0)`, and `.smooth` for gesture progress ([ContentView.swift L123-L128](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L123-L128)). A shared `interactiveSpring(response: 0.38, dampingFraction: 0.8)` drives hover and resize ([L41](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L41)).
- Seam: a 1 pt black rectangle overlays the top edge, inset by the top radius ([L105-L110](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L105-L110)).
- Shadow: black at 0.7 opacity, radius 6, only when open or hovered ([L111-L114](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L111-L114)). The window adds `shadowPadding = 20` so the shadow is not clipped ([matters.swift L15-L17](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/sizing/matters.swift#L15-L17)).
- Open content transition: scale 0.8 anchored top plus opacity, with `.smooth(duration: 0.35)` ([L354-L358](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L354-L358)).
- `matchedGeometryEffect` is used for album art and the spectrum so they move between closed and open layouts ([L398, L460](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L398)).
- Haptics: `.sensoryFeedback(.alignment, trigger:)` toggled on open, gated by a setting ([L184, L522-L523](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L184)).
- Visualizer: 4 `CAShapeLayer` bars, 2 pt wide, 14 pt tall, `transform.scale.y` animated between 0.35 and 1.0 with random targets every 0.3 s, and `preferredFrameRateRange` locked at 24 fps. It stops the timer and resets to scale 0.35 when not playing ([MusicVisualizer.swift L30-L34, L59, L73, L83](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Music/MusicVisualizer.swift)). This is the low-CPU approach. It is not level-driven.

### NotchDrop (MIT, 2.1k stars)

- Spring: `interactiveSpring(duration: 0.5, extraBounce: 0.25, blendDuration: 0.125)` ([NotchViewModel.swift L21-L24](https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchViewModel.swift#L21-L24)).
- Radius by state: closed 8, popping 10, opened 32 ([NotchView.swift L35-L41](https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchView.swift#L35-L41)).
- Concave corners without a path: two corner squares cut with `.blendMode(.destinationOut)` inside a `compositingGroup` ([L89-L136](https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchView.swift#L89-L136)). The `Shape` path in voz is simpler and animatable.
- Shadow: black, opacity 1 when open, radius 16 ([L83-L86](https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchView.swift#L83-L86)).
- Open content: scale plus opacity plus an offset of -height/2 ([L61-L66](https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchView.swift#L61-L66)).

### Atoll (GPL-3.0, 5.0k stars). Read only

- Springs: `.spring(response: 0.42, dampingFraction: 1.0)` for open and `0.45 / 1.0` for close in the modern path. Hover uses `.bouncy.speed(1.2)`. Content uses `.transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))` ([ContentView.swift L691-L711](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/ContentView.swift#L691-L711)).
- Tab content swap: opacity plus scale 0.965 with `.spring(response: 0.34, dampingFraction: 0.88)` on insert, scale 0.92 with `.smooth(duration: 0.22)` on removal ([L385-L389](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/ContentView.swift#L385-L389)). Exit is faster and smaller than enter.
- Shadow: black 0.6, radius 10 (or 5), only open or hovered, applied after `compositingGroup()` ([L676-L682](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/ContentView.swift#L676-L682)).
- Seam: a black rectangle of `notchTopScreenBleedAmount` height is added at the top ([L670-L674](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/ContentView.swift#L670-L674)).
- Recording badge: a live-activity row animates visibility with `.smooth(duration: 0.32)` in and `0.2` out ([RecordingLiveActivity.swift L57-L66](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/components/Recording/RecordingLiveActivity.swift#L57-L66)). The leading width animates from 0, so the badge grows out of the notch edge.

### MewNotch (GPL-3.0, 557 stars)

- Uses `NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)` in a small wrapper ([HapticsManager.swift](https://github.com/monuk7735/mew-notch/blob/main/MewNotch/Utils/Managers/HapticsManager.swift)).
- Hover shadow of radius 5 on the shape ([NotchView.swift L73-L74](https://github.com/monuk7735/mew-notch/blob/main/MewNotch/View/Notch/NotchView.swift#L73-L74)).
- I did not read its spring values.

### VoiceInk (the closest product to voz)

- Notch spring values match boring.notch (see stack.md 9d).
- Visualizer: 15 bars, 3 pt wide, 2 pt gap, 4 to 28 pt tall, in a `TimelineView(.animation(minimumInterval: 0.016))` ([AudioVisualizerView.swift L8-L24](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/AudioVisualizerView.swift#L8-L24)).
- Bar height: `pow(level, 0.7)` times `sin(time * 8 + index * 0.4) * 0.5 + 0.5` times a center boost `1 - 0.4 * distanceFromCenter` ([L48-L53](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/AudioVisualizerView.swift#L48-L53)).
- Idle: 15 flat bars at 4 pt, white at 0.5 opacity ([L58-L73](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/AudioVisualizerView.swift#L58-L73)). Active bars use 0.85 opacity.
- Processing: a label ("Transcribing") above a small progress animation, in a 28 pt tall box so layout does not shift ([L78-L112](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/AudioVisualizerView.swift#L78-L112)).

### Closed apps (described only)

- Superwhisper: the docs say a moving waveform shows the mic works, and a still waveform is a troubleshooting sign. The mini view keeps the waveform and shows a stop button on hover ([docs](https://superwhisper.com/docs/get-started/interface-rec-window), verified). A user thread says the waveform is tuned for consumer gear and reacts poorly to hot pro signals ([userjot](https://superwhisper.userjot.com/board/p/setting-to-lower-input-threshold-to-fix-waveform-animation), user report, search snippet only). Lesson: a fixed dB window needs a noise-floor margin.
- Wispr Flow: I found no design description. Unverified.
- Alcove, NotchNook: only store or news listings found, no design write-ups. Unverified.
- Siri glow and ChatGPT voice: Apple exposes no API for the Siri edge glow. Third-party recreations use a rotating angular gradient with layered blur ([vp0.com](https://vp0.com/blogs/apple-intelligence-siri-overlay-clone-swiftui), single secondary source). I found no verified source for ChatGPT voice mode. Neither fits a 36 pt notch wing.

### Apple APIs checked

- `blurReplace`: "A transition that animates the insertion or removal of a view by combining blurring and scaling effects", macOS 14+ ([Apple via sosumi](https://sosumi.ai/documentation/swiftui/transition/blurreplace), verified).
- `symbolEffect(_:options:isActive:)`: macOS 14+ ([Apple via sosumi](<https://sosumi.ai/documentation/swiftui/view/symboleffect(_:options:isactive:)>), verified). Draw On and Draw Off come with SF Symbols 7 ([WWDC25 337](https://developer.apple.com/videos/play/wwdc2025/337/) via search summary). The exact `drawOn` name and macOS 26 availability are unverified. Test with a build.
- `sensoryFeedback(_:trigger:)`: macOS 14+ ([Apple via sosumi](<https://sosumi.ai/documentation/swiftui/view/sensoryfeedback(_:trigger:)>), verified).
- `NSHapticFeedbackManager`: needs a Force Touch trackpad. The default performer "is based on the current input device" ([Apple via sosumi](https://sosumi.ai/documentation/appkit/nshapticfeedbackmanager), verified). A keyboard-triggered dictation may reach no trackpad, so the haptic may not fire (judgment).
- `NSView.displayLink(target:selector:)`: macOS 14+, "in-sync with the display the view is on", not called when the view is hidden ([Apple via sosumi](<https://sosumi.ai/documentation/appkit/nsview/displaylink(target:selector:)>), verified).
- `TimelineView`: the page I could read does not describe `.animation` or its refresh rate ([Apple via sosumi](https://sosumi.ai/documentation/swiftui/timelineview)). 120 Hz behavior of `.animation` is unverified.
- `contentTransition`: `interpolate` and `opacity` verified ([Apple via sosumi](<https://sosumi.ai/documentation/swiftui/view/contenttransition(_:)>)). `numericText` is not covered. voz shows no numbers, so it does not apply.

## (c) Prioritized changes for voz

Values come from the apps above. Where I chose a number myself, it says "judgment".

### 1. Content enters with blur, scale and opacity, anchored at the notch

File: `Sources/Voz/Indicator/IndicatorView.swift`, `notch` overlay (lines 50 to 61) and `IndicatorMotion.contentFade` (line 8).

Now: one opacity change, `easeOut(0.18).delay(0.14)` in, `easeIn(0.1)` out, on the whole HStack.

Change:

- Split leading and trailing into two views, each with `.transition(.blur(radius: 8).combined(with: .scale(x: 0.4, anchor: <toward notch>)).combined(with: .opacity))`. Leading anchor `.trailing`, trailing anchor `.leading`. This copies DynamicNotchKit ([NotchView.swift L112, L125](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchView.swift#L112)). Blur 8 is judgment (they use 10, Emil caps at 20).
- Enter animation: `.spring(duration: 0.34, bounce: 0.1)`, delay 0.08 for the leading dot, 0.12 for the bars (a 40 ms stagger, inside the 30 to 80 ms range in the emil-design-eng skill). Delay values are judgment.
- Exit animation: `.easeOut(duration: 0.12)`, no delay, no blur larger than 4. Atoll exits faster and smaller than it enters ([L385-L389](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/ContentView.swift#L385-L389)). Replace the current `easeIn`: Emil says ease-in feels slow on UI.
- Reduce Motion: opacity only, 0.2 s, as now.

### 2. State swaps (recording, transcribing, done, failed) animate

File: `Sources/Voz/Indicator/IndicatorContent.swift`.

Now: `IndicatorTrailing` and `IndicatorLeading` swap views in a `switch` with no transition. `RecordingDot` only animates its color.

Change:

- Key each trailing view by state and apply `.transition(.blurReplace)` with `.animation(.snappy(duration: 0.3), value: model.state)` on the container. This matches Atoll's `blurReplace` use and DynamicNotchKit's `.snappy(duration: 0.4)` conversion. 0.3 is judgment, shorter because the frame is small.
- Checkmark and exclamation: add `.contentTransition(.symbolEffect(.replace))` if the same `Image` view swaps, or `.symbolEffect(.bounce, value: state)` on arrival. Try `.symbolEffect(.drawOn)` for the checkmark on macOS 26 (unverified name, test).
- Keep the width fixed across states. Do not re-spring the shape on a state change. VoiceInk uses a fixed 28 pt box so layout does not shift ([L111](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/AudioVisualizerView.swift#L111)).

### 3. Bars driven by the display clock, not by an array shift

Files: `Sources/Voz/Indicator/LevelBars.swift`, `IndicatorModel.swift`, `IndicatorController.swift` (`pushLevel`, `levelHistoryInterval = 0.045`).

Now: 7 bars show the last 7 levels, pushed every 45 ms (about 22 Hz), animated `linear(0.06)`. Each push replaces `model.levels`, so the observed view body re-runs at 22 Hz. The bars step and the history scroll reads as jitter.

Change:

- Store the latest level in a small non-observed reference (a lock-protected `Float` or an `@unchecked Sendable` box), written from `pushLevel`. Remove `levels`, `resetLevels`, `levelHistoryInterval` and the array push.
- Render with `TimelineView(.animation(paused: state != .recording))` and a `Canvas` or 5 `Capsule` views. Pausing the timeline when not recording gives zero idle work. `LevelTap` already delivers at up to 60 Hz and already applies attack 0.04 s and release 0.18 s smoothing ([LevelTap.swift](../../Sources/Voz/LevelTap.swift)). Keep that smoothing and do not add a second one.
- Bar count 5. Width 3, gap 3, min height 3 (a dot at silence), max height 14. Judgment: fewer bars read as calm and stay readable at 14 pt. VoiceInk uses 15 in a larger window, boring.notch uses 4 at 14 pt.
- Height: `3 + 11 * pow(level, 0.7) * wave * centerFactor`, where `wave = 0.5 + 0.5 * sin(t * 8 + i * 0.4)` and `centerFactor = 1 - 0.4 * abs(i - 2) / 2`. The formula and constants are VoiceInk's ([L48-L53](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Recording/Components/AudioVisualizerView.swift#L48-L53)). `pow(level, 0.7)` lifts quiet speech. voz's `normalized` already maps -50 to -10 dB linearly. Keep the floor at -50 or lower to leave a noise margin (Superwhisper complaint above).
- Silent breathing: when `level < 0.04`, use `wave * 0.12` as the level so bars move slightly and show the mic is live. Superwhisper treats a still waveform as "mic not working" (docs above). The 0.04 and 0.12 values are judgment.
- Fill: white at 0.9 opacity (current). VoiceInk uses 0.85. No gradient, no glow.
- Reduce Motion: draw static bars scaled by level with no sine term.

### 4. Open and close timing for a high-frequency action

File: `IndicatorView.swift`, `IndicatorMotion` (lines 5 to 6), and `IndicatorController.showRecording` (30 ms sleep).

Now: open `spring(response: 0.42, dampingFraction: 0.8)`, close `spring(response: 0.45, dampingFraction: 1.0)`. These equal boring.notch and VoiceInk. They are correct for a notch app people hover. A hold-to-talk indicator opens far more often.

Change (judgment, from principle 1): open `.spring(duration: 0.34, bounce: 0.15)`, close `.spring(duration: 0.32, bounce: 0)`. Content delay 0.08 s. Reduce the 30 ms pre-expand sleep to one runloop turn, but only if the shape still animates from collapsed. If the open feels too fast on a real notch, go back to 0.42 and 0.8. Check by recording the screen and stepping through frames.

Keep: animating the width and both corner radii together, and retargeting on re-press.

### 5. Concentric radii and the seam

Files: `IndicatorView.swift` (radii on line 45 to 46), `NotchShape.swift`, `IndicatorLayout.swift`.

- Radii: expanded top 9, bottom 14 now. boring.notch closed is 6 and 14, DynamicNotchKit compact is 6 and 14. Set expanded top 6 and bottom 14 (judgment, to match the apps for a 36 pt wing). Apple's compact guidance wants content snug against the sensor ([WWDC23 10194](https://developer.apple.com/videos/play/wwdc2023/10194/)).
- Concentric content: the outer bottom radius is 14, so any rounded item near the bottom corner needs radius `14 - padding`. With 8 pt padding the inner radius is 6. The 3 pt bars are capsules and sit far from the corner, so no change there.
- Seam: add a 1 pt black strip above the top edge, inset by the top radius (boring.notch [L105-L110](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L105-L110)). Test on a real notch for a hairline between hardware and shape on fractional-pixel heights (judgment). DynamicNotchKit instead pads the black fill by 50 pt for overshoot ([L61](https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Views/NotchView.swift#L61)). voz overshoots with bounce 0.2 now, so check the shape does not show a gap at the outer edges.
- Collapsed width equals the notch width. Make it `notch.width + 2` so the shape overlaps the hardware edge by 1 pt per side (judgment).

### 6. Optional soft shadow when open

Files: `IndicatorView.swift`, `IndicatorLayout.swift` (panel padding), `IndicatorPanel.swift` (`hasShadow` stays false).

Shadow only helps over light wallpaper. Black at 0.5 opacity, radius 8, y 2, only when expanded. The apps use 0.6 to 1.0 with radius 6 to 16 ([boring.notch](https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift#L111-L114), [Atoll](https://github.com/Ebullioscopic/Atoll/blob/main/DynamicIsland/ContentView.swift#L676-L682), [NotchDrop](https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchView.swift#L83-L86)). The panel must add padding of about 2 times the radius on the sides and bottom, as boring.notch does with `shadowPadding = 20`. Apply `.compositingGroup()` before `.shadow` (Atoll does). Skip this if the panel padding makes the frame math in `IndicatorLayout` noisy. The value is small.

### 7. Recording dot

File: `LevelBars.swift` (`RecordingDot`).

Now: red 8 pt dot, scale 1.18 and opacity 0.65 over 0.9 s, repeating.

Change: keep the pulse. Replace it with a single opacity-and-scale breathing at 1.6 s per cycle with `easeInOut` (judgment: Apple's reduced-motion guidance in the apple-design skill warns about slow loops near 0.2 Hz, so 1.6 s is about 0.6 Hz). Add `.shadow(color: .red.opacity(0.5), radius: 3)` for a faint halo (judgment). Stop the loop for `done`, `failed` and `discarded`.

### 8. Sound and haptics

Files: `SoundCues.swift`, `scripts/make-sounds.swift`.

- Play the start cue in the same call that sets `isExpanded = true`, so sound and motion share a frame.
- `make-sounds.swift` uses a 2 ms attack and `exp(-70 t)` decay, which gives a short tick. Keep it. Add a second, softer cue for failure if you add a failure sound. Do not add a cue for done, because the stop cue already marks the end.
- Haptics: skip in v1. Keyboard dictation may not reach a trackpad, and Apple ties the performer to the current input device. If added later, use `NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)` on failure only, behind a setting (MewNotch pattern).

### 9. Idle cost

- The panel is already ordered out and the content view nil after close (`collapseAndHide`). Keep that.
- Pause the bars timeline outside `.recording` (change 3).
- `ProgressDots` uses `repeatForever`. It stops when its view is removed. Confirm with Instruments (Time Profiler and Core Animation) that no animation runs after the panel closes. No benchmark exists for this in my sources.
- Blur is cheap on a small view for under 0.4 s. A search result reports up to 50 percent CPU for a continuously animated blur ([AuroraView](https://github.com/OskarGroth/AuroraView), search snippet, secondary). Do not leave a blur running. The transitions above animate to 0 blur.

## (d) What to avoid

- Metaball or blob merging. It needs a blur then threshold pass ([ikyle.me](https://ikyle.me/blog/2026/creating-cool-ui-shape-morphing-directly-with-metal), secondary), costs GPU, and voz has one object, not two to merge.
- A rainbow or Siri-style glow. No public API, only third-party recreations, and it breaks the black-notch look.
- Random bar heights as in boring.notch's visualizer. It is cheap, but it does not reflect speech.
- Bounce above about 0.2 on open. Apple warns above about 0.4, and this action repeats all day.
- `ease-in` exits, `scale(0)` entries, and long delays before content (Emil, emil-design-eng skill).
- A persistent blur, gradient fills, inner highlights on a 36 pt black shape. They add cost and detract from the hardware match. I found no source showing a top app that uses them on the notch.
- `matchedGeometryEffect` for the bars. boring.notch uses it to move art between two layouts. voz has one layout, so a transition does the job.
- Hover tracking, click handling, and oversize panels (stack.md 9e). Keep `ignoresMouseEvents = true`.
- Copying GPL code from boring.notch, Atoll or MewNotch. Use the numbers and the technique only.

## Open items to test on hardware

1. Whether a 1 pt top strip or a +2 pt collapsed width removes any hairline at the notch.
2. Whether `TimelineView(.animation)` renders at 120 Hz on a ProMotion MacBook (unverified).
3. Whether `.symbolEffect(.drawOn)` compiles and plays on macOS 26 (unverified).
4. Whether open duration 0.34 with bounce 0.15 feels better than 0.42 with 0.8 after hundreds of presses.
5. Frame-step a screen recording of open, state swap and close at 0.25x speed.
