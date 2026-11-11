import LucideSwift
import SwiftUI

enum TourStep: Int, CaseIterable {
    case dictate
    case dictionary
    case extensions

    var title: String {
        switch self {
        case .dictate: "Talk, and Voz types"
        case .dictionary: "Spelled the way you spell it"
        case .extensions: "Make it yours"
        }
    }

    var detail: String {
        switch self {
        case .dictate: "Say it once. Voz cleans up your words and types them at your cursor."
        case .dictionary: "Add names and jargon to your Dictionary. Voz gets them right every time."
        case .extensions: "Extensions change what Voz does with your words. Install one, or write your own."
        }
    }

    var action: (title: String, page: PopoverPage)? {
        switch self {
        case .dictate: nil
        case .dictionary: ("Open Dictionary", .dictionary)
        case .extensions: ("Browse extensions", .extensions)
        }
    }
}

struct TourPage: View {
    @ObservedObject var model: PopoverModel
    @ObservedObject var settings: AppSettings
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: TourStep { model.tourStep }
    private var isLast: Bool { step == TourStep.allCases.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                StepProgress(count: TourStep.allCases.count, current: step.rawValue)
                Spacer(minLength: 0)
                Button("Skip", action: finish)
                    .buttonStyle(.quietText)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
                    .animation(Theme.Motion.section, value: isLast)
            }
            ZStack(alignment: .topLeading) {
                card
                    .id(step)
                    .transition(.page(forward: forward, reduceMotion: reduceMotion))
            }
            footer
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            demo
                .frame(maxWidth: .infinity)
                .frame(height: 148)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            StepHeader(title: step.title, detail: step.detail)
            ZStack(alignment: .leading) {
                if let action = step.action {
                    Button(action.title) { model.page = action.page }
                        .buttonStyle(.pill(.quiet, .small))
                }
            }
            .frame(height: PillSize.small.height)
        }
    }

    @ViewBuilder
    private var demo: some View {
        switch step {
        case .dictate: DictateDemo(hotkey: settings.hotkey.displayName)
        case .dictionary: DictionaryDemo()
        case .extensions: ExtensionsDemo()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if step != .dictate {
                Button("Back") { go(to: step.rawValue - 1) }
                    .buttonStyle(.quietText)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Button(isLast ? "Done" : "Next", action: advance)
                .buttonStyle(.pill(.ink, .regular))
                .contentTransition(.interpolate)
                .keyboardShortcut(.defaultAction)
        }
        .animation(Theme.Motion.section, value: step)
    }

    private func advance() {
        guard !isLast else { return finish() }
        go(to: step.rawValue + 1)
    }

    private func go(to index: Int) {
        guard let next = TourStep(rawValue: index) else { return }
        forward = next.rawValue > step.rawValue
        withAnimation(.spring(duration: 0.28, bounce: 0)) { model.tourStep = next }
    }

    private func finish() {
        withAnimation(Theme.Motion.section) { model.finishTour() }
    }
}

private struct DictateDemo: View {
    private static let phrase = "Let's meet at three tomorrow."
    let hotkey: String

    var body: some View {
        DemoLoop(duration: 6.5, rest: 5.5) { time in
            let pressed = Keyframes.ramp(time, from: 0.4, to: 0.5) - Keyframes.ramp(time, from: 3.0, to: 3.1)
            let listening = Keyframes.ramp(time, from: 0.6, to: 0.9) - Keyframes.ramp(time, from: 3.0, to: 3.3)
            let typed = Keyframes.typed(Self.phrase, progress: Keyframes.ramp(time, from: 3.4, to: 4.9))
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    key(pressed: pressed)
                    waveform(time: time, level: listening)
                }
                .offset(x: 33 * (1 - listening))
                field(typed: typed, typing: time > 3.3 && time < 5.1)
            }
            .padding(.horizontal, 20)
        }
    }

    private func key(pressed: Double) -> some View {
        Text(hotkey)
            .font(.ui(14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(minWidth: 56, minHeight: 40)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(pressed > 0.5 ? Theme.accent : Theme.hairline, lineWidth: pressed > 0.5 ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(0.08 * (1 - pressed)), radius: 0, y: 2 * (1 - pressed))
            .scaleEffect(1 - 0.04 * pressed)
    }

    private func waveform(time: Double, level: Double) -> some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 7, id: \.self) { index in
                let wave = 0.5 + 0.5 * sin(time * 8 + Double(index) * 1.1)
                Capsule()
                    .fill(Theme.recording)
                    .frame(width: 3, height: 4 + 16 * level * wave)
            }
        }
        .frame(width: 56, height: 40)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .scaleEffect(0.9 + 0.1 * level)
        .opacity(level)
    }

    private func field(typed: String, typing: Bool) -> some View {
        HStack(spacing: 1) {
            Text(typed.isEmpty ? "Any text field" : typed)
                .font(.ui(13))
                .foregroundStyle(typed.isEmpty ? Theme.inkTertiary : Theme.ink)
            if typing {
                Rectangle().fill(Theme.accent).frame(width: 1.5, height: 15)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .demoSurface()
    }
}

private struct DictionaryDemo: View {
    var body: some View {
        DemoLoop(duration: 7, rest: 5.5) { time in
            let chip = Keyframes.ramp(time, from: 1.2, to: 1.7)
            let fixed = Keyframes.ramp(time, from: 2.4, to: 2.9)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Icon(.bookText, size: 14)
                        .foregroundStyle(Theme.inkSecondary)
                    Text("Kubernetes")
                        .font(.ui(12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Theme.selected, in: Capsule())
                        .scaleEffect(0.9 + 0.1 * chip)
                        .opacity(chip)
                }
                ZStack(alignment: .leading) {
                    Text("Deploy it to cooper nettys")
                        .foregroundStyle(Theme.ink)
                        .opacity(1 - fixed)
                    Text("Deploy it to \(Text("Kubernetes").foregroundStyle(Theme.accent))")
                        .foregroundStyle(Theme.ink)
                        .opacity(fixed)
                }
                .font(.ui(13))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .demoSurface()
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct ExtensionsDemo: View {
    private static let rows: [(icon: LucideIconName, name: String, detail: String)] = [
        (.rocket, "voz-launcher", "Say \"computer, open Safari\""),
        (.mail, "voz-mail", "Formats dictation as an email"),
        (.send, "voz-send-it", "Say \"send it\" to press Return"),
    ]

    var body: some View {
        DemoLoop(duration: 7, rest: 5.5) { time in
            VStack(spacing: 6) {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    let arrival = Keyframes.ramp(time, from: 0.4 + 0.3 * Double(index), to: 0.8 + 0.3 * Double(index))
                    HStack(spacing: 10) {
                        Icon(row.icon, size: 15)
                            .foregroundStyle(Theme.inkSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name)
                                .font(.ui(12, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text(row.detail)
                                .font(.meta)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .demoSurface()
                    .offset(y: 8 * (1 - arrival))
                    .opacity(arrival)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private extension View {
    func demoSurface() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.hairline))
    }
}
