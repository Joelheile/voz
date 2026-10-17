# Speed research

Date: 2026-10-16. Target: macOS 26, Apple Silicon, M2 Pro dev machine.

Goal: key release to inserted, cleaned text in 1.5 s or less for any dictation length. Tiny. No idle load. Always running.

This file does not repeat `stack.md` or `cleanup-prompt.md`.

Measurement caveat: all local numbers were measured on this machine with load average 10 to 18 and a disk at 100% (about 2 GiB free). Treat them as noisy. Published numbers are cited by source number. "Unverified" means no primary source or measurement backs the claim.

## 1. Latency budget (key release to text)

Typical 5 to 15 s dictation, M2 Pro.

| Stage                                             | Today (measured or estimated)                                                                                 | Target                                                               |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Capture tail flush and stop                       | under 30 ms (estimate)                                                                                        | 30 ms or less                                                        |
| STT                                               | 99 to 127 ms for 11.9 s of audio (measured, about 100x RTFx)                                                  | about 40 ms on the tail only, 120 ms or less with no incremental STT |
| Rule pass                                         | about 5 ms (estimate)                                                                                         | about 5 ms                                                           |
| FM cleanup                                        | 700 ms for 17 words, 1044 ms for 38 words (measured medians, current prompt); times out past 2 to 3 sentences | 300 to 500 ms for the last sentence only (trimmed prompt, prewarmed) |
| Join and guard                                    | about 5 ms                                                                                                    | about 5 ms                                                           |
| Paste (pasteboard write, 50 ms delay, 4 CGEvents) | about 60 ms                                                                                                   | about 60 ms                                                          |
| Total                                             | 0.9 to 1.2 s for short text, raw-text fallback for long text                                                  | 0.55 to 0.75 s, hard cap 1.5 s with raw-tail fallback                |

Cold start is separate. First model load after a lost Core ML cache took 22.9 to 28.6 s (measured). Warm load took 0.15 to 0.48 s.

## 2. Findings

### Q1. Streaming and incremental STT

- STT is not the bottleneck. The batch Parakeet v3 run took 0.099 to 0.127 s for 11.87 s of audio on this machine (measured). At about 100x RTFx, 3 min of audio takes about 1.5 s. Incremental STT matters only past about 60 s of audio.
- The Core ML encoder takes a fixed 15 s window. Longer audio is split into overlapping windows merged on a 2 s overlap [1][3]. Encoder time per window: 17.8 ms GPU, 23.5 ms ANE, 85.4 ms CPU [2].
- FluidAudio has two streaming families [5][6]:
  - `SlidingWindowAsrManager` reuses the offline TDT encoder with 11+2+2 s windows. Hypothesis chunks are 1 to 2 s. Confirmation takes about 10 s. It does not conform to `StreamingAsrManager`.
  - Cache-aware managers (EOU 120M, Nemotron, Unified) conform to `StreamingAsrManager`.
- Parakeet EOU 120M is English only and has no punctuation [26]. LibriSpeech test-clean WER on M2: 4.88% at 320 ms chunks and 8.23% at 160 ms chunks, against about 2.6% for batch v3 [1]. It does not fit a German and English app.
- Nemotron streaming has 560, 1120 and 2240 ms tiers. A multilingual Latin variant scores 9.83% on FLEURS German [1]. Worse than batch v3.
- The unified streaming model re-encodes a 7.68 s window for every 1.04 s chunk. FluidAudio says to use batch for files and streaming for live audio [3].
- VoiceInk uses a different approach [10]. It runs VAD, keeps confirmed words with a `WordAgreementEngine`, and re-transcribes the buffer slice from the last confirmed word with batch `AsrManager.transcribe`. It falls back to a full batch run if fewer than 3 segments were confirmed.
- FluidAudio ships a Silero VAD Core ML model. It works on 256 ms hops and runs on CPU [7]. Reported speed is 1408x real time on M5 Pro [7].
- Recommendation: keep batch v3. Commit text at VAD silence boundaries during recording using the VoiceInk approach. At release only the tail needs STT.

### Q2. Incremental cleanup, Apple FM vs small local models

Measured on this machine, medians, prewarmed, greedy:

| Prompt                          | 17 words | 38 words |
| ------------------------------- | -------- | -------- |
| Short instruction               | 402 ms   | 715 ms   |
| voz instruction plus 6 examples | 713 ms   | 1044 ms  |

