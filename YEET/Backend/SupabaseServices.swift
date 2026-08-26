import Foundation
import Supabase

protocol AuthenticationServicing: Sendable {
    func currentUserID() async -> UUID?
    func signInWithApple(idToken: String, rawNonce: String) async throws -> UUID
    func signOut() async throws
    func deleteAccount(authorizationCode: String) async throws
    func authChanges() -> AsyncStream<UUID?>
}

protocol LeaderboardServicing: Sendable {
    func snapshot(candidateAirtimeMilliseconds: Int?) async throws -> LeaderboardSnapshot
    func setHandle(_ handle: String) async throws -> Profile
    func submit(_ pendingScore: PendingScore) async throws -> ScoreSubmissionResult
}

final class SupabaseServiceContainer: @unchecked Sendable {
    let auth: any AuthenticationServicing
    let leaderboard: any LeaderboardServicing

    init(configuration: BackendConfiguration) {
        let client = SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey
        )
        auth = SupabaseAuthenticationService(client: client)
        leaderboard = SupabaseLeaderboardService(client: client)
    }
}

private final class SupabaseAuthenticationService: AuthenticationServicing, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentUserID() async -> UUID? {
        try? await client.auth.session.user.id
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )
        return session.user.id
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
    }

    func deleteAccount(authorizationCode: String) async throws {
        struct Body: Encodable {
            let authorizationCode: String

            enum CodingKeys: String, CodingKey {
                case authorizationCode = "authorization_code"
            }
        }
        _ = try await client.functions.invoke(
            "delete-account",
            options: .init(body: Body(authorizationCode: authorizationCode))
        )
        try? await client.auth.signOut(scope: .local)
    }

    func authChanges() -> AsyncStream<UUID?> {
        AsyncStream { continuation in
            let task = Task { [client] in
                for await (_, session) in client.auth.authStateChanges {
                    guard !Task.isCancelled else { break }
                    continuation.yield(session?.user.id)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class SupabaseLeaderboardService: LeaderboardServicing, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func snapshot(candidateAirtimeMilliseconds: Int?) async throws -> LeaderboardSnapshot {
        struct Parameters: Encodable {
            let pCandidateAirtimeMs: Int?

            enum CodingKeys: String, CodingKey {
                case pCandidateAirtimeMs = "p_candidate_airtime_ms"
            }
        }

        do {
            let value: LeaderboardSnapshot = try await client
                .rpc(
                    "leaderboard_snapshot",
                    params: Parameters(pCandidateAirtimeMs: candidateAirtimeMilliseconds)
                )
                .execute()
                .value
            return value
        } catch {
            throw map(error)
        }
    }

    func setHandle(_ handle: String) async throws -> Profile {
        struct Parameters: Encodable {
            let pHandle: String

            enum CodingKeys: String, CodingKey { case pHandle = "p_handle" }
        }

        do {
            let value: Profile = try await client
                .rpc("set_profile_handle", params: Parameters(pHandle: handle))
                .execute()
                .value
            return value
        } catch {
            throw map(error)
        }
    }

    func submit(_ pendingScore: PendingScore) async throws -> ScoreSubmissionResult {
        struct Parameters: Encodable {
            let pClientAttemptID: UUID
            let pAirtimeMs: Int
            let pPreflightPeakG: Double
            let pImpactPeakG: Double
            let pAirborneSampleCount: Int

            enum CodingKeys: String, CodingKey {
                case pClientAttemptID = "p_client_attempt_id"
                case pAirtimeMs = "p_airtime_ms"
                case pPreflightPeakG = "p_preflight_peak_g"
                case pImpactPeakG = "p_impact_peak_g"
                case pAirborneSampleCount = "p_airborne_sample_count"
            }
        }

        let result = pendingScore.result
        let parameters = Parameters(
            pClientAttemptID: pendingScore.attemptID,
            pAirtimeMs: pendingScore.airtimeMilliseconds,
            pPreflightPeakG: result.preflightPeakAcceleration,
            pImpactPeakG: result.impactPeakAcceleration,
            pAirborneSampleCount: result.airborneSampleCount
        )

        do {
            let value: ScoreSubmissionResult = try await client
                .rpc("submit_attempt", params: parameters)
                .execute()
                .value
            return value
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> BackendError {
        let description = error.localizedDescription.lowercased()
        if description.contains("handle_taken") || description.contains("23505") {
            return .handleTaken
        }
        if description.contains("invalid_handle") {
            return .invalidHandle
        }
        if description.contains("profile_required") {
            return .profileRequired
        }
        if description.contains("submission_rate_limited") {
            return .rateLimited
        }
        return .message("Couldn’t reach the leaderboard. Please try again.")
    }
}
