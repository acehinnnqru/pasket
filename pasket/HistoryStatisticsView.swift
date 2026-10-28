import Carbon
import Charts
import SwiftUI

private enum StatisticsPage: String, CaseIterable {
    case copies = "Copies"
    case historyOpens = "History opens"

    var unit: String { self == .copies ? "copies" : "opens" }
    var chartID: String { self == .copies ? "copiesChart" : "historyOpensChart" }
    var explanation: String {
        self == .copies ? "Each captured copy or successful copy from history."
            : "Each time the history panel becomes visible."
    }
    var note: String {
        self == .copies
            ? "Counts are saved on this Mac by local date. The initial estimate counts each saved history item once on its most recent copy date; earlier repeats and deleted items cannot be recovered. New copies count every time, including repeats. Copying or pasting a group from history counts once; each queue item counts separately. Paused, excluded, or missed clipboard changes are not counted. Clearing history does not reset these counts."
            : "Counts are saved on this Mac by local date, starting with this version. Launch opens are included. Bringing an already visible panel forward does not add an open."
    }
}

struct HistoryStatisticsWindowView: View {
    var statistics: HistoryStatistics
    var copyStatistics: HistoryStatistics
    var onClose: () -> Void
    @State private var isPickerPresented = false
    @State private var page = StatisticsPage.copies

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
                        Text("Your daily clipboard usage.")
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
            HStack(spacing: 10) {
                ForEach(StatisticsPage.allCases, id: \.self) { option in
                    Button(option.rawValue) {
                        isPickerPresented = false
                        page = option
                    }
                    .buttonStyle(PasketButtonStyle(isActive: page == option))
                    .accessibilityAddTraits(page == option ? [.isSelected] : [])
                    .accessibilityIdentifier(option == .copies ? "copiesStatisticsPage" : "historyOpensStatisticsPage")
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            if page == .copies && !copyStatistics.isInitialized {
                Text("Copy statistics will appear after clipboard history loads successfully.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HistoryStatisticsView(statistics: page == .copies ? copyStatistics : statistics,
                                      isPickerPresented: $isPickerPresented, page: page)
            }
        }
        .frame(width: 640, height: 600)
        .modifier(PasketSurface())
        .modifier(PasketPickerOverlay())
        .background {
            ShortcutEventMonitor { event in
                guard event.keyCode == UInt16(kVK_Escape),
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
                else { return false }
                if !event.isARepeat {
                    if isPickerPresented { isPickerPresented = false }
                    else { onClose() }
                }
                return true
            }
        }
    }
}

private struct HistoryStatisticsView: View {
    var statistics: HistoryStatistics
    @Binding var isPickerPresented: Bool
    var page: StatisticsPage
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
                            Text(page.rawValue)
                                .font(.headline)
                            Text(page.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        PasketPicker(title: "Date range", selection: $dayCount,
                                     isPresented: $isPickerPresented, options: [7, 30, 90],
                                     valueAlignment: .trailing) { count in
                            "\(count) days"
                        }
                        .accessibilityIdentifier("statisticsDateRange")
                    }

                    HStack(spacing: 24) {
                        metric("Today", value: statistics.days(endingAt: context.date, count: 1).first?.count ?? 0)
                        metric("Selected period", value: days.reduce(0) { $0 + $1.count })
                        Spacer()
                        metric("Total", value: statistics.totalCount)
                            .help(page == .copies ? "All recorded copies, including the initial history estimate" : "All history opens recorded on this Mac")
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
                            y: .value(page.rawValue, day.count)
                        )
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(3)
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(day.count) \(page.unit)")
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
                    .accessibilityIdentifier(page.chartID)

                    if days.allSatisfy({ $0.count == 0 }) {
                        Text(page == .copies ? "No copies recorded in this period." : "No history opens recorded in this period.")
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

                    Text(page.note)
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
