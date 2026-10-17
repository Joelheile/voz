import SwiftUI
import VozCore

struct HistoryList: View {
    @ObservedObject var model: HistoryModel

    private var groups: [(day: Date, records: [TranscriptRecord])] {
        let calendar = Calendar.current
        return Dictionary(grouping: model.records) { calendar.startOfDay(for: $0.createdAt) }
            .map { (day: $0.key, records: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.block) {
            HStack {
                SectionTitle(text: "Transcripts")
                Spacer()
                SearchField(text: $model.query)
                    .frame(width: 200)
            }
            if model.records.isEmpty {
                EmptyNote(
                    symbol: "text.bubble",
                    title: model.query.isEmpty ? "No transcripts yet" : "No matches",
                    detail: model.query.isEmpty ? "Dictate something and it shows up here." : nil
                )
            } else {
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: DayLabel.text(for: group.day))
                        VStack(spacing: 0) {
                            ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { RowDivider() }
                                HistoryRow(record: record, copy: { model.copyText(of: record) }, delete: { model.delete(record) })
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hairline))
                    }
                }
            }
        }
    }
}

enum DayLabel {
    static func text(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.month(.wide).day().year())
    }
}

private struct HistoryRow: View {
    let record: TranscriptRecord
    let copy: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.meta)
                .monospacedDigit()
                .foregroundStyle(Theme.inkTertiary)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.finalText)
                    .font(.body14)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let appName = record.appName {
                    Text(appName).font(.system(size: 12)).foregroundStyle(Theme.inkTertiary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                IconButton(symbol: "doc.on.doc", help: "Copy", action: copy)
                IconButton(symbol: "trash", help: "Delete", action: delete)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(hovering ? Theme.hover : .clear)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}
