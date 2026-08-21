import SwiftUI

/// Possède l'unique instance d'`AppDataStore` pour la durée de la session
/// authentifiée. `@StateObject` la construit une seule fois, dans `init`,
/// et la conserve tant que cette vue garde son identité (c'est-à-dire tant
/// que `RootView` continue de présenter une session) — même si `RootView`
/// se re-rend avec une nouvelle valeur de `session` après un refresh.
struct AuthenticatedRootView: View {
    @StateObject private var dataStore: AppDataStore

    init(service: SupabaseService, session: AuthSession) {
        _dataStore = StateObject(wrappedValue: AppDataStore(service: service, session: session))
    }

    var body: some View {
        MainTabView()
            .environmentObject(dataStore)
    }
}
