import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var session: AuthSession?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let service: SupabaseService
    private let storageKey = "poteagenda.supabase.session"

    init() {
        do {
            service = SupabaseService(config: try SupabaseConfig.load())
        } catch {
            service = SupabaseService(config: SupabaseConfig(url: URL(string: "https://invalid.local")!, publishableKey: "missing"))
            errorMessage = error.localizedDescription
        }
    }

    func restoreSession() async {
        guard let data = KeychainService.load(forKey: storageKey) else { return }
        do {
            let stored = try JSONDecoder().decode(AuthSession.self, from: data)
            session = try await service.refresh(session: stored)
            persist()
        } catch {
            KeychainService.delete(forKey: storageKey)
            session = nil
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            session = try await service.signIn(email: email, password: password)
            persist()
        }
    }

    func signUp(email: String, password: String, username: String) async {
        await run {
            if let created = try await service.signUp(email: email, password: password, username: username) {
                session = created
                persist()
            } else {
                errorMessage = "Compte créé. Vérifie ton email avant de te connecter."
            }
        }
    }

    func signOut() async {
        guard let session else { return }
        await run {
            try? await service.signOut(session: session)
            self.session = nil
            KeychainService.delete(forKey: storageKey)
        }
    }

    func deleteAccount() async {
        guard let session else { return }
        await run {
            try await service.deleteAccount(session: session)
            self.session = nil
            KeychainService.delete(forKey: storageKey)
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func persist() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        KeychainService.save(data, forKey: storageKey)
    }
}
