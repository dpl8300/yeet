import XCTest
@testable import YEET

@MainActor
final class YEETAppModelTests: XCTestCase {
    func testRestoresSignedInSessionAndProfile() async {
        let userID = UUID()
        let auth = MockAuthenticationService(currentUserID: userID)
        let leaderboard = MockLeaderboardService(currentUser: entry(userID: userID, handle: "skylar"))
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        await waitUntil { model.accountState == .signedIn(userID: userID, handle: "skylar") }

        XCTAssertEqual(model.leaderboardState.snapshot?.currentUser?.handle, "skylar")
    }

    func testHandleValidationNormalizesAndRejectsInvalidValues() {
        XCTAssertEqual(HandleValidator.normalize("  @Sky_Lar  "), "sky_lar")
        XCTAssertTrue(HandleValidator.isValid("@sky_lar"))
        XCTAssertFalse(HandleValidator.isValid("two words"))
        XCTAssertFalse(HandleValidator.isValid("ab"))
    }

    func testHandleConflictRemainsInRequiredHandleState() async {
        let userID = UUID()
        let auth = MockAuthenticationService(currentUserID: userID)
        let leaderboard = MockLeaderboardService(currentUser: nil)
        leaderboard.setHandleError = BackendError.handleTaken
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        await waitUntil { model.accountState == .needsHandle(userID: userID) }
        let didSave = await model.saveHandle("claimed")

        XCTAssertFalse(didSave)
        XCTAssertEqual(model.accountState, .needsHandle(userID: userID))
        XCTAssertEqual(model.accountActionError, BackendError.handleTaken.localizedDescription)
    }

    func testGuestResultGetsHypotheticalRank() async {
        let auth = MockAuthenticationService(currentUserID: nil)
        let leaderboard = MockLeaderboardService(currentUser: nil)
        leaderboard.candidateRank = 27
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        await waitUntil { model.accountState == .signedOut }
        model.handleDetectionTransition(from: .airborne(startTimestamp: 1), to: .result(Self.result))
        await waitUntil { model.resultCloudState == .guest(rank: 27) }

        XCTAssertEqual(leaderboard.snapshotCandidates.last, 1_420)
        XCTAssertTrue(leaderboard.submissions.isEmpty)
    }

    func testPendingGuestResultSubmitsAfterAppleSignInAndHandleCreation() async {
        let userID = UUID()
        let auth = MockAuthenticationService(currentUserID: nil)
        auth.appleSignInUserID = userID
        let leaderboard = MockLeaderboardService(currentUser: nil)
        leaderboard.setHandleProfile = profile(userID: userID, handle: "rocket")
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        await waitUntil { model.accountState == .signedOut }
        model.handleDetectionTransition(from: .airborne(startTimestamp: 1), to: .result(Self.result))
        await waitUntil {
            if case .guest = model.resultCloudState { return true }
            return false
        }

        await model.completeAppleSignIn(idToken: "apple-token", rawNonce: "nonce")
        XCTAssertEqual(model.accountState, .needsHandle(userID: userID))
        let didSave = await model.saveHandle("@Rocket")
        XCTAssertTrue(didSave)
        await waitUntil { model.resultCloudState.isSaved }

        XCTAssertEqual(leaderboard.submissions.count, 1)
        XCTAssertEqual(model.accountState, .signedIn(userID: userID, handle: "rocket"))
    }

    func testSignedInResultAutomaticallySubmitsOnlyOnce() async {
        let userID = UUID()
        let auth = MockAuthenticationService(currentUserID: userID)
        let leaderboard = MockLeaderboardService(currentUser: entry(userID: userID, handle: "orbit"))
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        await waitUntil { model.accountState == .signedIn(userID: userID, handle: "orbit") }
        model.handleDetectionTransition(from: .airborne(startTimestamp: 1), to: .result(Self.result))
        model.handleDetectionTransition(from: .result(Self.result), to: .result(Self.result))
        await waitUntil { model.resultCloudState.isSaved }

        XCTAssertEqual(leaderboard.submissions.count, 1)
    }

    func testResultWaitsForSignedInSessionRestorationInsteadOfBecomingGuest() async {
        let userID = UUID()
        let auth = MockAuthenticationService(currentUserID: userID)
        let leaderboard = MockLeaderboardService(
            currentUser: entry(userID: userID, handle: "restored")
        )
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        model.handleDetectionTransition(
            from: .airborne(startTimestamp: 1),
            to: .result(Self.result)
        )

        XCTAssertEqual(model.resultCloudState, .checkingAccount)
        await waitUntil { model.resultCloudState.isSaved }
        XCTAssertEqual(model.accountState, .signedIn(userID: userID, handle: "restored"))
        XCTAssertEqual(leaderboard.submissions.count, 1)
        XCTAssertFalse(
            leaderboard.snapshotCandidates.contains(where: { $0 != nil }),
            "A restoring signed-in session must not launch a guest candidate request"
        )
    }

    func testFailedSaveRetriesWithSameIdempotencyID() async {
        let userID = UUID()
        let auth = MockAuthenticationService(currentUserID: userID)
        let leaderboard = MockLeaderboardService(currentUser: entry(userID: userID, handle: "retry"))
        leaderboard.submitFailureCount = 1
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        await waitUntil { model.accountState == .signedIn(userID: userID, handle: "retry") }
        model.handleDetectionTransition(from: .airborne(startTimestamp: 1), to: .result(Self.result))
        await waitUntil {
            if case .failed = model.resultCloudState { return true }
            return false
        }
        model.retryScore()
        await waitUntil { model.resultCloudState.isSaved }

        XCTAssertEqual(leaderboard.submissions.count, 2)
        XCTAssertEqual(leaderboard.submissions[0].attemptID, leaderboard.submissions[1].attemptID)
    }

