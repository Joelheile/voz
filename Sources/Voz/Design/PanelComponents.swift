import SwiftUI

struct PageBar<Trailing: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 4) {
            IconButton(icon: .chevronLeft, help: "Back", action: back)
                .keyboardShortcut("[", modifiers: .command)
            Text(title)
                .font(.display(17))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, -6)
    }
}

extension PageBar where Trailing == EmptyView {
    init(title: String, back: @escaping () -> Void) {
        self.init(title: title, back: back) { EmptyView() }
    }
}

struct PageNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.meta)
            .lineSpacing(2)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
                    ForEach(rows) { row in
                        VStack(spacing: 0) {
                            if row.id != rows.first?.id { RowDivider() }
                            row.padding(.horizontal, 12)
                        }
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
                        .font(.meta)
                        .lineSpacing(2)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .frame(minHeight: Theme.Size.row)
        .padding(.vertical, 6)
    }
}

struct LinkRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        ActionRow(title: title, value: value, action: action) { hovering in
            Icon(.chevronRight, size: 13)
                .foregroundStyle(hovering ? Theme.ink : Theme.inkTertiary)
        }
    }
}

struct ActionRow<Trailing: View>: View {
    let title: String
    let value: String
    let action: () -> Void
    @ViewBuilder var trailing: (Bool) -> Trailing
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text(value).font(.meta).foregroundStyle(Theme.inkSecondary)
                trailing(hovering)
            }
            .frame(minHeight: Theme.Size.row)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

extension ActionRow where Trailing == EmptyView {
    init(title: String, value: String, action: @escaping () -> Void) {
        self.init(title: title, value: value, action: action) { _ in EmptyView() }
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

struct TabBar<Tab: Hashable & RawRepresentable<String>>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .font(.ui(12, weight: .medium))
                        .foregroundStyle(tab == selection ? Theme.ink : Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background {
                            if tab == selection {
                                RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous)
                                    .fill(Theme.raised)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.selected, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .animation(.spring(duration: 0.25, bounce: 0), value: selection)
    }
}
