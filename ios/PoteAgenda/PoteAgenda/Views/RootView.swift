import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        Group {
            if let session = sessionStore.session {
                MainTabView(dataStore: AppDataStore(service: sessionStore.service, session: session))
            } else {
                AuthView()
            }
        }
        .alert("Erreur", isPresented: Binding(
            get: { sessionStore.errorMessage != nil },
            set: { if !$0 { sessionStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sessionStore.errorMessage ?? "")
        }
    }
}
