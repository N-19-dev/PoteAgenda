import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var query = ""
    @State private var results: [Profile] = []
    let onOpenAgenda: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Recherche") {
                    TextField("Pseudo ou email", text: $query)
                        .poteSearchInputTraits()
                        .onSubmit { Task { await search() } }
                    Button("Rechercher") {
                        Task { await search() }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)

                    ForEach(results) { profile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(profile.username)
                                Text(profile.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Ajouter") {
                                Task { await dataStore.sendFriendRequest(profile) }
                            }
                        }
                    }
                }

                Section("Amis et demandes") {
                    if dataStore.friends.isEmpty {
                        EmptyStateView(title: "Aucun ami pour le moment", systemImage: "person.2.slash")
                    } else {
                        ForEach(dataStore.friends) { row in
                            if row.friendship.status == .accepted {
                                Button {
                                    dataStore.agendaSelectedFriendIds = [dataStore.friendUserId(for: row)]
                                    onOpenAgenda()
                                } label: {
                                    friendRowContent(row)
                                }
                                .buttonStyle(.plain)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    friendRowContent(row)

                                    if row.friendship.status == .pending {
                                        HStack {
                                            Button("Accepter") {
                                                Task { await dataStore.respondToFriendship(row.friendship, accept: true) }
                                            }
                                            Button("Refuser", role: .destructive) {
                                                Task { await dataStore.respondToFriendship(row.friendship, accept: false) }
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Amis")
            .refreshable { await dataStore.refreshFriends() }
        }
    }

    private func search() async {
        do {
            results = try await dataStore.searchProfiles(query)
        } catch {
            dataStore.errorMessage = error.localizedDescription
        }
    }

    private func friendRowContent(_ row: FriendRow) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(row.profile?.username ?? "Profil")
                    .foregroundStyle(.primary)
                Text(row.friendship.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if row.friendship.status == .accepted {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
