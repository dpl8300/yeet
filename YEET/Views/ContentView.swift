import AVFoundation
import AVKit
import CoreHaptics
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("yeet.onboarding.completed") private var hasCompletedOnboarding = false
    @StateObject private var hapticPlayer = YEETHapticPlayer()
    @StateObject private var viewModel = YEETViewModel()
    @StateObject private var appModel = YEETAppModel()
    @State private var replayPresentation: POVReplayPresentation?
    @State private var phase: YEETExperiencePhase = .home
    @State private var attempt: AttemptPresentation?
    @State private var catchTask: Task<Void, Never>?
    @State private var rankTask: Task<Void, Never>?
    @State private var celebratedAttemptID: UUID?

    var body: some View {
        ZStack {
            experience
        }
        .onChange(of: viewModel.state) { oldState, newState in
            handleDetectionTransition(from: oldState, to: newState)
        }
        .onChange(of: appModel.resultCloudState) { _, newState in
            handleCloudTransition(newState)
        }
        .onChange(of: viewModel.povState) { _, newState in
            if case let .available(url) = newState {
                attempt?.povURL = url
            } else if newState != .finalizing {
                attempt?.povURL = nil
            }
        }
#if DEBUG
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let snapshot = viewModel.debugSnapshot {
                DebugPanel(snapshot: snapshot)
                    .padding(.horizontal, YEETTheme.pagePadding)
                    .padding(.bottom, 8)
            }
        }
#endif
        .preferredColorScheme(.light)
        .fullScreenCover(item: $replayPresentation) { replay in
            POVReplayView(url: replay.url, context: replay.context) {
                replayPresentation = nil
            }
        }
        .sheet(isPresented: $appModel.isAccountPresented) {
            AccountSheet(appModel: appModel) {
                appModel.isAccountPresented = false
                phase = .tutorial
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: povAlertBinding) { alert in
            if alert.offersSettings {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .cancel(),
                    secondaryButton: .default(Text("Open Settings")) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        openURL(url)
                    }
                )
            }

            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            appModel.start()
            viewModel.restorePOVPreference()
            hapticPlayer.prepare()
            if !hasCompletedOnboarding {
                phase = .tutorial
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
            if newPhase == .active {
                appModel.sceneBecameActive()
                viewModel.restorePOVPreference()
                hapticPlayer.prepare()
            } else {
                hapticPlayer.stop()
            }
        }
        .onDisappear {
            catchTask?.cancel()
            rankTask?.cancel()
            viewModel.cleanUp()
        }
    }

    @ViewBuilder
    private var experience: some View {
        switch phase {
        case .tutorial:
            TutorialView {
                hasCompletedOnboarding = true
                phase = .home
            }

        case .home:
            IdleView(
                isPOVEnabled: viewModel.isPOVEnabled,
                povState: viewModel.povState,
                leaderboardState: appModel.leaderboardState,
                accountState: appModel.accountState,
                onStart: startFromHome,
                onPOVChange: viewModel.setPOVEnabled,
                onOpenAccount: appModel.presentAccount,
                onRefreshLeaderboard: appModel.refreshLeaderboard,
                isEnabled: viewModel.canStart
            )

        case .measuring:
            YEETScreen(
                state: viewModel.state,
                isPOVRecording: viewModel.isPOVRecording
            )

        case .catching:
            if let attempt {
                CatchView(result: attempt.result, showsConfetti: !reduceMotion)
            }

        case .rankUp:
            if let attempt, case let .saved(saved) = appModel.resultCloudState {
                RankUpView(
                    previousRank: attempt.previousRank,
                    newRank: saved.rank,
                    showsMotion: !reduceMotion
                )
            }

        case let .result(kind):
            if let attempt {
                ResultView(
                    kind: kind,
                    presentation: attempt,
                    povState: viewModel.povState,
                    onStartAgain: startAgain,
                    onViewLeaderboard: showHome,
                    onViewPOV: presentPOV,
                    onOpenAccount: appModel.presentAccount,
                    onRetryScore: appModel.retryScore,
                    isEnabled: viewModel.canStartAgain
                )
            }

        case .invalid:
            InvalidView(onStartAgain: startAgain, isEnabled: viewModel.canStartAgain)
        }
    }

    private func startFromHome() {
        guard viewModel.canStart else { return }
        attempt = nil
        celebratedAttemptID = nil
        phase = .measuring
        viewModel.start()
    }

    private func startAgain() {
        guard viewModel.canStartAgain else { return }
        catchTask?.cancel()
        rankTask?.cancel()
        attempt = nil
        celebratedAttemptID = nil
        phase = .measuring
        viewModel.startAgain()
    }

    private func showHome() {
        catchTask?.cancel()
        rankTask?.cancel()
        viewModel.releaseAttemptPOV()
        attempt = nil
        phase = .home
        Task { await appModel.refreshLeaderboard() }
    }

    private func presentPOV(_ url: URL) {
        guard let attempt else { return }
        replayPresentation = POVReplayPresentation(
            url: url,
            context: ShareVideoContext(
                result: attempt.result,
                rank: attempt.newRank,
                candidateRank: attempt.candidateRank
            )
        )
    }

    private func handleDetectionTransition(from oldState: YEETViewState, to newState: YEETViewState) {
        if case let .result(result) = newState, oldState != newState {
            let currentUser = appModel.leaderboardState.snapshot?.currentUser
            attempt = AttemptPresentation(
                result: result,
                previousPersonalBestMilliseconds: currentUser?.airtimeMilliseconds,
                previousRank: currentUser?.rank,
                saveStatus: .idle,
                povURL: viewModel.povVideoURL
            )
            appModel.handleDetectionTransition(from: oldState, to: newState)
            attempt?.saveStatus = appModel.resultCloudState
            phase = .catching
            hapticPlayer.play(.catchSuccess)
            catchTask?.cancel()
            catchTask = Task {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.8 : 1.5))
                guard !Task.isCancelled else { return }
                advanceAfterCatch()
            }
            return
        }

        appModel.handleDetectionTransition(from: oldState, to: newState)
        switch newState {
        case .countdown, .waiting, .airborne:
            phase = .measuring
        case .invalid:
            phase = .invalid
        case .idle:
            if phase == .measuring { phase = .home }
        case .result:
            break
        }
    }

    private func handleCloudTransition(_ cloudState: ResultCloudState) {
        attempt?.saveStatus = cloudState
        guard case let .saved(saved) = cloudState, saved.isPersonalBest else { return }
        guard phase != .catching else { return }
        appModel.isAccountPresented = false
        beginRankUp(saved)
    }

    private func advanceAfterCatch() {
        if case let .saved(saved) = appModel.resultCloudState, saved.isPersonalBest {
            beginRankUp(saved)
        } else {
            phase = .result(.normal)
        }
    }

    private func beginRankUp(_ saved: ScoreSubmissionResult) {
        guard celebratedAttemptID != saved.attemptID else { return }
        celebratedAttemptID = saved.attemptID
        phase = .rankUp
        hapticPlayer.play(.rankUp)
        rankTask?.cancel()
        rankTask = Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.2 : 3.0))
            guard !Task.isCancelled else { return }
            if saved.rank == 1 {
                phase = .result(.worldRecord)
                hapticPlayer.play(.worldRecord)
            } else {
                phase = .result(.personalBest)
                hapticPlayer.play(.personalBest)
            }
        }
    }

    private var povAlertBinding: Binding<POVAlert?> {
        Binding(
            get: { viewModel.povAlert },
            set: { newValue in
                if newValue == nil {
                    viewModel.dismissPOVAlert()
                }
            }
        )
    }
}