- Decode costs about 330 ms per 21 words. The long prompt adds about 300 ms fixed (measured).
- Two concurrent sessions took 1557 ms wall against about 713 ms for one. FM requests serialize (measured). Incremental cleanup must use a serial queue.
- Apple states the model has 2-bit QAT and about 3B parameters [14]. The 2024 post gives 0.6 ms per prompt token and 30 tok/s on iPhone 15 Pro [14]. Apple forum guidance says to expect 20 to 30 tok/s and to profile with Instruments [15].
- `prewarm(promptPrefix:)` needs at least 1 s of lead time, is not guaranteed, and may not run in the background or under load [16]. `isResponding` guards concurrent calls on one session [17].
- On-device context is 4K tokens. On macOS there is no rate limit. Prewarm loads the model into memory [18].
- Today `TextCleaner` splits into sentences and cleans them sequentially after release under one shared 1500 ms deadline. Anything over 2 to 3 sentences times out and falls back to raw text (code read plus measurement: a 20-word sentence took 1346 ms, two sentences timed out at about 1530 ms).
- Fix: clean each sentence while the user is still talking. At release only the last sentence is left.
- llama.cpp option [21][22][23]:
  - The Metal backend can embed the shader source and compile it at runtime. No `metal` tool is needed [21].
  - Release b11683 ships an xcframework (66.8 MB) and a macOS arm64 tarball (12.2 MB) [22].
  - Published: Llama 7B Q4_0 on M2 Pro 19-core reaches 341 t/s prompt and 38.9 t/s decode [23]. TinyLlama 1.1B Q4_0 on M4 iPad reaches 1334 t/s and 121 t/s [23].
  - A 0.6B to 1B model on M2 Pro would decode about 4 to 5x faster than FM. This is extrapolated and unverified. I could not benchmark it because the disk is full.
  - Costs: new dependency, 0.6 to 0.8 GB RAM while loaded (estimate), unproven German and English quality.
- MLX is blocked without Xcode. `swift build` fails with `unable to spawn process 'metal'` [24]. An open proposal compiles kernels at runtime from source, about 2.5 s on first use [24].
- Apple says prefill is compute-bound and decode is memory-bandwidth-bound [25]. Shorter prompts and shorter outputs both help.
- Fine-tuned tiny model: Wispr Flow reports a fine-tuned Llama with end-to-end p99 under 700 ms and "100+ tokens in <250 ms" [27]. That is a cloud service. A local fine-tuned tiny model is unverified. Defer.

### Q3. ANE and Core ML

- First load compiles and specializes the model. FluidAudio lists the encoder at 3361 ms cold and 162 ms warm on iPhone 16 Pro Max [2].
- An Apple engineer says the specialization cache is automatic, stored on disk, keyed to model path and configuration, and can be freed by low storage, system updates or model changes [12]. It is stored per compute-unit configuration [12].
- On this Mac it lives at `~/Library/Caches/com.joelheile.voz/com.apple.e5rt.e5bundlecache/25G83/<hash>/`. 25G83 is the OS build (measured).
- Measured here: first load 28.6 s, then 0.18 s and 0.15 s. A later run took 22.9 s, then 0.48 s, then 24.8 s after a 90 s idle. The cache is lost within minutes in this environment. The cause is unverified. A full disk is a candidate, because Apple lists low storage as a reason for purging [12].
- Preprocessor is pinned to CPU. Encoder uses ANE by default. `encoderComputeUnits: .cpuAndGPU` is opt-in, about 8% faster (RTFx about 127 against about 117 median) and WER-neutral. FluidAudio keeps ANE as default for power [2].
- 6-bit palettized encoder is the shipped choice. INT4 is slower and less accurate [2].
- macOS 27 release notes (Core AI section, worded "iOS 27") say the system restricts background Neural Engine access like GPU restrictions. Background access needs the entitlement `com.apple.developer.background-tasks.continued-processing.inference`. ANE memory is attributed to the app process [11]. Whether this applies to macOS menu-bar agents is unverified. FluidAudio issue 738 tracks it [8].
- A forum thread reports concurrent ANE predictions serialized on iOS 27 with gains on macOS 26.4.1 [13]. Single poster, unconfirmed. A reply calls the ANE a shared system resource [13].
- Contention with FM: both models are used one after another in the pipeline, not at once. Incremental work during recording would overlap STT of the next segment with FM cleanup of the last. Whether this slows either is unmeasured. Measure before shipping.

