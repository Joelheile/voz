import SwiftUI
import VozCore

struct Sidebar: View {
    @ObservedObject var model: MainWindowModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Brand()
                .padding(.leading, 14)
                .padding(.top, 52)
                .padding(.bottom, 28)
            VStack(spacing: 4) {
                ForEach(MainSection.allCases) { section in
                    SidebarItem(section: section, isActive: model.section == section) {
                        model.section = section
                    }
                }
            }
            Spacer(minLength: 0)
            ShortcutHint(settings: settings)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: 232)
    }
}

private struct Brand: View {
    var body: some View {
        HStack(spacing: 10) {
            LevelBarsMark(height: 22, barWidth: 4.5, spacing: 3.5, color: Theme.ink, accentIndex: 2, accent: Theme.accent)
            Text("voz")
                .font(.display(28, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
        }
    }
}

private struct SidebarItem: View {
    let section: MainSection
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 20)
                Text(section.title)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                Spacer(minLength: 0)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                    .opacity(isActive ? 1 : 0)
            }
            .foregroundStyle(isActive || hovering ? Theme.ink : Theme.inkSecondary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
        .animation(Theme.Motion.hover, value: isActive)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var background: Color {
        if isActive { return Theme.selected }
        return hovering ? Theme.selected.opacity(0.5) : .clear
    }
}

private struct ShortcutHint: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(settings.hotkey.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(settings.holdToTalk ? "Hold to dictate" : "Press to dictate")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
    }
}
