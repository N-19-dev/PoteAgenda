import SwiftUI

struct AgendaMonthGrid: View {
    let selectedDay: Date
    let blocks: [AgendaBlock]
    let onSelectDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(["L", "M", "M", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(DateHelpers.monthDates(for: selectedDay), id: \.self) { day in
                Button {
                    onSelectDay(day)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Calendar.current.component(.day, from: day).formatted())
                            .font(.headline.weight(.bold))
                            .foregroundStyle(DateHelpers.sameMonth(day, selectedDay) ? .primary : .secondary)
                        Spacer()
                        let count = blockCount(on: day)
                        if count > 0 {
                            Text(count == 1 ? "1 créneau" : "\(count) créneaux")
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    .frame(height: 76, alignment: .topLeading)
                    .padding(7)
                    .background(monthCellBackground(for: day), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.poteSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    private func blockCount(on day: Date) -> Int {
        let bounds = DateHelpers.dayBounds(for: day)
        return blocks.filter { block in
            guard let start = DateHelpers.parse(block.startAt), let end = DateHelpers.parse(block.endAt) else { return false }
            return start < bounds.end && end > bounds.start
        }.count
    }

    private func monthCellBackground(for day: Date) -> Color {
        if Calendar.current.isDate(day, inSameDayAs: selectedDay) {
            return Color.accentColor.opacity(0.16)
        }
        return Color.poteGroupedBackground
    }
}