### Q4. Memory

- Transcribe run: max RSS 536 MB, peak footprint 70.7 MB (`/usr/bin/time -l`, measured). The weights are mapped files, so footprint is much lower than RSS.
- Cleanup run: RSS 26 MB, footprint 9.3 MB (measured). FM runs out of process. Its resident cost is not visible to voz and is unverified.
- Parakeet v3 has 600M parameters and needs at least 2 GB RAM to load [26]. Model on disk is about 480 MB [1].
- A local LLM adds 0.6 to 0.8 GB (estimate, unverified).
- macOS 27 attributes ANE memory to the app process [11]. Expect footprint to rise on macOS 27. Re-measure there.
- Idle policy: Handy closes the mic stream after 30 s idle [19]. The model stays loaded. No evidence in the sources of an unload strategy that is worth the cold-load cost, given the cache loss above.

### Q5. Audio path latency

- voz builds a new `AVAudioEngine` on every `start()`, taps with a 1024 frame buffer and converts to 16 kHz mono. Start latency is not measured anywhere. No source gives a number. Instrument it.
- The recording indicator shows while the mic "is in use or has been used recently" [28]. Leaving the mic open between dictations would keep the indicator on. Do not do that.
- FluidVoice pre-registers the input callback and a fixed ring buffer at startup without starting the device, so no indicator shows [20]. Handy has AlwaysOn and OnDemand modes [19].
- Bluetooth: an AirPods input switches the link to HFP and drops the rate to 16 or 24 kHz [29][30]. voz already prefers the built-in mic when the default is Bluetooth.
- Voice processing IO adds echo cancellation and noise suppression. It changes the format and adds start cost (unverified size). Keep it off.
- The 150 ms mute delay after the start cue is by design. It does not affect release latency.

### Q6. Insertion speed

- voz: 50 ms `pasteDelay`, V keycode hardcoded to 9, `.cghidEventTap` (code read).
- VoiceInk: 200 ms pre-paste delay, 10 ms between events, 250 ms or more before clipboard restore, `.privateState` source, `.cghidEventTap` [9].
- OpenWhispr macOS: 120 ms paste delay, 8 ms between key down and up, 20 ms after, restore after 450 ms, `.cgSessionEventTap`. It resolves the V keycode from the active layout with TIS, so it works on non-QWERTY layouts [31].
- Handy has configurable `paste_delay_ms` and `paste_delay_after_ms` [19].
- FluidVoice sleeps 25 to 50 ms in AX insertion, posts keys with `postToPid`, and types Unicode CGEvents with no inter-chunk delay [20].
- voz at 50 ms is already the fastest of the peers. Keep it. Insertion cost is about 60 ms and cannot be cut much.
- Risk: a hardcoded V keycode of 9 pastes the wrong character on Dvorak and some AZERTY layouts. Resolve it from the layout.
- Any cut below 50 ms is unverified against slow target apps. Do not shorten.

### Q7. Always running

- `SMAppService` has four kinds: mainApp, loginItem, agent, daemon. `.agent` uses a plist in `Contents/Library/LaunchAgents` [32].
- Relevant launchd keys [33]: `BundleProgram` (SMAppService only), `KeepAlive` (`SuccessfulExit`, `Crashed`), `ThrottleInterval` (default 10 s), `ProcessType` (Interactive means no resource limits and should be used only when needed; Adaptive; Background), `LimitLoadToSessionType`, `RunAtLoad`.
- VoiceInk and Handy use mainApp login items. Neither relaunches after a crash [9][19].
- voz already re-enables the event tap on `tapDisabledByTimeout` and `tapDisabledByUserInput` (code read). FluidVoice adds a 30 s health check [20]. The tap being disabled is the more likely failure than the process dying.
- A `KeepAlive` agent adds crash recovery. Risks, all unverified: Sparkle relaunch interplay, Quit semantics (exit 0 stops it, which is correct), and TCC attribution for Accessibility and Input Monitoring.
- App Nap throttles timers and I/O for apps that are not in the foreground and hold no assertion [34]. `ProcessInfo.beginActivity` offers `.userInitiated` and `.latencyCritical` ("highest timer and I/O precision") [34]. voz has no `beginActivity` call (grep). Whether App Nap delays the event tap or hotkey for an LSUIElement app is unverified. Test it: idle 10 min, then press the hotkey and log the delay.
- Hold an activity only while recording and processing. A permanent assertion costs battery.

