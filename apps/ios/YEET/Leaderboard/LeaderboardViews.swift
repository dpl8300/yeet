import Foundation
import SwiftUI

struct EmbeddedLeaderboardView: View {
    let state: LeaderboardLoadState
    let accountState: AccountState
    var maximumLeaderCount = 10
    var isCompact = false
    let onSignIn: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Text("GLOBAL LEADERBOARD")
                    .font(.system(size: isCompact ? 18 : 20, weight: .black))
                    .tracking(0.9)
                    .foregroundStyle(YEETTheme.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                if case .loading = state {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small).tint(YEETTheme.ink)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            content
        }
        .padding(.bottom, 2)
        .accessibilityIdentifier("yeet.leaderboard")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .unavailable:
            LeaderboardMessage(
                title: "LEADERBOARD UNAVAILABLE",
                detail: "Add Supabase configuration to connect."
            )

        case let .loading(cached):
            if let cached {
                leaderboard(snapshot: cached, isStale: false)
            } else {
                LeaderboardSkeleton()
            }

        case let .loaded(snapshot):
            leaderboard(snapshot: snapshot, isStale: false)

        case let .failed(message, cached):
            if let cached {
                leaderboard(snapshot: cached, isStale: true)
                compactRetry(message)
            } else {
                LeaderboardMessage(title: "COULDN’T LOAD RANKINGS", detail: message)
                compactRetry(nil)
            }
        }
    }

    @ViewBuilder
    private func leaderboard(snapshot: LeaderboardSnapshot, isStale: Bool) -> some View {
        let displayedLeaders = Array(snapshot.leaders.prefix(maximumLeaderCount))
        VStack(spacing: 2) {
            if snapshot.leaders.isEmpty {
                LeaderboardMessage(
                    title: "BE THE FIRST TO RANK",
                    detail: "Complete a valid YEET and save your score."
                )
            } else {
                ForEach(displayedLeaders) { entry in
                    LeaderboardRow(
                        entry: entry,
                        isHighlighted: entry.userID == snapshot.currentUser?.userID,
                        isCompact: isCompact
                    )
                }
            }

            if let currentUser = snapshot.currentUser,
               !displayedLeaders.contains(where: { $0.userID == currentUser.userID }) {
                LeaderboardRow(entry: currentUser, isHighlighted: true, isCompact: isCompact)
            } else if case .signedOut = accountState {
                Button(action: onSignIn) {
                    HStack {
                        Text("YOUR RANK")
                        Spacer()
                        Text("SIGN IN TO SAVE")
                    }
                    .font(.system(size: isCompact ? 14 : 15, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .foregroundStyle(YEETTheme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: isCompact ? 46 : 50)
                    .background(YEETTheme.yellow, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("yeet.account.signInFromLeaderboard")
            }

            if isStale {
                Text("Showing saved rankings")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(YEETTheme.muted)
            }
        }
    }

    private func compactRetry(_ message: String?) -> some View {
        Button(action: onRetry) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.clockwise")
                Text(message == nil ? "RETRY" : "OFFLINE · RETRY")
            }
            .font(.caption2.weight(.black))
            .foregroundStyle(YEETTheme.muted)
        }
        .buttonStyle(.plain)
        .accessibilityHint(message ?? "Reload the leaderboard")
    }
}

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let isHighlighted: Bool
    var isCompact = false

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.rank.map { "#\($0.formatted())" } ?? "—")
                .font(.system(size: isCompact ? 14 : 15, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(width: 42, alignment: .leading)

            Text("@\(entry.handle)")
                .font(
                    isCompact
                        ? .system(size: 15, weight: isHighlighted ? .black : .semibold)
                        : .system(size: 16, weight: isHighlighted ? .black : .semibold)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(entry.airtimeMilliseconds.map(LeaderboardFormat.airtime) ?? "—")
                .font(.system(size: isCompact ? 15 : 16, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
        .foregroundStyle(YEETTheme.ink)
        .padding(.horizontal, 12)
        .frame(height: isCompact ? 42 : 46)
        .background(
            isHighlighted ? YEETTheme.yellow : YEETTheme.paper,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(YEETTheme.ink.opacity(0.22), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rank \(entry.rank?.formatted() ?? "unranked"), \(entry.handle), "
                + (entry.airtimeMilliseconds.map(LeaderboardFormat.airtime) ?? "no score")
        )
    }
}

private struct LeaderboardMessage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.black))
                .fontWidth(.compressed)
            Text(detail)
                .font(.caption)
                .foregroundStyle(YEETTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(YEETTheme.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LeaderboardSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(YEETTheme.ink.opacity(0.06))
                    .frame(height: 42)
            }
        }
        .accessibilityLabel("Loading leaderboard")
    }
}

