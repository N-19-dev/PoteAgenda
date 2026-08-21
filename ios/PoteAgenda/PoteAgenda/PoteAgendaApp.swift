import SwiftUI

@main
struct PoteAgendaApp: App {
    @StateObject private var sessionStore = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .task {
                    await sessionStore.restoreSession()
                }
                // Le minuteur de rafraîchissement proactif de SessionStore ne
                // tourne pas pendant que l'app est suspendue : on rattrape ici
                // un token expiré (ou proche de l'expiration) au retour au premier plan.
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await sessionStore.refreshSessionIfNeeded() }
                }
        }
    }
}
