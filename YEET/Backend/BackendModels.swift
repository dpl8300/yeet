import Foundation

struct Profile: Codable, Equatable, Sendable {
    let id: UUID
    let handle: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LeaderboardEntry: Codable, Equatable, Identifiable, Sendable {
    let userID: UUID
    let handle: String
    let rank: Int?
    let airtimeMilliseconds: Int?
    let achievedAt: String?

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case handle
        case rank
        case airtimeMilliseconds = "airtime_ms"
        case achievedAt = "achieved_at"
    }
}

struct LeaderboardSnapshot: Codable, Equatable, Sendable {
    let leaders: [LeaderboardEntry]
    let currentUser: LeaderboardEntry?
    let candidateRank: Int?
    let totalPlayers: Int

    static let empty = LeaderboardSnapshot(
        leaders: [],
        currentUser: nil,
        candidateRank: nil,
        totalPlayers: 0
    )

    enum CodingKeys: String, CodingKey {
        case leaders
        case currentUser = "current_user"
        case candidateRank = "candidate_rank"
        case totalPlayers = "total_players"
    }
}

struct ScoreSubmissionResult: Codable, Equatable, Sendable {
    let attemptID: UUID
    let personalBestMilliseconds: Int
    let rank: Int
    let isPersonalBest: Bool
    let alreadyProcessed: Bool

    enum CodingKeys: String, CodingKey {
        case attemptID = "attempt_id"
        case personalBestMilliseconds = "personal_best_ms"
        case rank
        case isPersonalBest = "is_personal_best"
        case alreadyProcessed = "already_processed"
    }
}

struct PendingScore: Equatable, Sendable {
    let attemptID: UUID
    let result: DetectionResult

    var airtimeMilliseconds: Int {
        Int((result.airtime * 1_000).rounded())
    }
}

enum AccountState: Equatable, Sendable {
    case unavailable
    case checking
    case signedOut
    case needsHandle(userID: UUID)
    case signedIn(userID: UUID, handle: String)

    var handle: String? {
        guard case let .signedIn(_, handle) = self else { return nil }
        return handle
    }

    var isSignedIn: Bool {
        switch self {
        case .needsHandle, .signedIn: true
        default: false
        }
    }
}

enum LeaderboardLoadState: Equatable, Sendable {
    case unavailable
    case loading(cached: LeaderboardSnapshot?)
    case loaded(LeaderboardSnapshot)
    case failed(message: String, cached: LeaderboardSnapshot?)

    var snapshot: LeaderboardSnapshot? {
        switch self {
        case let .loading(cached), let .failed(_, cached): cached
        case let .loaded(snapshot): snapshot
        case .unavailable: nil
        }
    }
}

enum ResultCloudState: Equatable, Sendable {
    case idle
    case estimating
    case guest(rank: Int?)
    case saving
    case saved(ScoreSubmissionResult)
    case failed(message: String)
    case unavailable
}

enum BackendError: LocalizedError, Equatable, Sendable {
    case unavailable
    case invalidAppleCredential
    case invalidHandle
    case handleTaken
    case profileRequired
    case rateLimited
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Leaderboard unavailable."
        case .invalidAppleCredential:
            "Apple couldn’t provide a valid credential. Please try again."
        case .invalidHandle:
            "Use 3–20 lowercase letters, numbers, or underscores."
        case .handleTaken:
            "That handle is already taken."
        case .profileRequired:
            "Choose a handle before saving a score."
        case .rateLimited:
            "That was too fast. Wait a moment and try again."
        case let .message(message):
            message
        }
    }
}

enum HandleValidator {
    static func normalize(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("@") {
            normalized.removeFirst()
        }
        return normalized
    }

    static func isValid(_ value: String) -> Bool {
        let normalized = normalize(value)
        return normalized.range(
            of: "^[a-z0-9_]{3,20}$",
            options: .regularExpression
        ) != nil
    }
}
