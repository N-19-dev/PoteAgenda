import CoreLocation
import SwiftUI

struct AgendaView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var draftEvent: AgendaDraftEvent?
    @State private var selectedDisplayMode: AgendaDisplayMode = .week
    @State private var didSelectInitialFriends = false
    @State private var eventToDelete: CalendarEvent?
    @State private var selectedBlock: AgendaBlock?
    @State private var calendarPageOffset = 0

    private let calendarPageRadius = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                AgendaToolbar(
                    selectedDay: $dataStore.selectedDay,
                    selectedDisplayMode: $selectedDisplayMode,
                    acceptedFriends: dataStore.acceptedFriends,
                    selectedFriendIds: agendaSelectedFriendIdsBinding,
                    groups: dataStore.groups,
                    selectedGroup: dataStore.selectedGroup,
                    showingGroupBusyEvents: agendaShowingGroupBusyEventsBinding,
                    onSelectGroup: { group in
                        Task {
                            await dataStore.selectGroup(group)
                            dataStore.agendaShowingGroupBusyEvents = true
                        }
                    }
                )

                TabView(selection: $calendarPageOffset) {
                    ForEach((-calendarPageRadius)...calendarPageRadius, id: \.self) { offset in
                        let pageDay = shiftedDay(from: dataStore.selectedDay, by: offset)

                        Group {
                            if selectedDisplayMode == .month {
                                ScrollView(.vertical, showsIndicators: false) {
                                    AgendaMonthGrid(
                                        selectedDay: pageDay,
                                        blocks: visibleBlocks,
                                        onSelectDay: { day in
                                            dataStore.selectedDay = day
                                            selectedDisplayMode = .day
                                        }
                                    )
                                    .padding(.bottom, 12)
                                }
                            } else {
                                AgendaWeekGrid(
                                    selectedDay: pageDay,
                                    displayMode: selectedDisplayMode,
                                    blocks: visibleBlocks,
                                    onSelectDay: { day in
                                        dataStore.selectedDay = day
                                    },
                                    onSelectOwnEvent: { event in
                                        eventToDelete = event
                                    },
                                    onSelectBlock: { block in
                                        selectedBlock = block
                                    },
                                    onCreateDraft: { draft in
                                        draftEvent = draft
                                    }
                                )
                            }
                        }
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .background(Color.poteGroupedBackground)
            .navigationTitle("Agenda")
            .toolbar {
                ToolbarItem(placement: .poteTopBarTrailing) {
                    Button {
                        draftEvent = AgendaDraftEvent(day: dataStore.selectedDay)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await refreshVisibleAgenda()
                syncSelectedFriendsWithAcceptedFriends()
            }
            .onChange(of: dataStore.selectedDay) {
                Task { await refreshVisibleAgenda() }
            }
            .onChange(of: dataStore.friends) {
                syncSelectedFriendsWithAcceptedFriends()
            }
            .onChange(of: dataStore.agendaSelectedFriendIds) {
                Task { await refreshVisibleAgenda() }
            }
            .onChange(of: selectedDisplayMode) {
                calendarPageOffset = 0
                if selectedDisplayMode == .week {
                    syncSelectedFriendsWithAcceptedFriends()
                }
                Task { await refreshVisibleAgenda() }
            }
            .onChange(of: calendarPageOffset) {
                guard calendarPageOffset != 0 else { return }
                let offset = calendarPageOffset
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dataStore.selectedDay = shiftedDay(from: dataStore.selectedDay, by: offset)
                    calendarPageOffset = 0
                }
            }
            .refreshable { await refreshVisibleAgenda() }
            .sheet(item: $draftEvent) { draft in
                AddEventView(draft: draft)
            }
            .sheet(item: $selectedBlock) { block in
                AgendaBlockDetailSheet(block: block) {
                    selectedBlock = nil
                }
            }
            .confirmationDialog(
                "Indisponibilité",
                isPresented: Binding(
                    get: { eventToDelete != nil },
                    set: { if !$0 { eventToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let event = eventToDelete {
                    Button("Supprimer", role: .destructive) {
                        Task { await dataStore.deleteEvent(event) }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text(eventToDelete?.title ?? "")
            }
        }
    }

    private var visibleBlocks: [AgendaBlock] {
        var blocks = dataStore.calendarEvents.compactMap { AgendaBlock(event: $0) }
        blocks += dataStore.outings.map { row in
            AgendaBlock(
                id: "received-outing-\(row.outing.id)",
                title: row.outing.title,
                subtitle: row.response.agendaLabel,
                startAt: row.outing.startsAt,
                endAt: row.outing.endsAt,
                color: row.response.agendaColor,
                ownEvent: nil,
                details: .receivedOuting(row)
            )
        }
        blocks += dataStore.sentOutings.map { row in
            AgendaBlock(
                id: "sent-outing-\(row.outing.id)",
                title: row.outing.title,
                subtitle: row.outing.confirmedAt == nil ? "En attente" : "Confirmé",
                startAt: row.outing.startsAt,
                endAt: row.outing.endsAt,
                color: row.outing.confirmedAt == nil ? "#f97316" : "#22c55e",
                ownEvent: nil,
                details: .sentOuting(row)
            )
        }

        blocks += dataStore.friendsBusyEvents
            .filter { effectiveSelectedFriendIds.contains($0.userId) }
            .map { busyEvent in
                AgendaBlock(
                    id: "friend-\(busyEvent.userId)-\(busyEvent.startAt)",
                    title: friendName(for: busyEvent.userId),
                    subtitle: "Occupé",
                    startAt: busyEvent.startAt,
                    endAt: busyEvent.endAt,
                    color: "#8e8e93",
                    ownEvent: nil,
                    style: .friendBusy,
                    details: .friendBusy(busyEvent, friendName(for: busyEvent.userId), "Ami sélectionné")
                )
            }

        if dataStore.agendaShowingGroupBusyEvents {
            blocks += dataStore.busyEvents.map { busyEvent in
                AgendaBlock(
                    id: "group-\(busyEvent.userId)-\(busyEvent.startAt)",
                    title: friendName(for: busyEvent.userId),
                    subtitle: dataStore.selectedGroup?.name ?? "Groupe",
                    startAt: busyEvent.startAt,
                    endAt: busyEvent.endAt,
                    color: "#64748b",
                    ownEvent: nil,
                    style: .friendBusy,
                    details: .friendBusy(busyEvent, friendName(for: busyEvent.userId), dataStore.selectedGroup?.name ?? "Groupe")
                )
            }
        }

        return blocks
    }

    private func friendName(for userId: String) -> String {
        dataStore.acceptedFriends.first { dataStore.friendUserId(for: $0) == userId }?.profile?.username ?? "Ami"
    }

    private func refreshVisibleAgenda() async {
        let bounds = visibleBounds
        await dataStore.refreshAgenda(start: bounds.start, end: bounds.end)
    }

    private var visibleBounds: (start: Date, end: Date) {
        let firstPageDay = shiftedDay(from: dataStore.selectedDay, by: -calendarPageRadius)
        let lastPageDay = shiftedDay(from: dataStore.selectedDay, by: calendarPageRadius)
        let firstBounds = periodBounds(for: firstPageDay)
        let lastBounds = periodBounds(for: lastPageDay)
        return (firstBounds.start, lastBounds.end)
    }

    private func periodBounds(for date: Date) -> (start: Date, end: Date) {
        switch selectedDisplayMode {
        case .day:
            return DateHelpers.dayBounds(for: date)
        case .week:
            return DateHelpers.weekBounds(for: date)
        case .month:
            return DateHelpers.monthBounds(for: date)
        }
    }

    private func shiftedDay(from date: Date, by pageOffset: Int) -> Date {
        switch selectedDisplayMode {
        case .day:
            return Calendar.current.date(byAdding: .day, value: pageOffset, to: date) ?? date
        case .week:
            return Calendar.current.date(byAdding: .day, value: pageOffset * 7, to: date) ?? date
        case .month:
            return Calendar.current.date(byAdding: .month, value: pageOffset, to: date) ?? date
        }
    }

    private var effectiveSelectedFriendIds: Set<String> {
        let acceptedIds = Set(dataStore.acceptedFriends.map { dataStore.friendUserId(for: $0) })
        return dataStore.agendaSelectedFriendIds.intersection(acceptedIds)
    }

    private var agendaSelectedFriendIdsBinding: Binding<Set<String>> {
        Binding(
            get: { dataStore.agendaSelectedFriendIds },
            set: { dataStore.agendaSelectedFriendIds = $0 }
        )
    }

    private var agendaShowingGroupBusyEventsBinding: Binding<Bool> {
        Binding(
            get: { dataStore.agendaShowingGroupBusyEvents },
            set: { dataStore.agendaShowingGroupBusyEvents = $0 }
        )
    }

    private func syncSelectedFriendsWithAcceptedFriends() {
        let acceptedIds = Set(dataStore.acceptedFriends.map { dataStore.friendUserId(for: $0) })
        guard !acceptedIds.isEmpty else {
            dataStore.agendaSelectedFriendIds.removeAll()
            didSelectInitialFriends = false
            return
        }

        if didSelectInitialFriends {
            dataStore.agendaSelectedFriendIds.formIntersection(acceptedIds)
        } else if dataStore.agendaSelectedFriendIds.isEmpty {
            dataStore.agendaSelectedFriendIds = acceptedIds
            didSelectInitialFriends = true
        } else {
            dataStore.agendaSelectedFriendIds.formIntersection(acceptedIds)
            didSelectInitialFriends = true
        }
    }
}

private enum AgendaDisplayMode: String, CaseIterable, Identifiable {
    case day = "Jour"
    case week = "Semaine"
    case month = "Mois"

    var id: String { rawValue }
}

struct AgendaDraftEvent: Identifiable {
    let id = UUID()
    let startsAt: Date
    let endsAt: Date
    /// Bornes du créneau où tout le monde est disponible, quand ce brouillon
    /// vient d'un tap sur une disponibilité commune : le début/fin restent
    /// ajustables mais ne doivent pas sortir de ce créneau.
    let slotStart: Date?
    let slotEnd: Date?

    init(day: Date) {
        let start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        self.startsAt = start
        self.endsAt = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        self.slotStart = nil
        self.slotEnd = nil
    }

    init(startsAt: Date, endsAt: Date, slotStart: Date? = nil, slotEnd: Date? = nil) {
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.slotStart = slotStart
        self.slotEnd = slotEnd
    }
}

private struct AgendaToolbar: View {
    @Binding var selectedDay: Date
    @Binding var selectedDisplayMode: AgendaDisplayMode
    let acceptedFriends: [FriendRow]
    @Binding var selectedFriendIds: Set<String>
    let groups: [PoteGroup]
    let selectedGroup: PoteGroup?
    @Binding var showingGroupBusyEvents: Bool
    let onSelectGroup: (PoteGroup) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    moveWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button("Aujourd'hui") {
                    selectedDay = Date()
                }
                .buttonStyle(.bordered)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    moveWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)

                Spacer()

                DatePicker("Jour", selection: $selectedDay, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            Picker("Affichage", selection: $selectedDisplayMode) {
                ForEach(AgendaDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            FriendsFilterMenu(acceptedFriends: acceptedFriends, selectedFriendIds: $selectedFriendIds)
            GroupFilterMenu(
                groups: groups,
                selectedGroup: selectedGroup,
                showingGroupBusyEvents: $showingGroupBusyEvents,
                onSelectGroup: onSelectGroup
            )
        }
    }

    private func moveWeek(by value: Int) {
        switch selectedDisplayMode {
        case .day:
            selectedDay = Calendar.current.date(byAdding: .day, value: value, to: selectedDay) ?? selectedDay
        case .week:
            selectedDay = Calendar.current.date(byAdding: .day, value: value * 7, to: selectedDay) ?? selectedDay
        case .month:
            selectedDay = Calendar.current.date(byAdding: .month, value: value, to: selectedDay) ?? selectedDay
        }
    }
}

private struct FriendsFilterMenu: View {
    @EnvironmentObject private var dataStore: AppDataStore
    let acceptedFriends: [FriendRow]
    @Binding var selectedFriendIds: Set<String>
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack {
                Image(systemName: "person.2.fill")
                Text(filterTitle)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.poteSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(acceptedFriends.isEmpty)
        .sheet(isPresented: $showingPicker) {
            FriendsFilterPicker(acceptedFriends: acceptedFriends, selectedFriendIds: $selectedFriendIds)
        }
    }

    private var filterTitle: String {
        if acceptedFriends.isEmpty { return "Aucun ami accepté" }
        if selectedFriendIds.isEmpty { return "Aucun ami affiché" }
        if selectedFriendIds.count == acceptedFriends.count { return "Tous les amis" }
        if selectedFriendIds.count == 1 {
            let selected = acceptedFriends.first { selectedFriendIds.contains(dataStore.friendUserId(for: $0)) }
            return selected?.profile?.username ?? "1 ami"
        }
        return "\(selectedFriendIds.count) amis"
    }
}

private struct FriendsFilterPicker: View {
    @EnvironmentObject private var dataStore: AppDataStore
    let acceptedFriends: [FriendRow]
    @Binding var selectedFriendIds: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    var body: some View {
        NavigationStack {
            List {
                Button("Tous les amis") {
                    selectedFriendIds = Set(acceptedFriends.map { dataStore.friendUserId(for: $0) })
                }

                Button("Aucun") {
                    selectedFriendIds.removeAll()
                }

                ForEach(filteredFriends) { friend in
                    let friendId = dataStore.friendUserId(for: friend)
                    Button {
                        toggle(friendId)
                    } label: {
                        Label(friend.profile?.username ?? "Ami", systemImage: selectedFriendIds.contains(friendId) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.primary)
                    }
                }

                if filteredFriends.isEmpty {
                    Text("Aucun ami trouvé")
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchQuery, prompt: "Rechercher un ami")
            .navigationTitle("Amis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private var filteredFriends: [FriendRow] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return acceptedFriends }
        return acceptedFriends.filter { friend in
            let username = friend.profile?.username ?? ""
            let email = friend.profile?.email ?? ""
            return username.localizedCaseInsensitiveContains(query)
                || email.localizedCaseInsensitiveContains(query)
        }
    }

    private func toggle(_ id: String) {
        if selectedFriendIds.contains(id) {
            selectedFriendIds.remove(id)
        } else {
            selectedFriendIds.insert(id)
        }
    }
}

private struct GroupFilterMenu: View {
    let groups: [PoteGroup]
    let selectedGroup: PoteGroup?
    @Binding var showingGroupBusyEvents: Bool
    let onSelectGroup: (PoteGroup) -> Void

    var body: some View {
        Menu {
            Button(showingGroupBusyEvents ? "Masquer le groupe" : "Afficher le groupe") {
                if selectedGroup != nil {
                    showingGroupBusyEvents.toggle()
                } else if let first = groups.first {
                    onSelectGroup(first)
                }
            }

            ForEach(groups) { group in
                Button {
                    onSelectGroup(group)
                } label: {
                    Label(group.name, systemImage: selectedGroup?.id == group.id && showingGroupBusyEvents ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            HStack {
                Image(systemName: "person.3.fill")
                Text(groupTitle)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.poteSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(groups.isEmpty)
    }

    private var groupTitle: String {
        if groups.isEmpty { return "Aucun groupe" }
        guard showingGroupBusyEvents else { return "Aucun groupe affiché" }
        return selectedGroup?.name ?? "Groupe affiché"
    }
}

private struct AgendaWeekGrid: View {
    let selectedDay: Date
    let displayMode: AgendaDisplayMode
    let blocks: [AgendaBlock]
    let onSelectDay: (Date) -> Void
    let onSelectOwnEvent: (CalendarEvent) -> Void
    let onSelectBlock: (AgendaBlock) -> Void
    let onCreateDraft: (AgendaDraftEvent) -> Void
    @State private var expandedBlockId: String?

    private let hourRange = 7...23
    private let hourHeight: CGFloat = 64
    private let hourRailWidth: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let dayWidth = resolvedDayWidth(availableWidth: proxy.size.width)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    weekHeader(dayWidth: dayWidth)
                    Divider()
                    gridBody(dayWidth: dayWidth)
                }
                .frame(width: proxy.size.width)
                .background(Color.poteSecondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 18))
                .onAppear { logRenderCounts(dayWidth: dayWidth) }
                .onChange(of: renderSignature) { logRenderCounts(dayWidth: dayWidth) }
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

    private var renderSignature: String {
        "\(displayMode.rawValue)-\(weekDates.map(DateHelpers.apiDateString).joined(separator: ","))-\(blocks.map(\.id).joined(separator: "|"))"
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
                        if friendBusyCount(on: day) > 0 {
                            Capsule()
                                .fill(Color.secondary.opacity(0.55))
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
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: dayWidth, height: hourHeight)
                                .border(Color.poteSeparator.opacity(0.35), width: 0.5)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.45)
                                        .onEnded { _ in
                                            onCreateDraft(draftEvent(on: day, hour: hour))
                                        }
                                )
                        }
                    }
                }
            }

            let positionedBlocks = positionedBlocks(dayWidth: dayWidth)

            ForEach(positionedFriendBusyBlocks(positionedBlocks)) { positioned in
                Button {
                    onSelectBlock(positioned.block)
                } label: {
                    FriendBusyOverlayBlock(block: positioned.block)
                }
                .buttonStyle(.plain)
                .frame(width: max(dayWidth - 10, 36), height: max(positioned.height, 30))
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .offset(
                    x: hourRailWidth + CGFloat(positioned.dayIndex) * dayWidth + 5,
                    y: positioned.top
                )
                .zIndex(4)
            }

            ForEach(positionedEventBlocks(positionedBlocks)) { positioned in
                let isExpanded = expandedBlockId == positioned.id
                AgendaEventBlockView(
                    block: positioned.block,
                    hideLabels: false,
                    expanded: isExpanded
                ) {
                    onSelectBlock(positioned.block)
                }
                .frame(width: max(dayWidth - 8, 34), height: max(positioned.height, isExpanded ? 68 : 30))
                .offset(
                    x: hourRailWidth + CGFloat(positioned.dayIndex) * dayWidth + 4,
                    y: positioned.top
                )
                .zIndex(positioned.block.style.zIndex)
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

    private func positionedFriendBusyBlocks(_ positionedBlocks: [PositionedAgendaBlock]) -> [PositionedAgendaBlock] {
        positionedBlocks.filter { $0.block.style == .friendBusy }
    }

    private func positionedEventBlocks(_ positionedBlocks: [PositionedAgendaBlock]) -> [PositionedAgendaBlock] {
        positionedBlocks.filter { $0.block.style != .friendBusy }
    }

    private func friendBusyCount(on day: Date) -> Int {
        let bounds = DateHelpers.dayBounds(for: day)
        return blocks.filter { block in
            guard block.style == .friendBusy else { return false }
            guard let start = DateHelpers.parse(block.startAt), let end = DateHelpers.parse(block.endAt) else { return false }
            return start < bounds.end && end > bounds.start
        }.count
    }

    private func logRenderCounts(dayWidth: CGFloat) {
        let positionedBlocks = positionedBlocks(dayWidth: dayWidth)
        let friendBusyCount = positionedFriendBusyBlocks(positionedBlocks).count
        let eventCount = positionedEventBlocks(positionedBlocks).count
        let totalFriendBusy = blocks.filter { $0.style == .friendBusy }.count
        let unpositionedFriendBusy = blocks.filter { block in
            guard block.style == .friendBusy else { return false }
            return !positionedBlocks.contains { $0.block.id == block.id }
        }
        let sample = unpositionedFriendBusy.first.map { "\($0.startAt) -> \($0.endAt) parse=\(DateHelpers.parse($0.startAt) != nil)/\(DateHelpers.parse($0.endAt) != nil)" } ?? "none"
        let visibleDays = weekDates.map(DateHelpers.apiDateString).joined(separator: "...")
        print("PoteAgenda Week render: mode=\(displayMode.rawValue) days=\(visibleDays) friendBusyBlocks=\(totalFriendBusy) positionedFriendBusy=\(friendBusyCount) positionedEvents=\(eventCount) sampleUnpositioned=\(sample)")
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

private struct AgendaEventBlockView: View {
    let block: AgendaBlock
    let hideLabels: Bool
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: expanded ? 4 : 2) {
            if hideLabels {
                Text(block.subtitle ?? block.title)
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                    .opacity(0)
            } else {
                Text(block.title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle = block.subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if expanded {
                    Text(block.timeLabel)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .foregroundStyle(block.style.foregroundStyle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(block.style.backgroundColor(for: block))
                .overlay {
                    if block.style == .friendBusy {
                        Stripes()
                            .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(block.style.borderColor(for: block), lineWidth: block.style == .friendBusy ? 1 : 0)
                }
        }
    }
}

private struct FriendBusyOverlayBlock: View {
    let block: AgendaBlock

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.poteBusyOther)
            .overlay {
                Stripes()
                    .stroke(Color.secondary.opacity(0.7), lineWidth: 1.4)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.55), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.caption2.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .foregroundStyle(.secondary)
                .padding(5)
            }
    }
}

private struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 8
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

private struct AgendaMonthGrid: View {
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
                            Text("\(count) occupé")
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

private struct AgendaBlock: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let startAt: String
    let endAt: String
    let color: String
    let ownEvent: CalendarEvent?
    let style: AgendaBlockStyle
    let details: AgendaBlockDetails

    var timeLabel: String {
        guard let start = DateHelpers.parse(startAt), let end = DateHelpers.parse(endAt) else { return "" }
        return "\(DateHelpers.displayTimeString(start)) - \(DateHelpers.displayTimeString(end))"
    }

    var dateRangeLabel: String {
        guard let start = DateHelpers.parse(startAt), let end = DateHelpers.parse(endAt) else { return "" }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(DateHelpers.displayDateString(start)), \(DateHelpers.displayTimeString(start)) - \(DateHelpers.displayTimeString(end))"
        }
        return "Du \(DateHelpers.displayDateString(start)) \(DateHelpers.displayTimeString(start)) au \(DateHelpers.displayDateString(end)) \(DateHelpers.displayTimeString(end))"
    }

    init?(event: CalendarEvent) {
        guard let id = event.id else { return nil }
        self.id = id
        self.title = event.title
        self.subtitle = nil
        self.startAt = event.startAt
        self.endAt = event.endAt
        self.color = event.color
        self.ownEvent = event
        self.style = .ownBusy
        self.details = .ownEvent(event)
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        startAt: String,
        endAt: String,
        color: String,
        ownEvent: CalendarEvent?,
        style: AgendaBlockStyle = .outing,
        details: AgendaBlockDetails? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.startAt = startAt
        self.endAt = endAt
        self.color = color
        self.ownEvent = ownEvent
        self.style = style
        self.details = details ?? .generic
    }
}

private enum AgendaBlockDetails {
    case ownEvent(CalendarEvent)
    case receivedOuting(ReceivedOutingRow)
    case sentOuting(SentOutingRow)
    case friendBusy(BusyEvent, String, String)
    case generic
}

private enum AgendaBlockStyle: Equatable {
    case ownBusy
    case outing
    case friendBusy

    var foregroundStyle: Color {
        switch self {
        case .friendBusy:
            return .secondary
        case .ownBusy, .outing:
            return .white
        }
    }

    func backgroundColor(for block: AgendaBlock) -> Color {
        switch self {
        case .friendBusy:
            return Color.poteBusyOther
        case .ownBusy, .outing:
            return Color(hex: block.color)
        }
    }

    func borderColor(for block: AgendaBlock) -> Color {
        switch self {
        case .friendBusy:
            return Color.secondary.opacity(0.28)
        case .ownBusy, .outing:
            return Color(hex: block.color)
        }
    }

    var zIndex: Double {
        switch self {
        case .friendBusy:
            return 3
        case .ownBusy:
            return 2
        case .outing:
            return 1
        }
    }
}

private struct AgendaBlockDetailSheet: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var locallyRemindedParticipantIds = Set<String>()
    @State private var receivedParticipants: [OutingParticipantRow] = []
    @State private var showingCancelConfirmation = false
    let block: AgendaBlock
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(block.style == .friendBusy ? Color.poteBusyOther : Color(hex: block.color))
                                .frame(width: 12, height: 12)
                                .overlay {
                                    if block.style == .friendBusy {
                                        Circle().stroke(Color.secondary.opacity(0.55), lineWidth: 1)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(headerTitle)
                                    .font(.headline.weight(.bold))
                                if let subtitle = headerSubtitle {
                                    Text(subtitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(block.dateRangeLabel)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                detailSections
                actionSections
                discussionSection
            }
            .navigationTitle("Détail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismissSheet()
                    }
                }
            }
        }
        .task(id: block.id) {
            await loadReceivedParticipantsIfNeeded()
        }
        .confirmationDialog(
            "Supprimer cette invitation ?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                guard case .sentOuting(let row) = block.details else { return }
                Task {
                    await dataStore.cancelOuting(row.outing)
                    dismissSheet()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les participants ne verront plus cette invitation et la discussion associée sera fermée.")
        }
    }

    private func loadReceivedParticipantsIfNeeded() async {
        guard case .receivedOuting(let row) = block.details else { return }
        receivedParticipants = (try? await dataStore.outingParticipants(outingId: row.outing.id)) ?? []
    }

    private func organizerName(for row: ReceivedOutingRow) -> String? {
        receivedParticipants.first { $0.participant.userId == row.outing.creatorId }?.profile?.username
    }

    private func participantDisplayName(_ participant: OutingParticipantRow, creatorId: String) -> String {
        let name = participant.profile?.username ?? "Invité"
        return participant.participant.userId == creatorId ? "\(name) (organisateur)" : name
    }

    private var headerTitle: String {
        switch block.details {
        case .friendBusy(_, let friendName, _):
            return "\(friendName) pas dispo"
        default:
            return block.title
        }
    }

    private var headerSubtitle: String? {
        switch block.details {
        case .friendBusy:
            return nil
        default:
            return block.subtitle
        }
    }

    @ViewBuilder
    private var detailSections: some View {
        switch block.details {
        case .ownEvent(let event):
            Section("Indisponibilité") {
                DetailRow(label: "Titre", value: event.title)
                DetailRow(label: "Source", value: event.source)
            }
        case .receivedOuting(let row):
            Section("Invitation") {
                DetailRow(label: "Statut", value: row.response.agendaLabel)
                if let organizerName = organizerName(for: row) {
                    DetailRow(label: "Invité par", value: organizerName)
                }
                if let remindedAt = row.participant.remindedAt, row.response == .pending {
                    DetailRow(label: "Relance", value: DateHelpers.displayDateTimeString(remindedAt))
                }
                if let location = row.outing.location, !location.isEmpty {
                    DetailLocationRow(location: location)
                }
                if let note = row.outing.note, !note.isEmpty {
                    DetailRow(label: "Note", value: note)
                }
            }
            if !receivedParticipants.isEmpty {
                Section("Participants") {
                    ForEach(receivedParticipants) { participant in
                        HStack {
                            Text(participantDisplayName(participant, creatorId: row.outing.creatorId))
                            Spacer()
                            Text(participant.participant.response.agendaLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: participant.participant.response.agendaColor))
                        }
                    }
                }
            }
        case .sentOuting(let row):
            Section("Invitation envoyée") {
                DetailRow(label: "Statut", value: row.outing.confirmedAt == nil ? "En attente" : "Confirmée")
                if let location = row.outing.location, !location.isEmpty {
                    DetailLocationRow(location: location)
                }
                if let note = row.outing.note, !note.isEmpty {
                    DetailRow(label: "Note", value: note)
                }
            }
            Section("Participants") {
                let pendingParticipants = pendingParticipants(in: row)
                if pendingParticipants.count > 1 {
                    Button {
                        Task {
                            let didRemind = await dataStore.remindPendingOutingParticipants(
                                outing: row.outing,
                                participants: pendingParticipants.map(\.participant)
                            )
                            if didRemind {
                                locallyRemindedParticipantIds.formUnion(pendingParticipants.map(\.participant.userId))
                            }
                        }
                    } label: {
                        Label("Relancer tous", systemImage: "bell.badge")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(dataStore.isLoading || pendingParticipants.allSatisfy { isReminded($0) })
                }

                ForEach(row.participants) { participant in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(participant.profile?.username ?? "Invité")
                            Spacer()
                            Text(participant.participant.response.agendaLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: participant.participant.response.agendaColor))
                        }

                        if participant.participant.response == .pending {
                            Button {
                                Task {
                                    let didRemind = await dataStore.remindOutingParticipant(
                                        outing: row.outing,
                                        participant: participant.participant
                                    )
                                    if didRemind {
                                        locallyRemindedParticipantIds.insert(participant.participant.userId)
                                    }
                                }
                            } label: {
                                Label(
                                    isReminded(participant) ? "Relance envoyée" : "Relancer",
                                    systemImage: "bell"
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .disabled(dataStore.isLoading || isReminded(participant))
                        }
                    }
                }
            }
        case .friendBusy(let busyEvent, let friendName, let source):
            Section("\(friendName) pas dispo") {
                DetailRow(label: "Personne", value: friendName)
                DetailRow(label: "Quand", value: block.dateRangeLabel)
                DetailRow(label: "Via", value: source)
                if let title = busyEvent.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DetailRow(label: "Ce qu'il fait", value: title)
                } else {
                    DetailRow(label: "Ce qu'il fait", value: "Détail non partagé")
                }
            }
        case .generic:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionSections: some View {
        switch block.details {
        case .ownEvent(let event):
            Section {
                Button("Supprimer l'indisponibilité", role: .destructive) {
                    Task {
                        await dataStore.deleteEvent(event)
                        dismissSheet()
                    }
                }
            }
        case .receivedOuting(let row):
            Section("Réponse") {
                Button("Accepter") {
                    Task {
                        await dataStore.respondToOuting(row.outing, response: .accepted)
                        dismissSheet()
                    }
                }
                .disabled(row.response == .accepted)

                Button("Refuser", role: .destructive) {
                    Task {
                        await dataStore.respondToOuting(row.outing, response: .declined)
                        dismissSheet()
                    }
                }
                .disabled(row.response == .declined)

                Button("Remettre en attente") {
                    Task {
                        await dataStore.respondToOuting(row.outing, response: .pending)
                        dismissSheet()
                    }
                }
                .disabled(row.response == .pending)
            }
        case .sentOuting:
            Section {
                Button("Supprimer l'invitation", role: .destructive) {
                    showingCancelConfirmation = true
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var discussionSection: some View {
        switch block.details {
        case .receivedOuting(let row) where canDiscussOuting(row.outing):
            OutingDiscussionSection(outing: row.outing)
        case .sentOuting(let row) where canDiscussOuting(row.outing):
            OutingDiscussionSection(outing: row.outing)
        default:
            EmptyView()
        }
    }

    private func dismissSheet() {
        onClose()
        dismiss()
    }

    private func pendingParticipants(in row: SentOutingRow) -> [OutingParticipantRow] {
        row.participants.filter { $0.participant.response == .pending }
    }

    private func isReminded(_ participant: OutingParticipantRow) -> Bool {
        locallyRemindedParticipantIds.contains(participant.participant.userId)
            || agendaRecentlyReminded(participant.participant.remindedAt)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct DetailLocationRow: View {
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Lieu")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            LocationLink(location: location)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}

struct AddEventView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: AgendaCreationKind = .outing
    @State private var title = ""
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var color = "#6366f1"
    @State private var location = ""
    @State private var locationCoordinate: CLLocationCoordinate2D?
    @State private var note = ""
    @State private var selectedFriendIds = Set<String>()
    @State private var selectedGroupId: String?
    @State private var friendSearchQuery = ""
    private let slotStart: Date?
    private let slotEnd: Date?

    init(draft: AgendaDraftEvent) {
        _startsAt = State(initialValue: draft.startsAt)
        _endsAt = State(initialValue: draft.endsAt)
        slotStart = draft.slotStart
        slotEnd = draft.slotEnd
    }

    /// Membres/amis invités dont une indisponibilité connue chevauche le
    /// créneau actuellement choisi. On laisse l'utilisateur créer
    /// l'invitation quand même : mieux vaut prévenir que bloquer, la personne
    /// pourra toujours répondre "je ne peux pas" elle-même.
    /// Ce brouillon vient du tap sur une disponibilité commune calculée à
    /// partir des indisponibilités du groupe : dans ce cas `dataStore.busyEvents`
    /// et `dataStore.selectedGroupMembers` sont garantis correspondre à ce
    /// groupe (c'est cette même donnée qui a servi à calculer le créneau), donc
    /// on peut s'y fier sans dépendre du timing de `selectedGroupId`.
    private var groupBusyEventsApply: Bool {
        slotStart != nil || (selectedGroupId != nil && selectedGroupId == dataStore.selectedGroup?.id)
    }

    private var conflictingUserIds: [String] {
        guard startsAt < endsAt else { return [] }
        var invitedIds = selectedFriendIds
        if groupBusyEventsApply {
            invitedIds.formUnion(dataStore.selectedGroupMembers.map { $0.member.userId })
        }
        invitedIds.remove(dataStore.currentUserId)

        var relevantEvents = dataStore.friendsBusyEvents
        if groupBusyEventsApply {
            relevantEvents += dataStore.busyEvents
        }

        var conflicts = Set<String>()
        for event in relevantEvents {
            guard invitedIds.contains(event.userId),
                  let eventStart = DateHelpers.parse(event.startAt),
                  let eventEnd = DateHelpers.parse(event.endAt),
                  eventStart < endsAt, eventEnd > startsAt
            else { continue }
            conflicts.insert(event.userId)
        }
        return conflicts.sorted { displayName(for: $0) < displayName(for: $1) }
    }

    private var isOutsideKnownFreeSlot: Bool {
        guard let slotStart, let slotEnd, startsAt < endsAt else { return false }
        return startsAt < slotStart || endsAt > slotEnd
    }

    /// Message d'alerte prioritairement nominatif : on nomme qui n'est plus
    /// disponible dès qu'on le sait ; le message générique ne sert que de
    /// filet quand on sait juste qu'on sort du créneau commun sans pouvoir
    /// dire précisément qui pose problème (ex. données pas encore chargées).
    private var conflictWarning: String? {
        let names = conflictingUserIds.map(displayName)
        if !names.isEmpty {
            let joined = names.joined(separator: ", ")
            return names.count > 1
                ? "Attention : \(joined) ne sont plus disponibles sur ce créneau."
                : "Attention : \(joined) n'est plus disponible sur ce créneau."
        }
        if isOutsideKnownFreeSlot {
            return "Attention : vous sortez du créneau où tout le monde était disponible."
        }
        return nil
    }

    private func displayName(for userId: String) -> String {
        if let friend = dataStore.acceptedFriends.first(where: { dataStore.friendUserId(for: $0) == userId }) {
            return friend.profile?.username ?? "Ami"
        }
        if let member = dataStore.selectedGroupMembers.first(where: { $0.member.userId == userId }) {
            return member.profile?.username ?? "Membre"
        }
        return "Quelqu'un"
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(AgendaCreationKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("Titre", text: $title)
                    DatePicker("Début", selection: $startsAt)
                        .onChange(of: startsAt) { _, newValue in
                            if endsAt <= newValue {
                                endsAt = Calendar.current.date(byAdding: .hour, value: 1, to: newValue) ?? newValue
                            }
                        }
                    DatePicker("Fin", selection: $endsAt, in: startsAt...)
                    if let warning = conflictWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Créneau")
                } footer: {
                    if let slotStart, let slotEnd, conflictWarning == nil {
                        Text("Ce créneau vient d'une disponibilité commune entre \(DateHelpers.displayTimeString(slotStart)) et \(DateHelpers.displayTimeString(slotEnd)).")
                    }
                }

                if kind == .busy {
                    Section("Couleur") {
                        Picker("Couleur", selection: $color) {
                            Text("Indigo").tag("#6366f1")
                            Text("Rouge").tag("#ef4444")
                            Text("Orange").tag("#f97316")
                            Text("Gris").tag("#64748b")
                        }
                    }
                } else {
                    Section("Détails") {
                        LocationSearchField(location: $location, coordinate: $locationCoordinate)
                        TextField("Note", text: $note, axis: .vertical)
                    }

                    Section("Invités amis") {
                        if dataStore.acceptedFriends.isEmpty {
                            Text("Aucun ami accepté")
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("Rechercher un ami", text: $friendSearchQuery)
                                .poteSearchInputTraits()

                            ForEach(filteredAcceptedFriends) { friend in
                                let friendId = dataStore.friendUserId(for: friend)
                                Button {
                                    toggleFriend(friendId)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(friend.profile?.username ?? "Ami")
                                                .foregroundStyle(.primary)
                                            if let email = friend.profile?.email {
                                                Text(email)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: selectedFriendIds.contains(friendId) ? "checkmark.circle.fill" : "circle")
                                    }
                                }
                            }

                            if filteredAcceptedFriends.isEmpty {
                                Text("Aucun ami trouvé")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Invités groupe") {
                        if dataStore.groups.isEmpty {
                            Text("Aucun groupe disponible")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dataStore.groups) { group in
                                Button {
                                    toggleGroup(group.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(group.name)
                                                .foregroundStyle(.primary)
                                            if let description = group.description, !description.isEmpty {
                                                Text(description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: selectedGroupId == group.id ? "checkmark.circle.fill" : "circle")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(kind == .busy ? "Indisponibilité" : "Invitation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        Task {
                            if kind == .busy {
                                await dataStore.addEvent(title: title, startsAt: startsAt, endsAt: endsAt, color: color)
                            } else {
                                await dataStore.createOuting(
                                    title: title,
                                    startsAt: startsAt,
                                    endsAt: endsAt,
                                    location: cleaned(location),
                                    note: cleaned(note),
                                    friendIds: Array(selectedFriendIds),
                                    group: selectedGroup
                                )
                            }
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .onChange(of: kind) {
                switch kind {
                case .busy:
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = "Occupé"
                    }
                case .outing:
                    if title == "Occupé" {
                        title = ""
                    }
                }
            }
            .onAppear {
                if selectedFriendIds.isEmpty {
                    selectedFriendIds = defaultInviteeIds
                }
                if selectedGroupId == nil, dataStore.agendaShowingGroupBusyEvents {
                    selectedGroupId = dataStore.selectedGroup?.id
                }
            }
        }
    }

    private var defaultInviteeIds: Set<String> {
        let acceptedIds = Set(dataStore.acceptedFriends.map { dataStore.friendUserId(for: $0) })
        return dataStore.agendaSelectedFriendIds.intersection(acceptedIds)
    }

    private var selectedGroup: PoteGroup? {
        selectedGroupId.flatMap { id in dataStore.groups.first { $0.id == id } }
    }

    private var filteredAcceptedFriends: [FriendRow] {
        let query = friendSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return dataStore.acceptedFriends }
        return dataStore.acceptedFriends.filter { friend in
            let username = friend.profile?.username ?? ""
            let email = friend.profile?.email ?? ""
            return username.localizedCaseInsensitiveContains(query)
                || email.localizedCaseInsensitiveContains(query)
        }
    }

    private var isValid: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasInvitees = kind == .busy || !selectedFriendIds.isEmpty || selectedGroupId != nil
        return hasTitle && startsAt < endsAt && hasInvitees
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func toggleFriend(_ id: String) {
        if selectedFriendIds.contains(id) {
            selectedFriendIds.remove(id)
        } else {
            selectedFriendIds.insert(id)
        }
    }

    private func toggleGroup(_ id: String) {
        selectedGroupId = selectedGroupId == id ? nil : id
    }
}

private enum AgendaCreationKind: String, CaseIterable, Identifiable {
    case outing
    case busy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .busy: "Indispo"
        case .outing: "Invitation"
        }
    }
}

private let agendaRemindCooldownSeconds: TimeInterval = 12 * 60 * 60

private func agendaRecentlyReminded(_ remindedAt: String?) -> Bool {
    guard let remindedAt, let date = DateHelpers.parse(remindedAt) else { return false }
    return Date().timeIntervalSince(date) < agendaRemindCooldownSeconds
}

private extension Color {
    static var poteGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color.gray.opacity(0.08)
        #endif
    }

    static var poteSecondaryGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.white
        #endif
    }

    static var poteSeparator: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #else
        Color.gray
        #endif
    }

    static var poteBusyOther: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #else
        Color.gray.opacity(0.24)
        #endif
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private extension OutingResponse {
    var agendaLabel: String {
        switch self {
        case .pending: "En attente"
        case .accepted: "Acceptée"
        case .declined: "Refusée"
        }
    }

    var agendaColor: String {
        switch self {
        case .pending: "#f97316"
        case .accepted: "#22c55e"
        case .declined: "#ef4444"
        }
    }
}
