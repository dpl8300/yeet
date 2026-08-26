import Foundation

struct BackendConfiguration: Equatable, Sendable {
    let projectURL: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) -> BackendConfiguration? {
        guard
            let projectRef = bundle.object(forInfoDictionaryKey: "YEETSupabaseProjectRef") as? String,
            let publishableKey = bundle.object(
                forInfoDictionaryKey: "YEETSupabasePublishableKey"
            ) as? String
        else {
            return nil
        }

        let trimmedRef = projectRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedRef.isEmpty,
            !trimmedKey.isEmpty,
            trimmedKey.hasPrefix("sb_publishable_"),
            let projectURL = URL(string: "https://\(trimmedRef).supabase.co")
        else {
            return nil
        }

        return BackendConfiguration(projectURL: projectURL, publishableKey: trimmedKey)
    }
}
