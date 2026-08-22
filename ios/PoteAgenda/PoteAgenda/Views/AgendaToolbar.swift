import SwiftUI

struct AgendaToolbar: View {
    @Binding var selectedDay: Date
    @Binding var selectedDisplayMode: AgendaDisplayMode
    let acceptedFriends: [FriendRow]
    @Binding var selectedFriendIds: Set<String>
    let groups: [PoteGroup]
    let selectedGroup: PoteGroup?
    @Binding var showingGroupBusyEvents: Bool
    let onSelectGroup: (PoteGroup) -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        moveWeek(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Période précédente")

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
                    .accessibilityLabel("Période suivante")

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
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Disponibilités affichées")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                FriendsFilterMenu(acceptedFriends: acceptedFriends, selectedFriendIds: $selectedFriendIds)
                GroupFilterMenu(
                    groups: groups,
                    selectedGroup: selectedGroup,
                    showingGroupBusyEvents: $showingGroupBusyEvents,
                    onSelectGroup: onSelectGroup
                )

                Label("Tes amis voient seulement Libre/Occupé, jamais tes titres.", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
        if selectedFriendIds.isEmpty { return "Voir les disponibilités de…" }
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
        guard showingGroupBusyEvents else { return "Voir un groupe…" }
        return selectedGroup?.name ?? "Groupe affiché"
    }
}
