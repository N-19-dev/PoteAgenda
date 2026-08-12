import SwiftUI

@main
struct PoteAgendaApp: App {
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .task {
                    await sessionStore.restoreSession()
                }
        }
    }
}