private struct POVReplayPresentation: Identifiable {
    let id = UUID()
    let url: URL
    let context: ShareVideoContext
}

private struct AttemptPresentation: Equatable {
    let result: DetectionResult
    let previousPersonalBestMilliseconds: Int?
    let previousRank: Int?
    var saveStatus: ResultCloudState
    var povURL: URL?

    var newPersonalBestMilliseconds: Int? {
        guard case let .saved(saved) = saveStatus else { return nil }
        return saved.personalBestMilliseconds
    }

    var newRank: Int? { saveStatus.authoritativeRank }
    var candidateRank: Int? { saveStatus.candidateRank }
    var isWorldRecord: Bool { newRank == 1 }
}

private enum YEETExperiencePhase: Equatable {
    case tutorial
    case home
    case measuring
    case catching
    case rankUp
    case result(YEETResultKind)
    case invalid
}

private enum YEETResultKind: Equatable {
    case normal
    case personalBest
    case worldRecord
}

struct YEETScreen: View {
    let state: YEETViewState
    var isPOVRecording = false

    var body: some View {
        switch state {
        case let .countdown(step):
            CountdownView(step: step)

        case .waiting:
            WaitingView()

        case let .airborne(startTimestamp):
            AirborneView(startTimestamp: startTimestamp, isRecording: isPOVRecording)

        case .idle, .result, .invalid:
            Color.white.ignoresSafeArea()
        }
    }
}

enum YEETHapticCue: Int, CaseIterable, Equatable, Sendable {
    case catchSuccess
    case rankUp
    case personalBest
    case worldRecord

    var intensity: Double {
        switch self {
        case .catchSuccess: 0.72
        case .rankUp: 0.82
        case .personalBest: 0.92
        case .worldRecord: 1.0
        }
    }

    var duration: TimeInterval {
        switch self {
        case .catchSuccess: 0.22
        case .rankUp: 0.38
        case .personalBest: 0.48
        case .worldRecord: 0.62
        }
    }

