import SwiftUI

struct AgendaWeekGrid: View {
    let selectedDay: Date
    let displayMode: AgendaDisplayMode
    let blocks: [AgendaBlock]
    let onSelectDay: (Date) -> Void
    let onSelectOwnEvent: (CalendarEvent) -> Void
    let onSelectBlock: (AgendaBlock) -> Void
    let onSelectOverlapGroup: ([AgendaBlock]) -> Void
    let onCreateDraft: (AgendaDraftEvent) -> Void
    @State private var expandedBlockId: String?

    private let hourRange = 7...23
    private let hourHeight: CGFloat = 64
    private let hourRailWidth: CGFloat = 44
    /// Hauteur minimale pour qu'un bloc "ami" reste lisible même pour un
    /// événement très court.
    private static let minReadableHeight: CGFloat = 30
    /// En dessous de cette hauteur, un seul mot tient : on bascule le bloc
    /// ami en rendu compact (padding réduit, une seule ligne) plutôt que de
    /// laisser le texte se faire couper.
    private static let compactTextThreshold: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            let dayWidth = resolvedDayWidth(availableWidth: proxy.size.width)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    weekHeader(dayWidth: dayWidth)
                    Divider()
                    if blocks.isEmpty {
                        emptyStateHint
                    }
                    gridBody(dayWidth: dayWidth)
                }
                .frame(width: proxy.size.width)
                .background(Color.poteSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func resolvedDayWidth(availableWidth: CGFloat) -> CGFloat {
        if displayMode == .day { return max(availableWidth - hourRailWidth, 1) }
        let fittingWidth = (availableWidth - hourRailWidth) / CGFloat(weekDates.count)
        return max(fittingWidth, 1)
    }

    private var weekDates: [Date] {
        displayMode == .day ? [selectedDay] : DateHelpers.weekDates(for: selectedDay)
    }

    private func weekHeader(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: hourRailWidth)

            ForEach(weekDates, id: \.self) { day in
                Button {
                    onSelectDay(day)
                } label: {
                    VStack(spacing: 5) {
                        Text(DateHelpers.weekdayString(day).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(Calendar.current.component(.day, from: day).formatted())
                            .font(.headline.weight(.black))
                            .frame(width: 34, height: 34)
                            .background(dayBadgeBackground(for: day))
                            .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDay) ? .white : .primary)
                        if friendBusyPresent(on: day) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.55))
                                .frame(width: 24, height: 4)
                        } else if friendPendingPresent(on: day) {
                            Capsule()
                                .fill(Color(hex: "#f97316").opacity(0.7))
                                .frame(width: 24, height: 4)
                        } else {
                            Color.clear.frame(width: 24, height: 4)
                        }
                    }
                    .frame(width: dayWidth, height: 70)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyStateHint: some View {
        Label("Appuie sur + ou maintiens un créneau pour ajouter une indisponibilité.", systemImage: "hand.tap")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Un tap crée directement un brouillon sur une case libre (plus
    /// découvrable qu'un long press seul) ; les blocs, dessinés au-dessus
    /// avec leur propre zone de tap, interceptent le tap là où le créneau
    /// est occupé, donc ce raccourci ne s'applique de fait qu'aux cases
    /// libres. Le long press reste disponible en complément.
    private func hourCell(day: Date, hour: Int, dayWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: dayWidth, height: hourHeight)
            .border(Color.poteSeparator.opacity(0.35), width: 0.5)
            .contentShape(Rectangle())
            .onTapGesture { onCreateDraft(draftEvent(on: day, hour: hour)) }
            .simultaneousGesture(longPressGesture(day: day, hour: hour))
    }

    private func longPressGesture(day: Date, hour: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in onCreateDraft(draftEvent(on: day, hour: hour)) }
    }

    private func gridBody(dayWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(hourRange), id: \.self) { hour in
                        Text(String(format: "%02d:00", hour))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: hourRailWidth, height: hourHeight, alignment: .topTrailing)
                            .padding(.trailing, 6)
                    }
                }

                ForEach(Array(weekDates.enumerated()), id: \.element) { _, day in
                    VStack(spacing: 0) {
                        ForEach(Array(hourRange), id: \.self) { hour in
                            hourCell(day: day, hour: hour, dayWidth: dayWidth)
                        }
                    }
                }
            }

            let positionedBlocks = positionedBlocks(dayWidth: dayWidth)
            let friendPositioned = positionedFriendBusyBlocks(positionedBlocks)
            let eventPositioned = positionedEventBlocks(positionedBlocks)

            // Vue jour : la colonne est assez large pour poser les blocs qui
            // se chevauchent côte à côte (comme un agenda classique). Vue
            // semaine/mois : la colonne de jour est déjà étroite, des
            // sous-colonnes y seraient illisibles — on affiche un seul bloc
            // (le plus pertinent) avec un badge de compte, et le tap liste
            // les autres.
            if displayMode == .day {
                ForEach(columnLayout(friendPositioned)) { columned in
                    friendOverlayBlockView(columned, dayWidth: dayWidth)
                }
                ForEach(columnLayout(eventPositioned)) { columned in
                    eventBlockView(columned, dayWidth: dayWidth)
                }
            } else {
                ForEach(overlapGroups(friendPositioned)) { group in
                    friendOverlayBadgeView(group, dayWidth: dayWidth)
                }
                ForEach(overlapGroups(eventPositioned)) { group in
                    eventBadgeView(group, dayWidth: dayWidth)
                }
            }

            if let todayIndex = weekDates.firstIndex(where: { Calendar.current.isDateInToday($0) }) {
                CurrentTimeLine(startHour: hourRange.lowerBound, hourHeight: hourHeight)
                    .frame(width: dayWidth)
                    .offset(x: hourRailWidth + CGFloat(todayIndex) * dayWidth, y: 0)
            }
        }
        .frame(height: CGFloat(hourRange.count) * hourHeight)
    }

    private func toggleExpanded(_ id: String) {
        withAnimation(.snappy(duration: 0.18)) {
            expandedBlockId = expandedBlockId == id ? nil : id
        }
    }

    private func draftEvent(on day: Date, hour: Int) -> AgendaDraftEvent {
        let startsAt = DateHelpers.hourDate(on: day, hour: hour)
        let endsAt = Calendar.current.date(byAdding: .hour, value: 1, to: startsAt) ?? startsAt
        return AgendaDraftEvent(startsAt: startsAt, endsAt: endsAt)
    }

    private func positionedBlocks(dayWidth: CGFloat) -> [PositionedAgendaBlock] {
        blocks.flatMap { block in
            weekDates.enumerated().compactMap { dayIndex, day in
                positionedBlock(block, on: day, dayIndex: dayIndex)
            }
        }
    }

    private func isFriendOverlayStyle(_ style: AgendaBlockStyle) -> Bool {
        style == .friendBusy || style == .friendPending
    }

    private func positionedFriendBusyBlocks(_ positionedBlocks: [PositionedAgendaBlock]) -> [PositionedAgendaBlock] {
        positionedBlocks.filter { isFriendOverlayStyle($0.block.style) }
    }

    private func positionedEventBlocks(_ positionedBlocks: [PositionedAgendaBlock]) -> [PositionedAgendaBlock] {
        positionedBlocks.filter { !isFriendOverlayStyle($0.block.style) }
    }

    /// Regroupe, jour par jour, les blocs dont l'intervalle vertical (top →
    /// top+height) se chevauche transitivement — deux blocs qui se touchent
    /// bout à bout ne forment pas un chevauchement, seul un vrai recouvrement
    /// compte.
    private func overlapClusters(_ positionedBlocks: [PositionedAgendaBlock]) -> [[PositionedAgendaBlock]] {
        let byDay = Dictionary(grouping: positionedBlocks, by: \.dayIndex)
        var clusters: [[PositionedAgendaBlock]] = []
        for (_, dayBlocks) in byDay {
            let sorted = dayBlocks.sorted {
                $0.top == $1.top ? $0.height > $1.height : $0.top < $1.top
            }
            var current: [PositionedAgendaBlock] = []
            var currentEnd: CGFloat = -.infinity
            for block in sorted {
                let end = block.top + block.height
                if current.isEmpty || block.top < currentEnd {
                    current.append(block)
                    currentEnd = max(currentEnd, end)
                } else {
                    clusters.append(current)
                    current = [block]
                    currentEnd = end
                }
            }
            if !current.isEmpty { clusters.append(current) }
        }
        return clusters
    }

    /// Assigne à chaque bloc chevauchant une colonne (algorithme glouton
    /// classique de layout d'agenda) : tous les blocs d'un même cluster se
    /// partagent la largeur du jour à parts égales.
    private func columnLayout(_ positionedBlocks: [PositionedAgendaBlock]) -> [ColumnedAgendaBlock] {
        overlapClusters(positionedBlocks).flatMap { cluster -> [ColumnedAgendaBlock] in
            var columnEnds: [CGFloat] = []
            var columnOf: [String: Int] = [:]
            for block in cluster.sorted(by: { $0.top < $1.top }) {
                if let idx = columnEnds.firstIndex(where: { $0 <= block.top }) {
                    columnEnds[idx] = block.top + block.height
                    columnOf[block.id] = idx
                } else {
                    columnEnds.append(block.top + block.height)
                    columnOf[block.id] = columnEnds.count - 1
                }
            }
            let columnCount = columnEnds.count
            return cluster.map { ColumnedAgendaBlock(positioned: $0, columnIndex: columnOf[$0.id] ?? 0, columnCount: columnCount) }
        }
    }

    /// Vue semaine/mois : un cluster de blocs chevauchants devient un seul
    /// groupe affichant le bloc le plus pertinent (mes événements avant les
    /// sorties, avant les indispos d'amis) et le compte total.
    private func overlapGroups(_ positionedBlocks: [PositionedAgendaBlock]) -> [AgendaOverlapBadgeGroup] {
        overlapClusters(positionedBlocks).compactMap { cluster in
            guard let primary = cluster.min(by: { overlapPriority($0.block.style) < overlapPriority($1.block.style) || (overlapPriority($0.block.style) == overlapPriority($1.block.style) && $0.top < $1.top) }) else {
                return nil
            }
            return AgendaOverlapBadgeGroup(primary: primary, blocks: cluster.map(\.block))
        }
    }

    private func overlapPriority(_ style: AgendaBlockStyle) -> Int {
        switch style {
        case .ownBusy: return 0
        case .outing: return 1
        case .friendBusy: return 2
        case .friendPending: return 3
        }
    }

    @ViewBuilder
    private func friendOverlayBlockView(_ columned: ColumnedAgendaBlock, dayWidth: CGFloat) -> some View {
        let positioned = columned.positioned
        // Un événement court (ex. 10-15 min) est remonté à une hauteur
        // minimale lisible (voir minReadableHeight) ; sans recentrer
        // verticalement, le bloc ne s'agrandissait que vers le bas et venait
        // chevaucher/masquer le texte du créneau suivant. On centre donc
        // l'agrandissement sur l'horaire réel.
        let flooredHeight = max(positioned.height, Self.minReadableHeight)
        let verticalGrowth = flooredHeight - positioned.height
        let availableWidth = max(dayWidth - 10, 36)
        let columnWidth = availableWidth / CGFloat(columned.columnCount)
        Button {
            onSelectBlock(positioned.block)
        } label: {
            FriendBusyOverlayBlock(block: positioned.block, compact: flooredHeight < Self.compactTextThreshold || columned.columnCount > 1)
        }
        .buttonStyle(.plain)
        .frame(width: max(columnWidth - 3, 26), height: flooredHeight)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .offset(
            x: hourRailWidth + CGFloat(positioned.dayIndex) * dayWidth + 5 + CGFloat(columned.columnIndex) * columnWidth,
            y: positioned.top - verticalGrowth / 2
        )
        .zIndex(4)
    }

    @ViewBuilder
    private func eventBlockView(_ columned: ColumnedAgendaBlock, dayWidth: CGFloat) -> some View {
        let positioned = columned.positioned
        let isExpanded = expandedBlockId == positioned.id
        let availableWidth = max(dayWidth - 8, 34)
        let columnWidth = availableWidth / CGFloat(columned.columnCount)
        AgendaEventBlockView(
            block: positioned.block,
            hideLabels: false,
            expanded: isExpanded
        ) {
            onSelectBlock(positioned.block)
        }
        .frame(width: max(columnWidth - 3, 24), height: max(positioned.height, isExpanded ? 68 : 30))
        .offset(
            x: hourRailWidth + CGFloat(positioned.dayIndex) * dayWidth + 4 + CGFloat(columned.columnIndex) * columnWidth,
            y: positioned.top
        )
        .zIndex(positioned.block.style.zIndex)
    }

    @ViewBuilder
    private func friendOverlayBadgeView(_ group: AgendaOverlapBadgeGroup, dayWidth: CGFloat) -> some View {
        let positioned = group.primary
        let flooredHeight = max(positioned.height, Self.minReadableHeight)
        let verticalGrowth = flooredHeight - positioned.height
        Button {
            if group.blocks.count > 1 {
                onSelectOverlapGroup(group.blocks)
            } else {
                onSelectBlock(positioned.block)
            }
        } label: {
            FriendBusyOverlayBlock(block: positioned.block, compact: flooredHeight < Self.compactTextThreshold)
                .overlay(alignment: .topTrailing) {
                    if group.blocks.count > 1 {
                        OverlapCountBadge(count: group.blocks.count)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: max(dayWidth - 10, 36), height: flooredHeight)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .offset(
            x: hourRailWidth + CGFloat(positioned.dayIndex) * dayWidth + 5,
            y: positioned.top - verticalGrowth / 2
        )
        .zIndex(4)
    }

    @ViewBuilder
    private func eventBadgeView(_ group: AgendaOverlapBadgeGroup, dayWidth: CGFloat) -> some View {
        let positioned = group.primary
        let isExpanded = expandedBlockId == positioned.id
        AgendaEventBlockView(
            block: positioned.block,
            hideLabels: false,
            expanded: isExpanded
        ) {
            if group.blocks.count > 1 {
                onSelectOverlapGroup(group.blocks)
            } else {
                onSelectBlock(positioned.block)
            }
        }
        .overlay(alignment: .topTrailing) {
            if group.blocks.count > 1 {
                OverlapCountBadge(count: group.blocks.count)
            }
        }
        .frame(width: max(dayWidth - 8, 34), height: max(positioned.height, isExpanded ? 68 : 30))
        .offset(
            x: hourRailWidth + CGFloat(positioned.dayIndex) * dayWidth + 4,
            y: positioned.top
        )
        .zIndex(positioned.block.style.zIndex)
    }

    /// true si au moins un ami est réellement occupé ce jour-là (par
    /// opposition à seulement "en attente" d'une invitation).
    private func friendBusyPresent(on day: Date) -> Bool {
        let bounds = DateHelpers.dayBounds(for: day)
        return blocks.contains { block in
            guard block.style == .friendBusy else { return false }
            guard let start = DateHelpers.parse(block.startAt), let end = DateHelpers.parse(block.endAt) else { return false }
            return start < bounds.end && end > bounds.start
        }
    }

    private func friendPendingPresent(on day: Date) -> Bool {
        let bounds = DateHelpers.dayBounds(for: day)
        return blocks.contains { block in
            guard block.style == .friendPending else { return false }
            guard let start = DateHelpers.parse(block.startAt), let end = DateHelpers.parse(block.endAt) else { return false }
            return start < bounds.end && end > bounds.start
        }
    }

    private func positionedBlock(_ block: AgendaBlock, on day: Date, dayIndex: Int) -> PositionedAgendaBlock? {
        guard let start = DateHelpers.parse(block.startAt), let end = DateHelpers.parse(block.endAt) else { return nil }
        let dayBounds = DateHelpers.dayBounds(for: day)
        let visibleStart = max(start, DateHelpers.hourDate(on: day, hour: hourRange.lowerBound))
        let visibleEnd = min(end, DateHelpers.hourDate(on: day, hour: hourRange.upperBound + 1))
        guard visibleStart < visibleEnd, visibleStart < dayBounds.end, visibleEnd > dayBounds.start else { return nil }

        let startMinutes = Calendar.current.dateComponents([.minute], from: DateHelpers.hourDate(on: day, hour: hourRange.lowerBound), to: visibleStart).minute ?? 0
        let durationMinutes = Calendar.current.dateComponents([.minute], from: visibleStart, to: visibleEnd).minute ?? 0
        return PositionedAgendaBlock(
            block: block,
            dayIndex: dayIndex,
            top: CGFloat(startMinutes) / 60 * hourHeight,
            height: CGFloat(durationMinutes) / 60 * hourHeight
        )
    }

    @ViewBuilder
    private func dayBadgeBackground(for day: Date) -> some View {
        if Calendar.current.isDate(day, inSameDayAs: selectedDay) {
            Circle().fill(Color.accentColor)
        } else if Calendar.current.isDateInToday(day) {
            Circle().stroke(Color.accentColor, lineWidth: 2)
        } else {
            Circle().fill(Color.clear)
        }
    }
}

private struct CurrentTimeLine: View {
    let startHour: Int
    let hourHeight: CGFloat

    var body: some View {
        let minutes = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        let top = CGFloat(minutes - startHour * 60) / 60 * hourHeight

        if top >= 0 {
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
            .offset(y: top)
        }
    }
}

private struct PositionedAgendaBlock: Identifiable {
    let block: AgendaBlock
    let dayIndex: Int
    let top: CGFloat
    let height: CGFloat

    var id: String { "\(block.id)-\(dayIndex)" }
}

/// Un bloc positionné auquel une colonne a été assignée au sein de son
/// cluster de chevauchement (vue jour).
private struct ColumnedAgendaBlock: Identifiable {
    let positioned: PositionedAgendaBlock
    let columnIndex: Int
    let columnCount: Int

    var id: String { positioned.id }
}

/// Un cluster de blocs qui se chevauchent (vue semaine/mois) : seul `primary`
/// est dessiné, `blocks` sert à lister le reste au tap sur le badge.
private struct AgendaOverlapBadgeGroup: Identifiable {
    let primary: PositionedAgendaBlock
    let blocks: [AgendaBlock]

    var id: String { primary.id }
}
