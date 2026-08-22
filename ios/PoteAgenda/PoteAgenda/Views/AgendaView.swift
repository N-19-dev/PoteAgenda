import SwiftUI

struct AgendaView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draftEvent: AgendaDraftEvent?
    @State private var selectedDisplayMode: AgendaDisplayMode = .week
    @State private var didSetInitialDisplayMode = false
    @State private var didSelectInitialFriends = false
    @State private var eventToDelete: CalendarEvent?
    @State private var selectedBlock: AgendaBlock?
    @State private var overlapGroup: AgendaOverlapGroup?
    @State private var calendarPageOffset = 0

    private let calendarPageRadius = 5

    /// Sur iPhone (largeur compacte), une semaine complète comprime trop les
    /// blocs pour rester lisible : on démarre en vue jour, une seule fois au
    /// premier affichage. Sur iPad/desktop (largeur régulière), la vue
    /// semaine reste la valeur par défaut.
    private func applyInitialDisplayModeIfNeeded() {
        guard !didSetInitialDisplayMode else { return }
        didSetInitialDisplayMode = true
        if horizontalSizeClass == .compact {
            selectedDisplayMode = .day
        }
    }

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
                                    onSelectOverlapGroup: { blocks in
                                        overlapGroup = AgendaOverlapGroup(blocks: blocks)
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
                    .accessibilityLabel("Ajouter un événement")
                }
            }
            .task {
                applyInitialDisplayModeIfNeeded()
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
            .sheet(item: $overlapGroup) { group in
                AgendaOverlapGroupSheet(
                    blocks: group.blocks,
                    onSelect: { block in
                        overlapGroup = nil
                        selectedBlock = block
                    },
                    onClose: { overlapGroup = nil }
                )
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

        let selectedFriendBusyEvents = dataStore.friendsBusyEvents
            .filter { effectiveSelectedFriendIds.contains($0.userId) }
        let selectedFriendBusyKeys = Set(selectedFriendBusyEvents.map(busyEventKey))

        blocks += selectedFriendBusyEvents
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

        // Invitations en attente de réponse chez un ami : pas une
        // indisponibilité confirmée, juste un signal qu'il pourrait le
        // devenir. Volontairement distinct de "Occupé" (couleur + libellé).
        //
        // On exclut les créneaux qui correspondent à une invitation que je
        // connais déjà en détail (envoyée par moi, ou reçue de cet ami) :
        // sinon le bloc "sollicité(e)" (translucide) se superpose pile sur
        // mon propre bloc d'invitation (titre visible, à juste titre car
        // c'est la mienne) et laisse voir le titre en transparence — ça
        // donnait l'impression que le bloc "sollicité" révélait le titre.
        blocks += dataStore.friendsPendingOutings
            .filter { effectiveSelectedFriendIds.contains($0.userId) }
            .filter { !isKnownOutingSlot(friendId: $0.userId, startAt: $0.startAt, endAt: $0.endAt) }
            .map { pending in
                AgendaBlock(
                    id: "friend-pending-\(pending.userId)-\(pending.startAt)",
                    title: friendName(for: pending.userId),
                    subtitle: "Sollicité(e)",
                    startAt: pending.startAt,
                    endAt: pending.endAt,
                    color: "#f97316",
                    ownEvent: nil,
                    style: .friendPending,
                    details: .friendPending(pending, friendName(for: pending.userId))
                )
            }

        if dataStore.agendaShowingGroupBusyEvents {
            // Un ami à la fois sélectionné individuellement et membre du
            // groupe affiché a déjà une barre "ami sélectionné" ci-dessus
            // pour la même indispo réelle : on ne la duplique pas ici, sinon
            // deux barres identiques se chevauchent pile sur le même créneau.
            blocks += dataStore.busyEvents
                .filter { !selectedFriendBusyKeys.contains(busyEventKey($0)) }
                .map { busyEvent in
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

    /// Identifie une indisponibilité par (personne, horaires) pour pouvoir
    /// dédupliquer un même ami vu à la fois via "amis sélectionnés" et via un
    /// groupe affiché.
    private func busyEventKey(_ busyEvent: BusyEvent) -> String {
        "\(busyEvent.userId)|\(busyEvent.startAt)|\(busyEvent.endAt)"
    }

    /// true si ce créneau (ami, horaires) correspond à une invitation dont
    /// je connais déjà le titre : une que j'ai envoyée à cet ami, ou une que
    /// j'ai reçue de sa part. Sert à ne pas superposer le bloc ambiant
    /// "sollicité(e)" sur mon propre bloc d'invitation.
    private func isKnownOutingSlot(friendId: String, startAt: String, endAt: String) -> Bool {
        let sentMatch = dataStore.sentOutings.contains { row in
            row.outing.startsAt == startAt
                && row.outing.endsAt == endAt
                && row.participants.contains { $0.participant.userId == friendId }
        }
        if sentMatch { return true }

        return dataStore.outings.contains { row in
            row.outing.creatorId == friendId
                && row.outing.startsAt == startAt
                && row.outing.endsAt == endAt
        }
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