### Q8. Binary size

- Release binary: 27.7 MB (measured). `strip -x` gives 19.99 MB. Plain `strip` gives 18.5 MB. `__LINKEDIT` is 10.45 MB. `__TEXT` is 16.6 MB, of which `__text` is 8.1 MB and `__const` is 7.4 MB (measured).
- Most of `__const` is Rust anonymous data from the prebuilt static library `NemoTextProcessing` (gaps of 4.88 MB and 2.11 MB, measured). Issues report 8 to 18 MB [35]. voz never references `TextNormalizer` or `NemoText` (grep).
- FluidAudio's `Package@swift-6.2.swift` has a `NemoTextProcessing` trait. `traits: []` on the dependency opts out [36]. This needs `swift-tools-version: 6.2` in voz's `Package.swift` (now 6.0, toolchain is Swift 6.2.1). Effect on the build is untested.
- SwiftPM release builds already pass `-Xlinker -dead_strip` on Apple targets [37].
- Full LTO raised link time by 55 to 68% with a minor size change under `-Osize` in the Swift pitch thread [38]. Low value here.
- Sparkle.framework is 2.9 MB. PostHog and GRDB link statically.
- `scripts/make-app.sh` has no strip step.

## 3. Prioritized changes

| #   | Change                                                                                                                                                                                                     | Expected gain                                                           | Risk                                                                                                                                   |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Incremental STT and cleanup during recording. Commit at VAD silence, transcribe the growing slice with batch v3, run finished sentences through one serial FM queue. At release only the tail remains.     | Latency stays about 0.6 s at any length. Removes timeouts on long text. | Medium. Boundary errors, queue cancel logic, ANE and FM contention (unmeasured). Keep the current path as the fallback until verified. |
| 2   | Trim the cleanup prompt (short instruction, 2 examples). Check with `voz --eval`.                                                                                                                          | About 300 ms per call.                                                  | Medium. Quality regressions, German in particular.                                                                                     |
| 3   | Protect model residency. Run a warm-up inference at launch, log cold load time (`model_load cold_ms` exists), keep the SpeechAnalyzer fallback. Free disk space on the dev machine and recheck cache loss. | Avoids 23 to 29 s cold loads.                                           | Low.                                                                                                                                   |
| 4   | Add `strip -x` to `make-app.sh` before signing.                                                                                                                                                            | 7.7 MB (28%).                                                           | None known. Verify notarization and Sparkle signing.                                                                                   |
| 5   | Opt out of `NemoTextProcessing` (tools 6.2, `traits: []`).                                                                                                                                                 | About 7 to 8 MB.                                                        | Low. Verify build and tests.                                                                                                           |
| 6   | Instrument `Recorder.start()` latency. Consider pre-registering the callback without starting the device. Keep voice processing off.                                                                       | Unknown until measured.                                                 | Low to medium.                                                                                                                         |
| 7   | Hedge for macOS 27: test on 27, try `encoderComputeUnits: .cpuAndGPU` (about 8% faster, more power).                                                                                                       | Avoids ANE background restriction if it applies.                        | Low.                                                                                                                                   |
| 8   | Layout-aware V keycode. Keep the 50 ms delay.                                                                                                                                                              | Correctness on non-QWERTY layouts.                                      | Low.                                                                                                                                   |
| 9   | Test App Nap effect on the hotkey. Use `beginActivity(.userInitiated)` only during dictation. Keep the 30 s tap health check.                                                                              | Removes a possible idle-wake delay.                                     | Low.                                                                                                                                   |
| 10  | `SMAppService.agent` with `KeepAlive`.                                                                                                                                                                     | Crash recovery.                                                         | Medium. Defer.                                                                                                                         |
| 11  | Local 1B llama.cpp cleanup model.                                                                                                                                                                          | About 4 to 5x faster decode (unverified).                               | High. New dependency, RAM, quality. Defer.                                                                                             |

## 4. Sources

