import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var showingCreateGroup = false
    let onOpenAgenda: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Groupes") {
                    if dataStore.groups.isEmpty {
                        EmptyStateView(title: "Aucun groupe", systemImage: "rectangle.3.group")
                    } else {
                        ForEach(dataStore.groups) { group in
                            NavigationLink {
                                GroupDetailView(group: group, onOpenAgenda: onOpenAgenda)
                            } label: {
                                GroupListRow(group: group, selected: dataStore.selectedGroup?.id == group.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groupes")
            .toolbar {
                ToolbarItem(placement: .poteTopBarTrailing) {
                    Button {
                        showingCreateGroup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await dataStore.refreshGroups() }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
            }
        }
    }
}

private struct GroupListRow: View {
    let group: PoteGroup
    let selected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .foregroundStyle(.primary)
                if let description = group.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct GroupDetailView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var showingEditGroup = false
    @State private var showingAddMembers = false
    let group: PoteGroup
    let onOpenAgenda: () -> Void

    private var isOwner: Bool {
        group.ownerId == dataStore.currentUserId
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.title3.weight(.bold))
                    if let description = group.description, !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    Task {
                        await dataStore.selectGroup(group)
                        dataStore.agendaShowingGroupBusyEvents = true
                        dataStore.agendaSelectedFriendIds.removeAll()
                        onOpenAgenda()
                    }
                } label: {
                    Label("Afficher dans mon agenda", systemImage: "calendar")
                }
            }

            Section("Membres") {
                if dataStore.selectedGroupMembers.isEmpty {
                    EmptyStateView(title: "Aucun membre", systemImage: "person.3")
                } else {
                    ForEach(dataStore.selectedGroupMembers) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.profile?.username ?? "Profil")
                                if let email = row.profile?.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(row.member.role == "owner" ? "Owner" : "Membre")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            if isOwner && row.member.userId != dataStore.currentUserId {
                                Button("Retirer", role: .destructive) {
                                    Task { await dataStore.removeMember(from: group, userId: row.member.userId) }
                                }
                            }
                        }
                    }
                }
            }

            Section("Disponibilites") {
                BusyTimelineView(events: dataStore.busyEvents)
            }
        }
        .navigationTitle(group.name)
        .toolbar {
            if isOwner {
                ToolbarItemGroup(placement: .poteTopBarTrailing) {
                    Button {
                        showingAddMembers = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    Button {
                        showingEditGroup = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .task { await dataStore.selectGroup(group) }
        .refreshable { await dataStore.selectGroup(group) }
        .sheet(isPresented: $showingEditGroup) {
            EditGroupView(group: group)
        }
        .sheet(isPresented: $showingAddMembers) {
            AddGroupMembersView(group: group)
        }
    }
}

private struct BusyTimelineView: View {
    let events: [BusyEvent]

    var body: some View {
        if events.isEmpty {
            Text("Tout le monde semble libre sur cette période.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(event.title ?? "Occupé")
                        EventTimeText(start: event.startAt, end: event.endAt)
                    }
                }
            }
        }
    }
}

private struct CreateGroupView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var selectedFriendIds = Set<String>()

    var body: some View {
        NavigationStack {
            Form {
                Section("Groupe") {
                    TextField("Nom", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                }

                Section("Membres") {
                    FriendSelectionRows(selectedFriendIds: $selectedFriendIds)
                }
            }
            .navigationTitle("Nouveau groupe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task {
                            await dataStore.createGroup(
                                name: name,
                                description: cleaned(description),
                                memberIds: Array(selectedFriendIds)
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct EditGroupView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss
    let group: PoteGroup
    @State private var name: String
    @State private var description: String

    init(group: PoteGroup) {
        self.group = group
        _name = State(initialValue: group.name)
        _description = State(initialValue: group.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                TextField("Description", text: $description, axis: .vertical)
            }
            .navigationTitle("Modifier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task {
                            await dataStore.updateGroup(group, name: name, description: cleaned(description))
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AddGroupMembersView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss
    let group: PoteGroup
    @State private var selectedFriendIds = Set<String>()

    private var existingMemberIds: Set<String> {
        Set(dataStore.selectedGroupMembers.map { $0.member.userId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ajouter des membres") {
                    FriendSelectionRows(
                        selectedFriendIds: $selectedFriendIds,
                        excludedFriendIds: existingMemberIds
                    )
                }
            }
            .navigationTitle("Membres")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        Task {
                            await dataStore.addMembers(to: group, userIds: Array(selectedFriendIds))
                            dismiss()
                        }
                    }
                    .disabled(selectedFriendIds.isEmpty)
                }
            }
        }
    }
}

private struct FriendSelectionRows: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Binding var selectedFriendIds: Set<String>
    var excludedFriendIds = Set<String>()

    var body: some View {
        let friends = dataStore.acceptedFriends.filter { friend in
            !excludedFriendIds.contains(dataStore.friendUserId(for: friend))
        }

        if friends.isEmpty {
            Text("Aucun ami disponible")
                .foregroundStyle(.secondary)
        } else {
            ForEach(friends) { friend in
                let friendId = dataStore.friendUserId(for: friend)
                Button {
                    toggle(friendId)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
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
