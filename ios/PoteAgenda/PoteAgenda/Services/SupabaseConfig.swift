import Foundation

struct SupabaseConfig {
    let url: URL
    let publishableKey: String

    static func load() throws -> SupabaseConfig {
        let plistURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist")
            ?? Bundle.main.url(forResource: "Supabase", withExtension: "plist", subdirectory: "Resources")
        guard let plistURL else {
            throw AppError.message("Ajoute PoteAgenda/Resources/Supabase.plist avec les cles Supabase.")
        }
        let data = try Data(contentsOf: plistURL)
        guard
            let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String],
            let rawURL = dictionary["SUPABASE_URL"],
            let url = URL(string: rawURL),
            let key = dictionary["SUPABASE_PUBLISHABLE_KEY"],
            !key.isEmpty
        else {
            throw AppError.message("Supabase.plist est invalide.")
        }
        return SupabaseConfig(url: url, publishableKey: key)
    }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