    var sharpness: Double {
        switch self {
        case .catchSuccess: 0.55
        case .rankUp: 0.72
        case .personalBest: 0.82
        case .worldRecord: 0.95
        }
    }
}

@MainActor
private final class YEETHapticPlayer: ObservableObject {
    private var engine: CHHapticEngine?
    private var activePlayers: [any CHHapticPatternPlayer] = []

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try engine ?? CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.engine = nil
                    self?.prepare()
                }
            }
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.engine = nil
                    self?.activePlayers.removeAll()
                }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    func play(_ cue: YEETHapticCue) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            playFallback(cue)
            return
        }

        prepare()
        guard let engine else {
            playFallback(cue)
            return
        }

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(
                    parameterID: .hapticIntensity,
                    value: Float(cue.intensity)
                ),
                CHHapticEventParameter(
                    parameterID: .hapticSharpness,
                    value: Float(cue.sharpness)
                )
            ],
            relativeTime: 0,
            duration: cue.duration
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            activePlayers.append(player)
            if activePlayers.count > 8 {
                activePlayers.removeFirst(activePlayers.count - 8)
            }
        } catch {
            playFallback(cue)
        }
    }

    func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
        activePlayers.removeAll()
    }

    private func playFallback(_ cue: YEETHapticCue) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch cue {
        case .rankUp, .personalBest, .worldRecord: .heavy
        case .catchSuccess: .medium
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: cue.intensity)
    }
}

enum YEETTheme {
    static let yellow = Color(red: 1.00, green: 0.82, blue: 0.03)
    static let ink = Color(red: 0.02, green: 0.02, blue: 0.02)
    static let paper = Color.white
    static let muted = Color(red: 0.38, green: 0.38, blue: 0.38)
    static let purple = Color(red: 0.55, green: 0.16, blue: 0.86)
    static let orange = Color(red: 1.00, green: 0.53, blue: 0.08)
    static let pagePadding: CGFloat = 24
    static let contentWidth: CGFloat = 500
    static let strokeWidth: CGFloat = 1.5
}

private struct YEETPage<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: YEETTheme.contentWidth)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, YEETTheme.pagePadding)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(background.ignoresSafeArea())
    }
}

