import Carbon
import Charts
import SwiftUI

struct HistoryStatisticsWindowView: View {
    var statistics: HistoryStatistics
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Statistics")
                            .font(.system(size: 16, weight: .medium))
                        Text("Your daily history usage.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 18)
                .padding(.vertical, 12)
                .overlay { PasketWindowDragRegion() }
                .help("Drag the header to move Statistics")
                .accessibilityIdentifier("statisticsWindowDragArea")
                PasketCloseButton(title: "Close statistics", help: "Close Statistics (Esc)", action: onClose)
                .keyboardShortcut("w", modifiers: .command)
            }
            .padding(.trailing, 14)
            Divider().opacity(0.5)
            HistoryStatisticsView(statistics: statistics)
        }
        .frame(width: 640, height: 600)
        .modifier(PasketSurface())
        .background {
            ShortcutEventMonitor { event in
                guard event.keyCode == UInt16(kVK_Escape),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return false }
                if !event.isARepeat { onClose() }
                return true
            }
        }
    }
}

struct HistoryStatisticsView: View {
    var statistics: HistoryStatistics
    @State private var dayCount = 7
    @State private var endDate: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let end = min(endDate ?? context.date, context.date)
            let days = statistics.days(endingAt: end, count: dayCount)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("History opens")
                                .font(.headline)
                            Text("Each time the history panel becomes visible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Date range", selection: $dayCount) {
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    HStack(spacing: 24) {
                        metric("Today", value: statistics.days(endingAt: context.date, count: 1).first?.count ?? 0)
                        metric("Selected period", value: days.reduce(0) { $0 + $1.count })
                        Spacer()
                        metric("Total", value: statistics.totalCount)
                            .help("All history opens recorded on this Mac")
                    }

                    HStack {
                        Button { movePeriod(from: end, by: -dayCount, now: context.date) } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 14, height: 16)
                        }
                        .accessibilityLabel("Previous period")
                        if let first = days.first, let last = days.last {
                            Text("\(first.date.formatted(date: .abbreviated, time: .omitted)) – \(last.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                        }
                        Button { movePeriod(from: end, by: dayCount, now: context.date) } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 14, height: 16)
                        }
                        .accessibilityLabel("Next period")
                        .disabled(endDate == nil)
                        Spacer()
                        Button("Today") { endDate = nil }
                            .disabled(endDate == nil)
                    }
                    .buttonStyle(PasketButtonStyle())

                    Chart(days) { day in
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Opens", day.count)
                        )
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(3)
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(day.count) opens")
                    }
                    .chartYScale(domain: 0...max(1, days.map(\.count).max() ?? 0))
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            if let count = value.as(Int.self) {
                                AxisGridLine()
                                AxisValueLabel { Text(count.formatted()) }
                            }
                        }
                    }
                    .frame(height: 150)
                    .accessibilityIdentifier("historyOpensChart")

                    if days.allSatisfy({ $0.count == 0 }) {
                        Text("No history opens recorded in this period.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(days.reversed()) { day in
                            HStack {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text(day.count.formatted()).monospacedDigit()
                            }
                            .font(.system(size: 12))
                            .padding(.vertical, 8)
                            Divider().opacity(0.4)
                        }
                    }

                    Text("Counts are saved on this Mac by local date, starting with this version. Launch opens are included. Bringing an already visible panel forward does not add an open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
        }
    }

    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted())
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func movePeriod(from date: Date, by offset: Int, now: Date) {
        guard let next = Calendar.current.date(byAdding: .day, value: offset, to: date) else { return }
        endDate = next >= Calendar.current.startOfDay(for: now) ? nil : next
    }
}
