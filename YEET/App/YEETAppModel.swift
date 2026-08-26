import Foundation
import SwiftUI

@MainActor
final class YEETAppModel: ObservableObject {
    @Published private(set) var accountState: AccountState
    @Published private(set) var leaderboardState: LeaderboardLoadState
    @Published private(set) var resultCloudState: ResultCloudState = .idle
    @Published private(set) var accountActionError: String?
    @Published private(set) var isAccountWorking = false
    @Published var isAccountPresented = false

    private let authService: (any AuthenticationServicing)?
    private let leaderboardService: (any LeaderboardServicing)?
    private var didStart = false
    private var authChangesTask: Task<Void, Never>?
    private var scoreTask: Task<Void, Never>?
    private var pendingScore: PendingScore?
    private var submittingAttemptID: UUID?
    private var leaderboardRequestID: UUID?

    convenience init(configuration: BackendConfiguration? = .load()) {
        guard let configuration else {
            self.init(authService: nil, leaderboardService: nil)
            return
        }
        let services = SupabaseServiceContainer(configuration: configuration)
        self.init(authService: services.auth, leaderboardService: services.leaderboard)
    }

    init(
        authService: (any AuthenticationServicing)?,
        leaderboardService: (any LeaderboardServicing)?
    ) {
        self.authService = authService
        self.leaderboardService = leaderboardService
        if authService == nil || leaderboardService == nil {
            accountState = .unavailable
            leaderboardState = .unavailable
        } else {
            accountState = .checking
            leaderboardState = .loading(cached: nil)
        }
    }

    deinit {
        authChangesTask?.cancel()
        scoreTask?.cancel()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        guard let authService else { return }

        authChangesTask = Task { [weak self, authService] in
            for await userID in authService.authChanges() {
                guard let self, !Task.isCancelled else { return }
                await self.applyAuthenticatedUser(userID)
            }
        }

        Task { [weak self, authService] in
            let userID = await authService.currentUserID()
            await self?.applyAuthenticatedUser(userID)
        }
    }

    func handleDetectionTransition(from oldState: YEETViewState, to newState: YEETViewState) {
        guard case let .result(result) = newState else {
            if case .result = oldState {
                resultCloudState = .idle
                pendingScore = nil
                scoreTask?.cancel()
            }
            return
        }
        guard oldState != newState else { return }

        let pending = PendingScore(attemptID: UUID(), result: result)
        pendingScore = pending
        scoreTask?.cancel()

        switch accountState {
        case .signedIn:
            scoreTask = Task { [weak self] in await self?.submitPendingScore() }
        case .unavailable:
            resultCloudState = .unavailable
        case .checking, .signedOut, .needsHandle:
            scoreTask = Task { [weak self] in await self?.estimateRank(for: pending) }
        }
    }

    func refreshLeaderboard() async {
        await refreshLeaderboard(candidateAirtimeMilliseconds: nil, marksLoading: true)
    }

    func sceneBecameActive() {
        guard didStart else { return }
        Task { [weak self] in await self?.refreshLeaderboard() }
    }

    func presentAccount() {
        accountActionError = nil
        isAccountPresented = true
    }

    func retryAccountCheck() {
        guard let authService else { return }
        accountActionError = nil
        Task { [weak self, authService] in
            let userID = await authService.currentUserID()
            await self?.applyAuthenticatedUser(userID)
        }
    }

    func completeAppleSignIn(idToken: String, rawNonce: String) async {
        guard let authService else {
            accountActionError = BackendError.unavailable.localizedDescription
            return
        }
        accountActionError = nil
        isAccountWorking = true
        defer { isAccountWorking = false }

        do {
            let userID = try await authService.signInWithApple(
                idToken: idToken,
                rawNonce: rawNonce
            )
            await applyAuthenticatedUser(userID)
        } catch {
            accountActionError = "Sign in failed. Please try again."
        }
    }

    func saveHandle(_ proposedHandle: String) async -> Bool {
        guard let leaderboardService else {
            accountActionError = BackendError.unavailable.localizedDescription
            return false
        }

        let handle = HandleValidator.normalize(proposedHandle)
        guard HandleValidator.isValid(handle) else {
            accountActionError = BackendError.invalidHandle.localizedDescription
            return false
        }

        accountActionError = nil
        isAccountWorking = true
        defer { isAccountWorking = false }

        do {
            let profile = try await leaderboardService.setHandle(handle)
            accountState = .signedIn(userID: profile.id, handle: profile.handle)
            await refreshLeaderboard(candidateAirtimeMilliseconds: nil, marksLoading: false)
            if pendingScore != nil {
                await submitPendingScore()
            }
            return true
        } catch {
            accountActionError = userMessage(for: error)
            return false
        }
    }

    func signOut() async {
        guard let authService else { return }
        accountActionError = nil
        isAccountWorking = true
        scoreTask?.cancel()
        defer { isAccountWorking = false }

        do {
            try await authService.signOut()
            accountState = .signedOut
            resultCloudState = pendingScore == nil ? .idle : .guest(rank: nil)
            leaderboardState = .loading(cached: nil)
            await refreshLeaderboard(candidateAirtimeMilliseconds: nil, marksLoading: false)
        } catch {
            accountActionError = "Couldn’t sign out. Please try again."
        }
    }