private struct TutorialView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 18)

                YEETWordmark(size: proxy.size.height < 700 ? 78 : 104)

                Text("How long can you\nkeep your phone in the air?")
                    .font(.headline.weight(.black))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                TossTutorialMark()
                    .frame(width: 190, height: proxy.size.height < 700 ? 150 : 220)
                    .padding(.top, 16)

                Text("TAP → YEET → CATCH")
                    .font(.caption.weight(.black))
                    .tracking(0.55)

                Spacer(minLength: 18)

                Button("LET’S YEET", action: onContinue)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(YEETTheme.ink, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yeet.onboarding.continue")

                Text("YEET responsibly. Use a clear, safe area and never throw toward people, animals, traffic, or anything you don’t want to hit.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(YEETTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: 430, maxHeight: .infinity)
            .padding(.horizontal, YEETTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(YEETTheme.paper.ignoresSafeArea())
        .accessibilityIdentifier("yeet.state.tutorial")
    }
}

private struct TossTutorialMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .stroke(YEETTheme.ink, lineWidth: 3)
                .frame(width: 58, height: 104)
                .rotationEffect(.degrees(22))
                .offset(y: -22)

            Text("0")
                .font(.title2.weight(.black))
                .rotationEffect(.degrees(22))
                .offset(x: -3, y: -22)

            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 58, weight: .regular))
                .rotationEffect(.degrees(-18))
                .offset(x: 55, y: 54)

            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(YEETTheme.ink)
                    .frame(width: 3, height: 13)
                    .rotationEffect(.degrees(Double(index * 24) - 28))
                    .offset(x: CGFloat(index * 10) - 28, y: -84)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct IdleView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isPOVEnabled: Bool
    let povState: POVCaptureState
    let leaderboardState: LeaderboardLoadState
    let accountState: AccountState
    let onStart: () -> Void
    let onPOVChange: (Bool) -> Void
    let onOpenAccount: () -> Void
    let onRefreshLeaderboard: () async -> Void
    var isEnabled = true

    var body: some View {
        GeometryReader { proxy in
            let isShort = proxy.size.height < 720
            let isAccessibility = dynamicTypeSize.isAccessibilitySize
            let leaderCount = isAccessibility ? 1 : (isShort ? 3 : 6)

            VStack(spacing: 0) {
                HStack {
                    Spacer().frame(width: 42)
                    Spacer()
                    YEETWordmark(size: 48)
                    Spacer()
                    Button(action: onOpenAccount) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3.weight(.black))
                            .foregroundStyle(YEETTheme.ink)
                            .frame(width: 42, height: 42)
                            .background(YEETTheme.ink.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Account settings")
                    .accessibilityIdentifier("yeet.account.settings")
                }
                .padding(.top, isShort ? 2 : 8)

                PersonalBestRankCard(state: leaderboardState)
                    .padding(.top, isShort ? 8 : 14)

                YEETHeroButton(action: onStart, isCompact: isShort || isAccessibility)
                    .disabled(!isEnabled)
                    .accessibilityHint(
                        isEnabled ? "Starts listening for a phone toss" : "Countdown starting"
                    )
                    .accessibilityIdentifier("yeet.start")
                    .padding(.top, isShort ? 10 : 16)

                POVToggleRow(
                    isOn: isPOVEnabled,
                    isPreparing: povState == .preparing,
                    isCompact: isShort || isAccessibility,
                    onChange: onPOVChange
                )
                .disabled(!isEnabled || povState == .preparing)
                .padding(.top, isShort ? 8 : 12)

                EmbeddedLeaderboardView(
                    state: leaderboardState,
                    accountState: accountState,
                    maximumLeaderCount: leaderCount,
                    isCompact: isShort || isAccessibility,
                    onSignIn: onOpenAccount,
                    onRetry: { Task { await onRefreshLeaderboard() } }
                )
                .padding(.top, isShort ? 10 : 16)

                Spacer(minLength: 4)
            }
            .frame(maxWidth: YEETTheme.contentWidth, maxHeight: .infinity)
            .padding(.horizontal, isShort ? 16 : YEETTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(YEETTheme.paper.ignoresSafeArea())
        .accessibilityIdentifier(isEnabled ? "yeet.state.idle" : "yeet.state.preparing")
    }
}

private struct POVToggleRow: View {
    let isOn: Bool
    let isPreparing: Bool
    var isCompact = false
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(YEETTheme.yellow)
                    .frame(width: 30, height: 30)

                Image(systemName: "video.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(YEETTheme.ink)
            }
            .accessibilityHidden(true)

            Text("Record POV")
                .font(isCompact ? .system(size: 16, weight: .bold) : .subheadline.weight(.bold))
                .foregroundStyle(YEETTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer(minLength: 12)

            if isPreparing {
                ProgressView()
                    .controlSize(.small)
                    .tint(YEETTheme.ink)
                    .frame(width: 51)
                    .accessibilityLabel("Preparing camera")
            } else {
                Toggle(
                    "Record POV",
                    isOn: Binding(
                        get: { isOn },
                        set: onChange
                    )
                )
                .labelsHidden()
                .tint(YEETTheme.yellow)
                .accessibilityIdentifier("yeet.pov.toggle")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: isCompact ? 46 : 54)
        .background(YEETTheme.paper, in: Capsule())
        .overlay {
            Capsule()
                .stroke(YEETTheme.ink.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: YEETTheme.ink.opacity(0.08), radius: 5, y: 3)
        .accessibilityElement(children: .contain)
    }
}

private struct WaitingView: View {
    var body: some View {
        YEETPage(background: YEETTheme.yellow) {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                YEETActionMark()

                Spacer(minLength: 64)

                Capsule()
                    .fill(YEETTheme.paper)
                    .frame(width: 88, height: 4)
                    .accessibilityHidden(true)

                HapticCaption(title: "HAPTIC LAUNCH", foreground: YEETTheme.ink)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("YEET. Waiting for release.")
        .accessibilityIdentifier("yeet.state.waiting")
    }
}

private struct CountdownView: View {
    let step: YEETCountdownStep

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 210

    private var progressIndex: Int {
        switch step {
        case .three: 0
        case .two: 1
        case .one: 2
        }
    }

    private var hapticLabel: String {
        switch step {
        case .three: "HAPTIC LIGHT"
        case .two: "HAPTIC MEDIUM"
        case .one: "HAPTIC STRONG"
        }
    }

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                Spacer(minLength: 64)

                Text(step.rawValue.formatted())
                    .font(.system(size: numberSize, weight: .black, design: .default))
                    .fontWidth(.compressed)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .foregroundStyle(YEETTheme.ink)

                Spacer(minLength: 56)

                CountdownProgress(activeIndex: progressIndex)

                HapticCaption(title: hapticLabel, foreground: YEETTheme.muted)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Countdown " + step.rawValue.formatted())
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("yeet.state.countdown.\(step.rawValue)")
    }
}

private struct CountdownProgress: View {
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? YEETTheme.ink : YEETTheme.ink.opacity(0.12))
                    .frame(width: index == activeIndex ? 7 : 6, height: index == activeIndex ? 7 : 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HapticCaption: View {
    let title: String
    let foreground: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform.path")
                .font(.caption.weight(.bold))

            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.45)
        }
        .foregroundStyle(foreground)
        .accessibilityHidden(true)
    }
}

