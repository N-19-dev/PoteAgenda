import CoreLocation
import SwiftUI

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
