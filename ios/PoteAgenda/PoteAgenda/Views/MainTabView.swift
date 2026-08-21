import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject var dataStore: AppDataStore
    @State private var selectedTab: PoteTab = .agenda

    var body: some View {
        TabView(selection: $selectedTab) {
            AgendaView()
                .tabItem { Label("Agenda", systemImage: "calendar") }
                .tag(PoteTab.agenda)

            FriendsView {
                selectedTab = .agenda
            }
                .tabItem { Label("Amis", systemImage: "person.2") }
                .tag(PoteTab.friends)

            GroupsView {
                selectedTab = .agenda
            }
                .tabItem { Label("Groupes", systemImage: "rectangle.3.group") }
                .tag(PoteTab.groups)

            InvitationsView()
                .tabItem { Label("Invitations", systemImage: "envelope") }
                .tag(PoteTab.invitations)

            SettingsView()
                .tabItem { Label("Compte", systemImage: "person.crop.circle") }
                .tag(PoteTab.settings)
        }
        .environmentObject(dataStore)
        .task {
            await dataStore.requestNotificationAuthorization()
            if dataStore.departureRemindersEnabled {
                dataStore.requestLocationAuthorizationIfNeeded()
            }
            await dataStore.refreshAll()
        }
        .alert("Erreur", isPresented: Binding(
            get: { dataStore.errorMessage != nil },
            set: { if !$0 { dataStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dataStore.errorMessage ?? "")
        }
    }
}

private enum PoteTab: Hashable {
    case agenda
    case friends
    case groups
    case invitations
    case settings
}