private struct AirborneView: View {
    let startTimestamp: TimeInterval
    let isRecording: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 106

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                HStack {
                    RecordingBadge()
                        .opacity(isRecording ? 1 : 0)
                    Spacer()
                }
                .padding(.top, 18)

                Spacer(minLength: 56)

                VStack(spacing: 2) {
                    TimelineView(.animation(minimumInterval: 0.02)) { _ in
                        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startTimestamp)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(elapsed.formatted(.number.precision(.fractionLength(2))))
                            Text("s")
                                .font(.system(size: displaySize * 0.48, weight: .black))
                        }
                        .font(.system(size: displaySize, weight: .black))
                        .fontWidth(.compressed)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .foregroundStyle(YEETTheme.ink)
                    }

                    Text("AIRTIME")
                        .font(.subheadline.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(YEETTheme.muted)
                }

                Spacer(minLength: 80)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isRecording ? "Airborne. POV recording." : "Airborne.")
        .accessibilityIdentifier("yeet.state.airborne")
    }
}

private struct CatchView: View {
    let result: DetectionResult
    let showsConfetti: Bool

    var body: some View {
        ZStack {
            YEETPage(background: YEETTheme.paper) {
                VStack(spacing: 4) {
                    Spacer(minLength: 100)
                    Text(result.airtime.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 104, weight: .black))
                        .fontWidth(.compressed)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                    Text("SECONDS AIRTIME")
                        .font(.caption.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(YEETTheme.muted)
                    Spacer(minLength: 48)
                    Image(systemName: "hands.clap.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(YEETTheme.yellow)
                    Text("NICE CATCH")
                        .font(.headline.weight(.black))
                        .padding(.top, 6)
                    Spacer(minLength: 80)
                }
            }

            if showsConfetti {
                ConfettiView(colors: [YEETTheme.yellow, YEETTheme.purple, YEETTheme.orange])
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nice catch. \(result.airtime.formatted(.number.precision(.fractionLength(2)))) seconds airtime")
        .accessibilityIdentifier("yeet.state.catch")
    }
}

private struct ConfettiView: View {
    let colors: [Color]
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { proxy in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                Canvas { context, size in
                    for index in 0..<34 {
                        let seed = Double((index * 37) % 101) / 101
                        let x = size.width * CGFloat(seed)
                        let speed = 120 + Double((index * 29) % 140)
                        let y = CGFloat((elapsed * speed + Double(index * 43)).truncatingRemainder(dividingBy: Double(size.height + 80))) - 40
                        let width = CGFloat(5 + (index % 4) * 2)
                        let rect = CGRect(x: x, y: y, width: width, height: width * 2.2)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[index % colors.count]))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { startedAt = Date() }
        .accessibilityHidden(true)
    }
}

private struct RankUpView: View {
    let previousRank: Int?
    let newRank: Int
    let showsMotion: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showsMotion {
                ConfettiView(colors: [YEETTheme.yellow, YEETTheme.purple, .white])
                    .opacity(0.8)
            }

            VStack(spacing: 22) {
                Spacer()
                Text(previousRank.map { "#\($0.formatted())" } ?? "UNRANKED")
                    .font(.title2.weight(.black))
                    .foregroundStyle(Color.white.opacity(0.38))

                Image(systemName: "arrow.down")
                    .font(.title.weight(.black))
                    .foregroundStyle(YEETTheme.purple)
                    .symbolEffect(.bounce, options: showsMotion ? .repeating : .nonRepeating)

                Text("#\(newRank.formatted())")
                    .font(.system(size: 82, weight: .black))
                    .fontWidth(.compressed)
                    .monospacedDigit()
                    .foregroundStyle(YEETTheme.ink)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 14)
                    .background(YEETTheme.yellow, in: RoundedRectangle(cornerRadius: 8))

                Text(previousRank == nil ? "YOU’RE ON THE BOARD" : "RANK UP")
                    .font(.headline.weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previousRank.map { "Rank improved from \($0) to \(newRank)" } ?? "Your first rank is \(newRank)")
        .accessibilityIdentifier("yeet.state.rankUp")
    }
}

private struct RecordingBadge: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)

