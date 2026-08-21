import Security
import XCTest
@testable import PoteAgenda

/// Vérifie que la session (dont le refresh token) est stockée avec
/// l'accessibilité attendue (cf. revue de sécurité : un refresh token stocké
/// en `AfterFirstUnlock` sans `ThisDeviceOnly` peut migrer vers un autre
/// appareil via une restauration de sauvegarde chiffrée).
final class KeychainServiceTests: XCTestCase {
    private let testKey = "poteagenda.tests.keychainAccessibility"
    private let keychainService = "com.poteagenda.app.session"

    override func tearDown() {
        KeychainService.delete(forKey: testKey)
        super.tearDown()
    }

    func testSavedItemUsesAfterFirstUnlockThisDeviceOnlyAccessibility() throws {
        KeychainService.save(Data("test-session-token".utf8), forKey: testKey)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: testKey,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // Sur certains environnements CI/sandbox sans trousseau utilisable
        // (pas de groupe d'accès keychain signé), SecItemCopyMatching peut
        // échouer indépendamment du code applicatif : dans ce cas le test
        // est ignoré plutôt que faussement rouge.
        try XCTSkipUnless(status == errSecSuccess, "Trousseau indisponible dans cet environnement de test (status \(status)).")

        let attributes = result as? [String: Any]
        let accessible = attributes?[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func testLoadRoundTripsSavedData() {
        let payload = Data("round-trip-check".utf8)
        KeychainService.save(payload, forKey: testKey)
        XCTAssertEqual(KeychainService.load(forKey: testKey), payload)
    }

    func testDeleteRemovesSavedData() {
        KeychainService.save(Data("to-be-deleted".utf8), forKey: testKey)
        KeychainService.delete(forKey: testKey)
        XCTAssertNil(KeychainService.load(forKey: testKey))
    }
}