    func testSignOutAndDeletionClearAccountState() async {
        let userID = UUID()
        let auth = MockAuthenticationService(currentUserID: userID)
        let leaderboard = MockLeaderboardService(currentUser: entry(userID: userID, handle: "cleanup"))
        let model = YEETAppModel(authService: auth, leaderboardService: leaderboard)

        model.start()
        await waitUntil { model.accountState == .signedIn(userID: userID, handle: "cleanup") }
        await model.signOut()
        XCTAssertEqual(model.accountState, .signedOut)
        XCTAssertEqual(auth.signOutCallCount, 1)

        auth.currentUser = userID
        auth.emit(userID)
        await waitUntil { model.accountState == .signedIn(userID: userID, handle: "cleanup") }
        model.handleDetectionTransition(from: .airborne(startTimestamp: 1), to: .result(Self.result))
        let deleted = await model.deleteAccount(authorizationCode: "fresh-code")

        XCTAssertTrue(deleted)
        XCTAssertEqual(auth.deletedAuthorizationCodes, ["fresh-code"])
        XCTAssertEqual(model.accountState, .signedOut)
        XCTAssertEqual(model.resultCloudState, .idle)
        XCTAssertFalse(model.isAccountPresented)
    }

    private static let result = DetectionResult(
        airborneStartTimestamp: 1,
        landingTimestamp: 2.42,
        airtime: 1.42,
        preflightPeakAcceleration: 1.8,
        impactPeakAcceleration: 2.4,
        airborneSampleCount: 142
    )

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Timed out waiting for app state")
    }

    private func entry(userID: UUID, handle: String) -> LeaderboardEntry {
        LeaderboardEntry(
            userID: userID,
            handle: handle,
            rank: 4,
            airtimeMilliseconds: 1_420,
            achievedAt: "2026-08-25T12:00:00Z"
        )
    }

    private func profile(userID: UUID, handle: String) -> Profile {
        Profile(
            id: userID,
            handle: handle,
            createdAt: "2026-08-25T12:00:00Z",
            updatedAt: "2026-08-25T12:00:00Z"
        )
    }
}

private extension ResultCloudState {
    var isSaved: Bool {
        if case .saved = self { return true }
        return false
    }
}

private final class MockAuthenticationService: AuthenticationServicing, @unchecked Sendable {
    var currentUser: UUID?
    var appleSignInUserID: UUID?
    private(set) var signOutCallCount = 0
    private(set) var deletedAuthorizationCodes: [String] = []
    private var continuation: AsyncStream<UUID?>.Continuation?

    init(currentUserID: UUID?) {
        currentUser = currentUserID
    }

    func currentUserID() async -> UUID? { currentUser }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> UUID {
        guard let appleSignInUserID else { throw BackendError.invalidAppleCredential }
        currentUser = appleSignInUserID
        return appleSignInUserID
    }

    func signOut() async throws {
        signOutCallCount += 1
        currentUser = nil
    }

    func deleteAccount(authorizationCode: String) async throws {
        deletedAuthorizationCodes.append(authorizationCode)
        currentUser = nil
    }

    func authChanges() -> AsyncStream<UUID?> {
        AsyncStream { continuation in self.continuation = continuation }
    }

    func emit(_ userID: UUID?) {
        currentUser = userID
        continuation?.yield(userID)
    }
}

private final class MockLeaderboardService: LeaderboardServicing, @unchecked Sendable {
    static let savedResult = ScoreSubmissionResult(
        attemptID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        personalBestMilliseconds: 1_420,
        rank: 4,
        isPersonalBest: true,
        alreadyProcessed: false
    )

    var currentUser: LeaderboardEntry?
    var candidateRank: Int?
    var setHandleProfile: Profile?
    var setHandleError: Error?
    var submitFailureCount = 0
    private(set) var snapshotCandidates: [Int?] = []
    private(set) var submissions: [PendingScore] = []

    init(currentUser: LeaderboardEntry?) {
        self.currentUser = currentUser
    }

    func snapshot(candidateAirtimeMilliseconds: Int?) async throws -> LeaderboardSnapshot {
        snapshotCandidates.append(candidateAirtimeMilliseconds)
        return LeaderboardSnapshot(
            leaders: currentUser.map { [$0] } ?? [],
            currentUser: currentUser,
            candidateRank: candidateAirtimeMilliseconds == nil ? nil : candidateRank,
            totalPlayers: currentUser == nil ? 0 : 1
        )
    }

    func setHandle(_ handle: String) async throws -> Profile {
        if let setHandleError { throw setHandleError }
        guard let setHandleProfile else { throw BackendError.message("Missing test profile") }
        return setHandleProfile
    }

    func submit(_ pendingScore: PendingScore) async throws -> ScoreSubmissionResult {
        submissions.append(pendingScore)
        if submitFailureCount > 0 {
            submitFailureCount -= 1
            throw BackendError.message("Offline")
        }
        return ScoreSubmissionResult(
            attemptID: pendingScore.attemptID,
            personalBestMilliseconds: Self.savedResult.personalBestMilliseconds,
            rank: Self.savedResult.rank,
            isPersonalBest: Self.savedResult.isPersonalBest,
            alreadyProcessed: submissions.count > 1
        )
    }
}