            Text("RECORDING")
                .font(.caption2.weight(.black))
                .tracking(0.55)
                .foregroundStyle(YEETTheme.ink)
        }
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(YEETTheme.paper.opacity(0.92), in: Capsule())
        .overlay {
            Capsule()
                .stroke(YEETTheme.ink.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct ResultView: View {
    let kind: YEETResultKind
    let presentation: AttemptPresentation
    let povState: POVCaptureState
    let onStartAgain: () -> Void
    let onViewLeaderboard: () -> Void
    let onViewPOV: (URL) -> Void
    let onOpenAccount: () -> Void
    let onRetryScore: () -> Void
    var isEnabled = true

    @ScaledMetric(relativeTo: .largeTitle) private var resultSize: CGFloat = 104
    @ScaledMetric(relativeTo: .title) private var suffixSize: CGFloat = 50

    private var formattedAirtime: String {
        presentation.result.airtime.formatted(.number.precision(.fractionLength(2)))
    }

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                Spacer(minLength: 54)

                achievementBadge

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formattedAirtime)
                        .font(.system(size: resultSize, weight: .black, design: .default))
                        .fontWidth(.compressed)
                        .monospacedDigit()

                    Text("s")
                        .font(.system(size: suffixSize, weight: .black, design: .default))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(YEETTheme.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Airtime \(formattedAirtime) seconds")

                Text("AIRTIME")
                    .font(.subheadline.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(YEETTheme.muted)
                    .padding(.top, -2)

                outcomeDetail
                    .padding(.top, 22)

                Spacer(minLength: 28)

                YEETPrimaryButton(title: "YEET AGAIN", action: onStartAgain)
                    .disabled(!isEnabled)
                    .accessibilityHint(
                        isEnabled ? "Starts a new airtime measurement" : "Countdown starting"
                    )
                    .accessibilityIdentifier("yeet.startAgain")

                YEETSecondaryButton(title: "VIEW LEADERBOARD", action: onViewLeaderboard)
                    .accessibilityIdentifier("yeet.result.viewLeaderboard")
                    .padding(.top, 10)

                povAction
            }
        }
        .accessibilityIdentifier(isEnabled ? "yeet.state.result" : "yeet.state.preparing.result")
    }

    @ViewBuilder
    private var achievementBadge: some View {
        switch kind {
        case .normal:
            EmptyView()
        case .personalBest:
            Text("NEW PB!")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(YEETTheme.purple, in: Capsule())
                .padding(.bottom, 12)
        case .worldRecord:
            VStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.title)
                    .foregroundStyle(YEETTheme.yellow)
                Text("WORLD RECORD")
                    .font(.headline.weight(.black))
                    .foregroundStyle(YEETTheme.purple)
            }
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var outcomeDetail: some View {
        switch kind {
        case .normal:
            ResultLeaderboardPrompt(
                state: presentation.saveStatus,
                onSignIn: onOpenAccount,
                onRetry: onRetryScore
            )
        case .personalBest:
            VStack(spacing: 4) {
                Text("PREVIOUS PB")
                    .font(.caption2.weight(.black))
                    .tracking(0.7)
                    .foregroundStyle(YEETTheme.muted)
                Text(presentation.previousPersonalBestMilliseconds.map(LeaderboardFormat.heroAirtime) ?? "FIRST SCORE")
                    .font(.title3.weight(.black))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .background(YEETTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        case .worldRecord:
            Text("YOU ARE #1")
                .font(.title2.weight(.black))
                .foregroundStyle(YEETTheme.purple)
        }
    }

    @ViewBuilder
    private var povAction: some View {
        if povState == .finalizing {
            YEETSecondaryButton(title: "PROCESSING POV…", action: {})
                .disabled(true)
                .accessibilityIdentifier("yeet.pov.processing")
                .padding(.top, 12)
                .padding(.bottom, 24)
        } else if let url = presentation.povURL {
            YEETSecondaryButton(title: "VIEW POV") {
                onViewPOV(url)
            }
            .accessibilityHint("Opens the recorded point-of-view video")
            .accessibilityIdentifier("yeet.pov.view")
            .padding(.top, 12)
                .padding(.bottom, 24)

        } else {
            Color.clear
                .frame(height: 24)
        }
    }
}

private struct InvalidView: View {
    let onStartAgain: () -> Void
    var isEnabled = true

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                NoYeetMark()
                    .frame(width: 88, height: 88)
                    .foregroundStyle(YEETTheme.ink)
                    .accessibilityHidden(true)

                Text("NO YEET")
                    .font(.system(.largeTitle, design: .default, weight: .black))
                    .fontWidth(.compressed)
                    .padding(.top, 22)

                Text("Couldn’t verify that one.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(YEETTheme.muted)
                    .padding(.top, 8)

                Spacer(minLength: 100)

                YEETPrimaryButton(title: "TRY AGAIN", action: onStartAgain)
                    .disabled(!isEnabled)
                    .accessibilityHint(
                        isEnabled ? "Starts a new airtime measurement" : "Countdown starting"
                    )
                    .accessibilityIdentifier("yeet.startAgain")
                    .padding(.bottom, 34)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isEnabled ? "yeet.state.invalid" : "yeet.state.preparing.invalid")
    }
}

private struct YEETWordmark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 54

    init(size: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        Text("YEET")
            .font(.system(size: size, weight: .black, design: .default))
            .fontWidth(.compressed)
            .italic()
            .foregroundStyle(YEETTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct YEETActionMark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 94

    var body: some View {
        VStack(spacing: -2) {
            Text("YEET!")
                .font(.system(size: size, weight: .black, design: .default))
                .fontWidth(.compressed)
                .italic()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .rotationEffect(.degrees(-4))

            YEETSwoosh()
                .stroke(
                    YEETTheme.ink,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .frame(height: 26)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)
        }
        .foregroundStyle(YEETTheme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("YEET!")
    }
}

private struct YEETPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.black))
                .fontWidth(.compressed)
                .foregroundStyle(YEETTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .padding(.horizontal, 24)
                .background(YEETTheme.yellow, in: Capsule())
                .shadow(color: YEETTheme.ink.opacity(0.12), radius: 6, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct YEETSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.black))
                .fontWidth(.compressed)
                .foregroundStyle(YEETTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .padding(.horizontal, 22)
                .background(YEETTheme.paper, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(YEETTheme.ink.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: YEETTheme.ink.opacity(0.08), radius: 5, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct YEETHeroButton: View {
    let action: () -> Void
    var isCompact = false

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 48

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                YEETBurstMark()

                Text("YEET")
                    .font(.system(size: isCompact ? 38 : titleSize, weight: .black, design: .default))
                    .fontWidth(.compressed)
                    .italic()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                YEETBurstMark()
                    .scaleEffect(x: -1)
            }
            .foregroundStyle(YEETTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: isCompact ? 72 : 88)
            .padding(.horizontal, 20)
            .background(YEETTheme.yellow, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(YEETTheme.ink, lineWidth: YEETTheme.strokeWidth)
            }
            .shadow(color: YEETTheme.ink.opacity(0.16), radius: 7, y: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct YEETBurstMark: View {
    var body: some View {
        ZStack {
            Capsule()
                .frame(width: 3, height: 11)
                .offset(x: -8, y: -7)
                .rotationEffect(.degrees(-34))

            Capsule()
                .frame(width: 3, height: 13)
                .offset(x: -12, y: 4)
                .rotationEffect(.degrees(-78))

            Capsule()
                .frame(width: 3, height: 10)
                .offset(x: -5, y: 11)
                .rotationEffect(.degrees(-122))
        }
        .frame(width: 28, height: 34)
        .accessibilityHidden(true)
    }
}

private struct YEETSwoosh: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY * 0.78))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.2),
            control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.68),
            control2: CGPoint(x: rect.width * 0.64, y: rect.height * 0.27)
        )
        return path
    }
}

