import XCTest
@testable import PoteAgenda

/// Vérifie que les erreurs backend ne fuient jamais en clair vers l'UI
/// (cf. revue de sécurité : messages Supabase bruts affichés à l'utilisateur).
final class SupabaseServiceErrorMappingTests: XCTestCase {
    func testKnownStatusCodesMapToGenericFrenchMessages() {
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 401), "Cette action n'est pas autorisée.")
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 403), "Cette action n'est pas autorisée.")
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 404), "Élément introuvable.")
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 409), "Cette action entre en conflit avec une donnée existante.")
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 429), "Trop de requêtes, réessaie dans un instant.")
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 500), "Erreur serveur, réessaie plus tard.")
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 503), "Erreur serveur, réessaie plus tard.")
    }

    func testUnknownStatusCodeFallsBackToGenericMessage() {
        XCTAssertEqual(SupabaseService.genericErrorMessage(forStatusCode: 418), "Une erreur est survenue. Réessaie.")
    }

    /// Garde-fou : aucun message généré ne doit jamais contenir de fragments
    /// typiques d'une erreur Postgres/PostgREST brute (nom de contrainte,
    /// code SQLSTATE, texte "duplicate key", etc.).
    func testGenericMessagesNeverLeakBackendVocabulary() {
        let suspiciousFragments = ["duplicate key", "constraint", "relation", "syntax error", "P0001", "23505", "42501"]
        for statusCode in [400, 401, 403, 404, 409, 422, 429, 500, 503] {
            let message = SupabaseService.genericErrorMessage(forStatusCode: statusCode)
            for fragment in suspiciousFragments {
                XCTAssertFalse(
                    message.lowercased().contains(fragment.lowercased()),
                    "Le message pour le statut \(statusCode) contient un fragment backend suspect : \(fragment)"
                )
            }
        }
    }
}