struct ResultLeaderboardPrompt: View {
    let state: ResultCloudState
    let onSignIn: () -> Void
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checkingAccount:
            statusPanel(title: "CHECKING YOUR ACCOUNT…", detail: nil, showsProgress: true)
        case .estimating:
            statusPanel(title: "CHECKING YOUR RANK…", detail: nil, showsProgress: true)
        case let .guest(rank):
            VStack(spacing: 10) {
                statusPanel(
                    title: rank.map { "YOU’D RANK #\($0.formatted())" } ?? "SAVE YOUR SCORE",
                    detail: "Sign in to claim this YEET.",
                    showsProgress: false
                )
                Button("SIGN IN TO SAVE", action: onSignIn)
                    .font(.caption.weight(.black))
                    .foregroundStyle(YEETTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(YEETTheme.yellow, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yeet.result.signInToSave")
            }
        case let .needsHandle(rank):
            VStack(spacing: 10) {
                statusPanel(
                    title: rank.map { "YOU’D RANK #\($0.formatted())" } ?? "PROFILE REQUIRED",
                    detail: "Choose a handle to save this YEET.",
                    showsProgress: false
                )
                Button("CHOOSE HANDLE", action: onSignIn)
                    .font(.caption.weight(.black))
                    .foregroundStyle(YEETTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(YEETTheme.yellow, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yeet.result.chooseHandle")
            }
        case .saving:
            statusPanel(title: "SAVING SCORE…", detail: nil, showsProgress: true)
        case let .saved(result):
            statusPanel(
                title: result.isPersonalBest ? "NEW PB · #\(result.rank.formatted())" : "SAVED · #\(result.rank.formatted())",
                detail: LeaderboardFormat.airtime(result.personalBestMilliseconds) + " personal best",
                showsProgress: false
            )
        case let .failed(message):
            VStack(spacing: 8) {
                statusPanel(title: "SCORE NOT SAVED", detail: message, showsProgress: false)
                Button("RETRY SAVE", action: onRetry)
                    .font(.caption.weight(.black))
                    .buttonStyle(.plain)
            }
        case .unavailable:
            statusPanel(
                title: "LEADERBOARD UNAVAILABLE",
                detail: "Your YEET still works without it.",
                showsProgress: false
            )
        }
    }

    private func statusPanel(title: String, detail: String?, showsProgress: Bool) -> some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView().controlSize(.small).tint(YEETTheme.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.black))
                    .fontWidth(.compressed)
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(YEETTheme.muted)
                }
            }
            Spacer()
        }
        .foregroundStyle(YEETTheme.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(YEETTheme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

enum LeaderboardFormat {
    static func airtime(_ milliseconds: Int) -> String {
        let seconds = Double(milliseconds) / 1_000
        return seconds.formatted(.number.precision(.fractionLength(3))) + "s"
    }

    static func rank(_ rank: Int) -> String {
        "#" + rank.formatted()
    }

    static func heroAirtime(_ milliseconds: Int) -> String {
        let seconds = Double(milliseconds) / 1_000
        return seconds.formatted(.number.precision(.fractionLength(2))) + "s"
    }
}

#if DEBUG
private enum LeaderboardPreviewFixtures {
    static let leaders = [
        entry(1, "moonshot", 2_140),
        entry(2, "orbit", 1_980),
        entry(3, "skylar", 1_810),
        entry(4, "launchpad", 1_720),
        entry(5, "gravitywho", 1_640)
    ]
    static let belowTopFive = entry(42, "yeeter", 1_420)

    static let topFivePlayer = LeaderboardSnapshot(
        leaders: leaders,
        currentUser: leaders[1],
        candidateRank: nil,
        totalPlayers: 2_000
    )

    static let rankedBelowTopFive = LeaderboardSnapshot(
        leaders: leaders,
        currentUser: belowTopFive,
        candidateRank: nil,
        totalPlayers: 2_000
    )

    private static func entry(_ rank: Int, _ handle: String, _ airtime: Int) -> LeaderboardEntry {
        LeaderboardEntry(
            userID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
            handle: handle,
            rank: rank,
            airtimeMilliseconds: airtime,
            achievedAt: "2026-08-25T12:00:00Z"
        )
    }
}

#Preview("Leaderboard · Loading") {
    EmbeddedLeaderboardView(
        state: .loading(cached: nil),
        accountState: .signedOut,
        onSignIn: {},
        onRetry: {}
    )
    .padding(24)
}

#Preview("Leaderboard · Empty") {
    EmbeddedLeaderboardView(
        state: .loaded(.empty),
        accountState: .signedOut,
        onSignIn: {},
        onRetry: {}
    )
    .padding(24)
}

#Preview("Leaderboard · Ranked below top five") {
    EmbeddedLeaderboardView(
        state: .loaded(LeaderboardPreviewFixtures.rankedBelowTopFive),
        accountState: .signedIn(
            userID: LeaderboardPreviewFixtures.belowTopFive.userID,
            handle: LeaderboardPreviewFixtures.belowTopFive.handle
        ),
        onSignIn: {},
        onRetry: {}
    )
    .padding(24)
}

#Preview("Leaderboard · Player in top five") {
    EmbeddedLeaderboardView(
        state: .loaded(LeaderboardPreviewFixtures.topFivePlayer),
        accountState: .signedIn(
            userID: LeaderboardPreviewFixtures.leaders[1].userID,
            handle: LeaderboardPreviewFixtures.leaders[1].handle
        ),
        onSignIn: {},
        onRetry: {}
    )
    .padding(24)
}

#Preview("Leaderboard · Offline") {
    EmbeddedLeaderboardView(
        state: .failed(
            message: "No internet connection.",
            cached: LeaderboardPreviewFixtures.rankedBelowTopFive
        ),
        accountState: .signedIn(
            userID: LeaderboardPreviewFixtures.belowTopFive.userID,
            handle: LeaderboardPreviewFixtures.belowTopFive.handle
        ),
        onSignIn: {},
        onRetry: {}
    )
    .padding(24)
}

#Preview("Result · Guest candidate") {
    ResultLeaderboardPrompt(state: .guest(rank: 56), onSignIn: {}, onRetry: {})
        .padding(24)
}

#Preview("Result · Submission error") {
    ResultLeaderboardPrompt(
        state: .failed(message: "Couldn’t reach the leaderboard."),
        onSignIn: {},
        onRetry: {}
    )
    .padding(24)
}
#endif
