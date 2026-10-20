import SwiftUI

struct PageBar: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            IconButton(symbol: "chevron.left", help: "Back", action: back)
                .keyboardShortcut("[", modifiers: .command)
            Text(title)
                .font(.display(20))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.leading, -6)
    }
}

struct PanelGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(text: title).padding(.leading, 2) }
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 { RowDivider() }
                        rows[index].padding(.horizontal, 12)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
            }
        }
    }
}

struct PanelRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .frame(minHeight: 40)
        .padding(.vertical, 4)
    }
}

struct LinkRow: View {
    let title: String
    let value: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(value).font(.meta).foregroundStyle(Theme.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Theme.ink : Theme.inkTertiary)
            }
            .frame(minHeight: 40)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

struct CappedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maxHeight))
    }
}