    func deleteAccount(authorizationCode: String) async -> Bool {
        guard let authService else { return false }
        accountActionError = nil
        isAccountWorking = true
        scoreTask?.cancel()
        defer { isAccountWorking = false }

        do {
            try await authService.deleteAccount(authorizationCode: authorizationCode)
            accountState = .signedOut
            pendingScore = nil
            resultCloudState = .idle
            leaderboardState = .loading(cached: nil)
            await refreshLeaderboard(candidateAirtimeMilliseconds: nil, marksLoading: false)
            isAccountPresented = false
            return true
        } catch {
            accountActionError = "Account deletion failed. Please try again."
            return false
        }
    }

    func retryScore() {
        guard pendingScore != nil else { return }
        scoreTask?.cancel()
        switch accountState {
        case .signedIn:
            scoreTask = Task { [weak self] in await self?.submitPendingScore() }
        case .signedOut, .needsHandle, .checking:
            scoreTask = Task { [weak self] in
                guard let pending = self?.pendingScore else { return }
                await self?.estimateRank(for: pending)
            }
        case .unavailable:
            resultCloudState = .unavailable
        }
    }

    private func applyAuthenticatedUser(_ userID: UUID?) async {
        guard leaderboardService != nil else {
            accountState = .unavailable
            leaderboardState = .unavailable
            return
        }

        guard let userID else {
            accountState = .signedOut
            leaderboardState = .loading(cached: nil)
            await refreshLeaderboard(candidateAirtimeMilliseconds: nil, marksLoading: false)
            return
        }

        accountState = .checking
        await refreshLeaderboard(candidateAirtimeMilliseconds: nil, marksLoading: false)
        switch leaderboardState {
        case let .loaded(snapshot):
            if let currentUser = snapshot.currentUser,
               currentUser.userID == userID {
                accountState = .signedIn(userID: userID, handle: currentUser.handle)
                if pendingScore != nil {
                    await submitPendingScore()
                }
            } else {
                accountState = .needsHandle(userID: userID)
                isAccountPresented = true
            }
        case .failed:
            accountState = .checking
            accountActionError = "Couldn’t check your profile. Please try again."
        case .unavailable, .loading:
            accountState = .checking
        }
    }

    private func estimateRank(for pending: PendingScore) async {
        guard pendingScore?.attemptID == pending.attemptID else { return }
        resultCloudState = .estimating
        await refreshLeaderboard(
            candidateAirtimeMilliseconds: pending.airtimeMilliseconds,
            marksLoading: false
        )
        guard pendingScore?.attemptID == pending.attemptID else { return }
        if case .signedIn = accountState { return }
        switch leaderboardState {
        case let .loaded(snapshot):
            resultCloudState = .guest(rank: snapshot.candidateRank)
        case .failed:
            resultCloudState = .guest(rank: nil)
        case .unavailable:
            resultCloudState = .unavailable
        case .loading:
            resultCloudState = .guest(rank: nil)
        }
    }

    private func submitPendingScore() async {
        guard
            let leaderboardService,
            let pending = pendingScore,
            case .signedIn = accountState,
            submittingAttemptID != pending.attemptID
        else { return }

        submittingAttemptID = pending.attemptID
        defer {
            if submittingAttemptID == pending.attemptID {
                submittingAttemptID = nil
            }
        }
        resultCloudState = .saving
        do {
            let result = try await leaderboardService.submit(pending)
            guard pendingScore?.attemptID == pending.attemptID,
                  case .signedIn = accountState else { return }
            pendingScore = nil
            resultCloudState = .saved(result)
            await refreshLeaderboard(candidateAirtimeMilliseconds: nil, marksLoading: false)
        } catch {
            guard pendingScore?.attemptID == pending.attemptID,
                  case .signedIn = accountState else { return }
            resultCloudState = .failed(message: userMessage(for: error))
        }
    }

    private func refreshLeaderboard(
        candidateAirtimeMilliseconds: Int?,
        marksLoading: Bool
    ) async {
        guard let leaderboardService else {
            leaderboardState = .unavailable
            return
        }

        let requestID = UUID()
        leaderboardRequestID = requestID
        let cached = leaderboardState.snapshot
        if marksLoading {
            leaderboardState = .loading(cached: cached)
        }
        do {
            let snapshot = try await leaderboardService.snapshot(
                candidateAirtimeMilliseconds: candidateAirtimeMilliseconds
            )
            guard leaderboardRequestID == requestID else { return }
            leaderboardState = .loaded(snapshot)
        } catch {
            guard leaderboardRequestID == requestID else { return }
            leaderboardState = .failed(message: userMessage(for: error), cached: cached)
        }
    }

    private func userMessage(for error: Error) -> String {
        if let backendError = error as? BackendError {
            return backendError.localizedDescription
        }
        return "Couldn’t reach the leaderboard. Please try again."
    }
}