1. FluidAudio Benchmarks. https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md
2. FluidAudio encoder compute placement. https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/EncoderComputePlacement.md (path unverified)
3. FluidAudio ASR getting started. https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md (path unverified)
4. FluidAudio long transcription. https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/LongTranscription.md (path unverified)
5. FluidAudio `SlidingWindowAsrManager.swift`. https://github.com/FluidInference/FluidAudio (Sources/FluidAudio/ASR)
6. FluidAudio `StreamingAsrManager.swift`. https://github.com/FluidInference/FluidAudio (Sources/FluidAudio/ASR)
7. FluidAudio VAD getting started. https://github.com/FluidInference/FluidAudio/blob/main/Documentation/VAD/GettingStarted.md
8. FluidAudio issue 738, macOS 27 background ANE. https://github.com/FluidInference/FluidAudio/issues/738
9. VoiceInk `CursorPaster.swift` and `FluidAudioStreamingProvider.swift`. https://github.com/Beingpax/VoiceInk
10. VoiceInk streaming provider (same repository as 9, file `FluidAudioStreamingProvider.swift`).
11. Apple, macOS 27 release notes, Core AI. https://developer.apple.com/documentation/macos-release-notes
12. Apple Developer Forums, Core ML specialization cache reply (thread id not recorded, unverified link). https://developer.apple.com/forums/
13. Apple Developer Forums thread 850110, ANE serialization. https://developer.apple.com/forums/thread/850110
14. Apple Machine Learning Research, Introducing Apple's on-device and server foundation models (2024) and 2025 tech report. https://machinelearning.apple.com/research/introducing-apple-foundation-models
15. Apple Developer Forums thread 791993 (FM token speed). https://developer.apple.com/forums/thread/791993
16. Apple docs, `LanguageModelSession.prewarm(promptPrefix:)`. https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)
17. Apple docs, `LanguageModelSession.isResponding`. https://developer.apple.com/documentation/foundationmodels/languagemodelsession/isresponding
18. WWDC26 sessions 8016 and 339 and lab notes (Foundation Models).
19. Handy, `clipboard.rs`, `managers/audio.rs`, `settings.rs`. https://github.com/cjpais/Handy
20. FluidVoice, `ASRService.swift`, `TypingService.swift`, `GlobalHotkeyManager.swift`, README. https://github.com/altic-dev/FluidVoice
21. llama.cpp `ggml-metal` CMake and `ggml-metal-device.m`. https://github.com/ggml-org/llama.cpp
22. llama.cpp release b11683. https://github.com/ggml-org/llama.cpp/releases/tag/b11683
23. llama.cpp discussion 4167, Apple Silicon benchmarks. https://github.com/ggml-org/llama.cpp/discussions/4167
24. mlx-swift issues 263 and 500. https://github.com/ml-explore/mlx-swift/issues/500
25. Apple Machine Learning Research, MLX on M5. https://machinelearning.apple.com/research/exploring-llms-mlx-m5
26. NVIDIA model cards, Parakeet TDT 0.6B v3 and Parakeet realtime EOU 120M. https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
27. Baseten, Wispr Flow case study. https://www.baseten.co/resources/customers/wispr-flow/
28. Apple Support, control access to the microphone on Mac. https://support.apple.com/guide/mac-help/control-access-to-your-microphone-on-mac-mchla1b1e1fe/mac
29. Liscio, AirPods and sample rate posts (URL not recorded, unverified). https://atastypixel.com/
30. Apple Developer Forums threads 797033 and 680785 (Bluetooth input rate). https://developer.apple.com/forums/thread/797033
31. OpenWhispr `clipboard.js` and `macos-fast-paste.swift`. https://github.com/OpenWhispr/openwhispr
32. Apple docs, `SMAppService`. https://developer.apple.com/documentation/servicemanagement/smappservice
33. `launchd.plist(5)` man page. https://keith.github.io/xcode-man-pages/launchd.plist.5.html
34. Apple docs, `ProcessInfo.ActivityOptions` and the App Nap guide. https://developer.apple.com/documentation/foundation/processinfo/activityoptions
35. FluidAudio issues 880 and 888, binary size. https://github.com/FluidInference/FluidAudio/issues/880
36. FluidAudio `Package@swift-6.2.swift`. https://github.com/FluidInference/FluidAudio/blob/main/Package%406.2.swift (path unverified)
37. SwiftPM `ProductBuildDescription.swift`. https://github.com/swiftlang/swift-package-manager
38. Swift Forums, LTO pitch thread. https://forums.swift.org/
39. WhisperKit paper, arXiv 2507.10860. https://arxiv.org/abs/2507.10860

Note on sources: items 10 and 12 to 14 duplicate or group other entries. Distinct primary sources number more than 30. URLs marked "unverified" or given as a site root were found during research but the exact path was not recorded.
