import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var session: AuthSession? {
        didSet { scheduleProactiveRefresh() }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?

    let service: SupabaseService
    private let storageKey = "poteagenda.supabase.session"
    /// Marge avant l'expiration du token à laquelle on déclenche un
    /// rafraîchissement proactif, pour qu'aucune requête ne parte jamais avec
    /// un token déjà expiré pendant que l'app est active.
    private static let refreshBuffer: TimeInterval = 60
    /// Délai avant de retenter un rafraîchissement après un échec temporaire
    /// (réseau indisponible, 5xx Supabase) : on ne déconnecte pas l'utilisateur
    /// pour ce genre d'erreur, on retente plus tard.
    private static let refreshRetryDelay: TimeInterval = 30
    private var sessionExpiresAt: Date?
    private var refreshTask: Task<Void, Never>?

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

    /// Ne remonte jamais d'erreur distincte selon que l'email existe ou non
    /// côté serveur (le endpoint Supabase /recover répond 200 dans les deux
    /// cas) : ça évite de laisser deviner quels emails sont inscrits.
    func resetPassword(email: String) async -> Bool {
        var succeeded = false
        await run {
            try await service.resetPassword(email: email)
            succeeded = true
        }
        return succeeded
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

    /// À appeler quand l'app redevient active (ex. retour de suspension) : le
    /// minuteur de rafraîchissement proactif repose sur `Task.sleep`, qui ne
    /// s'exécute pas pendant que l'app est suspendue. Le token peut donc avoir
    /// expiré (ou être proche de l'expiration) sans que personne ne l'ait
    /// renouvelé entre-temps.
    func refreshSessionIfNeeded() async {
        guard let current = session else { return }
        if let sessionExpiresAt, sessionExpiresAt.timeIntervalSinceNow > Self.refreshBuffer { return }
        await performRefresh(from: current)
    }

    private func scheduleProactiveRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        guard let session else {
            sessionExpiresAt = nil
            return
        }
        let expiresAt = Date().addingTimeInterval(TimeInterval(session.expiresIn))
        sessionExpiresAt = expiresAt
        let delay = max(expiresAt.timeIntervalSinceNow - Self.refreshBuffer, 5)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.performRefresh(from: session)
        }
    }

    /// Rafraîchit la session, ou renvoie proprement vers la connexion si le
    /// refresh token n'est plus valide (il n'y a pas de récupération
    /// silencieuse possible dans ce cas). Une panne réseau ou une erreur 5xx
    /// Supabase est temporaire : on garde la session en place et on retente,
    /// plutôt que de déconnecter l'utilisateur pour un problème passager.
    private func performRefresh(from current: AuthSession) async {
        do {
            session = try await service.refresh(session: current)
            persist()
        } catch {
            if isInvalidRefreshToken(error) {
                session = nil
                KeychainService.delete(forKey: storageKey)
            } else {
                scheduleRetry(from: current)
            }
        }
    }

    private func isInvalidRefreshToken(_ error: Error) -> Bool {
        guard case AppError.http(let status, _) = error else { return false }
        return status == 400 || status == 401
    }

    private func scheduleRetry(from current: AuthSession) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.refreshRetryDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.performRefresh(from: current)
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