private struct NoYeetMark: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                Circle()
                    .stroke(lineWidth: 3)

                Circle()
                    .fill()
                    .frame(width: width * 0.08, height: height * 0.08)
                    .offset(x: -width * 0.17, y: -height * 0.12)

                Circle()
                    .fill()
                    .frame(width: width * 0.08, height: height * 0.08)
                    .offset(x: width * 0.17, y: -height * 0.12)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.28, y: height * 0.7))
                    path.addQuadCurve(
                        to: CGPoint(x: width * 0.72, y: height * 0.7),
                        control: CGPoint(x: width * 0.5, y: height * 0.48)
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .padding(4)
        }
    }
}

private struct POVReplayView: View {
    let url: URL
    let context: ShareVideoContext
    let onDone: () -> Void

    @State private var player: AVPlayer
    @State private var isPlaying = false
    @State private var isSharing = false

    init(url: URL, context: ShareVideoContext, onDone: @escaping () -> Void) {
        self.url = url
        self.context = context
        self.onDone = onDone
        _player = State(initialValue: AVPlayer(url: url))
    }

    private var formattedAirtime: String {
        context.result.airtime.formatted(.number.precision(.fractionLength(2)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            POVPlayerSurface(player: player)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: togglePlayback)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.clear,
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(formattedAirtime)s")
                            .font(.system(size: 46, weight: .black, design: .default))
                            .fontWidth(.compressed)
                            .monospacedDigit()

                        Text("AIRTIME")
                            .font(.caption.weight(.black))
                            .tracking(1.2)
                            .opacity(0.78)
                    }

                    Spacer()

                    Text("YEET")
                        .font(.system(size: 34, weight: .black, design: .default))
                        .fontWidth(.compressed)
                        .italic()
                        .rotationEffect(.degrees(-3))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                if !isPlaying {
                    Button(action: playFromStart) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.black)
                            .offset(x: 2)
                            .frame(width: 82, height: 82)
                            .background(Color.white.opacity(0.94), in: Circle())
                            .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play POV video")
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("DONE", action: onDone)
                        .buttonStyle(POVReplayButtonStyle(isPrimary: false))

                    Button("SHARE") {
                        player.pause()
                        isPlaying = false
                        isSharing = true
                    }
                        .buttonStyle(POVReplayButtonStyle(isPrimary: true))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .statusBarHidden(true)
        .fullScreenCover(isPresented: $isSharing) {
            SocialShareView(sourceURL: url, context: context) {
                isSharing = false
            }
        }
        .onAppear {
            player.actionAtItemEnd = .pause
            player.seek(to: .zero)
        }
        .onDisappear {
            player.pause()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
        ) { notification in
            guard notification.object as? AVPlayerItem === player.currentItem else { return }
            isPlaying = false
            player.seek(to: .zero)
        }
        .accessibilityIdentifier("yeet.pov.replay")
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func playFromStart() {
        player.seek(to: .zero) { _ in
            player.play()
        }
        isPlaying = true
    }
}

private struct POVReplayButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.black))
            .fontWidth(.compressed)
            .foregroundStyle(isPrimary ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isPrimary ? YEETTheme.yellow : Color.black.opacity(0.42),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isPrimary ? 0 : 0.8), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct POVPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}

#if DEBUG
private struct DebugPanel: View {
    let snapshot: DebugSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("DEBUG · \(snapshot.state.uppercased())")
                Spacer(minLength: 8)
                if let magnitude = snapshot.magnitude {
                    Text("\(magnitude, format: .number.precision(.fractionLength(3))) g")
                }
                if let observedSampleRate = snapshot.observedSampleRate {
                    Text("\(observedSampleRate, format: .number.precision(.fractionLength(1))) Hz")
                }
            }

            Text(snapshot.lastTransition)
                .lineLimit(1)

            if snapshot.candidateStart != nil || snapshot.candidateEnd != nil {
                HStack(spacing: 12) {
                    if let candidateStart = snapshot.candidateStart {
                        Text("START \(candidateStart, format: .number.precision(.fractionLength(3)))")
                    }
                    if let candidateEnd = snapshot.candidateEnd {
                        Text("END \(candidateEnd, format: .number.precision(.fractionLength(3)))")
                    }
                }
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(YEETTheme.paper)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: YEETTheme.contentWidth, alignment: .leading)
        .background(YEETTheme.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Developer diagnostics")
    }
}
#endif

#if DEBUG
#Preview("Tutorial") { TutorialView(onContinue: {}) }

#Preview("Home") {
    IdleView(
        isPOVEnabled: true,
        povState: .ready,
        leaderboardState: .loaded(.empty),
        accountState: .signedOut,
        onStart: {},
        onPOVChange: { _ in },
        onOpenAccount: {},
        onRefreshLeaderboard: {}
    )
}

#Preview("Countdown · 3") {
    YEETScreen(state: .countdown(.three))
        .preferredColorScheme(.light)
}

#Preview("Countdown · 2") {
    YEETScreen(state: .countdown(.two))
        .preferredColorScheme(.light)
}

#Preview("Countdown · 1") {
    YEETScreen(state: .countdown(.one))
        .preferredColorScheme(.light)
}

#Preview("Waiting") {
    YEETScreen(state: .waiting)
        .preferredColorScheme(.light)
}

#Preview("Airborne") {
    YEETScreen(state: .airborne(startTimestamp: ProcessInfo.processInfo.systemUptime - 0.72), isPOVRecording: true)
        .preferredColorScheme(.light)
}

#Preview("Catch") { CatchView(result: .preview, showsConfetti: true) }

#Preview("Rank up") { RankUpView(previousRank: 7_102, newRank: 6_214, showsMotion: true) }

#Preview("Result") {
    ResultView(
        kind: .normal,
        presentation: .preview,
        povState: .disabled,
        onStartAgain: {},
        onViewLeaderboard: {},
        onViewPOV: { _ in },
        onOpenAccount: {},
        onRetryScore: {}
    )
}

#Preview("New PB") {
    ResultView(
        kind: .personalBest,
        presentation: .preview,
        povState: .disabled,
        onStartAgain: {},
        onViewLeaderboard: {},
        onViewPOV: { _ in },
        onOpenAccount: {},
        onRetryScore: {}
    )
}

#Preview("World record") {
    ResultView(
        kind: .worldRecord,
        presentation: .preview,
        povState: .disabled,
        onStartAgain: {},
        onViewLeaderboard: {},
        onViewPOV: { _ in },
        onOpenAccount: {},
        onRetryScore: {}
    )
}

#Preview("Invalid") {
    InvalidView(onStartAgain: {})
        .preferredColorScheme(.light)
}

private extension DetectionResult {
    static let preview = DetectionResult(
        airborneStartTimestamp: 1,
        landingTimestamp: 2.62,
        airtime: 1.62,
        preflightPeakAcceleration: 1.8,
        impactPeakAcceleration: 2.1,
        airborneSampleCount: 162
    )
}

private extension AttemptPresentation {
    static let preview = AttemptPresentation(
        result: .preview,
        previousPersonalBestMilliseconds: 1_420,
        previousRank: 7_102,
        saveStatus: .guest(rank: 56),
        povURL: nil
    )
}
#endif
