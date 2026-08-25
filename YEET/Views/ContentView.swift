import AVFoundation
import AVKit
import CoreHaptics
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var hapticPlayer = YEETHapticPlayer()
    @StateObject private var viewModel = YEETViewModel()
    @State private var replayPresentation: POVReplayPresentation?

    var body: some View {
        YEETScreen(
            state: viewModel.state,
            isPOVEnabled: viewModel.isPOVEnabled,
            povState: viewModel.povState,
            canStart: viewModel.canStart,
            canStartAgain: viewModel.canStartAgain,
            isPOVRecording: viewModel.isPOVRecording,
            onStart: viewModel.start,
            onStartAgain: viewModel.startAgain,
            onPOVChange: viewModel.setPOVEnabled,
            onViewPOV: { url, result in
                replayPresentation = POVReplayPresentation(url: url, result: result)
            }
        )
        .onChange(of: viewModel.state) { oldState, newState in
            guard let cue = YEETHapticCue.forTransition(from: oldState, to: newState) else {
                return
            }
            hapticPlayer.play(cue)
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
            POVReplayView(url: replay.url, result: replay.result) {
                replayPresentation = nil
            }
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
            viewModel.enablePOVByDefaultIfAuthorized()
            hapticPlayer.prepare()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
            if newPhase == .active {
                viewModel.enablePOVByDefaultIfAuthorized()
                hapticPlayer.prepare()
            } else {
                hapticPlayer.stop()
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
    let result: DetectionResult
}

struct YEETScreen: View {
    let state: YEETViewState
    var isPOVEnabled = false
    var povState: POVCaptureState = .disabled
    var canStart = true
    var canStartAgain = true
    var isPOVRecording = false
    let onStart: () -> Void
    let onStartAgain: () -> Void
    var onPOVChange: (Bool) -> Void = { _ in }
    var onViewPOV: (URL, DetectionResult) -> Void = { _, _ in }

    var body: some View {
        switch state {
        case .idle:
            IdleView(
                isPOVEnabled: isPOVEnabled,
                povState: povState,
                onStart: onStart,
                onPOVChange: onPOVChange,
                isEnabled: canStart
            )

        case let .preparing(context):
            switch context {
            case .idle:
                IdleView(
                    isPOVEnabled: isPOVEnabled,
                    povState: povState,
                    onStart: {},
                    onPOVChange: { _ in },
                    isEnabled: false
                )
            case let .result(result):
                ResultView(
                    result: result,
                    povState: povState,
                    onStartAgain: {},
                    onViewPOV: { _ in },
                    isEnabled: false
                )
            case .invalid:
                InvalidView(onStartAgain: {}, isEnabled: false)
            }

        case let .countdown(step):
            CountdownView(step: step)

        case .waiting:
            WaitingView()

        case .airborne:
            AirborneView(isRecording: isPOVRecording)

        case let .result(result):
            ResultView(
                result: result,
                povState: povState,
                onStartAgain: onStartAgain,
                onViewPOV: { url in onViewPOV(url, result) },
                isEnabled: canStartAgain
            )

        case .invalid:
            InvalidView(onStartAgain: onStartAgain, isEnabled: canStartAgain)
        }
    }
}

enum YEETHapticCue: Int, CaseIterable, Equatable, Sendable {
    case light
    case medium
    case strong
    case launch

    var intensity: Double {
        switch self {
        case .light: 0.35
        case .medium: 0.55
        case .strong: 0.8
        case .launch: 1.0
        }
    }

    var duration: TimeInterval {
        switch self {
        case .light: 0.14
        case .medium: 0.22
        case .strong: 0.30
        case .launch: 0.42
        }
    }

    var sharpness: Double {
        switch self {
        case .light: 0.2
        case .medium: 0.4
        case .strong: 0.65
        case .launch: 0.9
        }
    }

    static func forTransition(
        from oldState: YEETViewState,
        to newState: YEETViewState
    ) -> YEETHapticCue? {
        switch newState {
        case .countdown(.three): .light
        case .countdown(.two): .medium
        case .countdown(.one): .strong
        case .waiting where oldState == .countdown(.one): .launch
        default: nil
        }
    }
}

@MainActor
private final class YEETHapticPlayer: ObservableObject {
    private var engine: CHHapticEngine?

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            let engine = try engine ?? CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
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
        } catch {
            playFallback(cue)
        }
    }

    func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private func playFallback(_ cue: YEETHapticCue) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch cue {
        case .light: .light
        case .medium: .medium
        case .strong, .launch: .heavy
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: cue.intensity)
    }
}

private enum YEETTheme {
    static let yellow = Color(red: 1.00, green: 0.82, blue: 0.03)
    static let ink = Color(red: 0.02, green: 0.02, blue: 0.02)
    static let paper = Color.white
    static let muted = Color(red: 0.38, green: 0.38, blue: 0.38)
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

private struct IdleView: View {
    let isPOVEnabled: Bool
    let povState: POVCaptureState
    let onStart: () -> Void
    let onPOVChange: (Bool) -> Void
    var isEnabled = true

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                YEETWordmark(size: 54)
                    .padding(.top, 10)

                YEETHeroButton(action: onStart)
                    .disabled(!isEnabled)
                    .accessibilityHint(
                        isEnabled ? "Starts listening for a phone toss" : "Countdown starting"
                    )
                    .accessibilityIdentifier("yeet.start")
                    .padding(.top, 54)

                POVToggleRow(
                    isOn: isPOVEnabled,
                    isPreparing: povState == .preparing,
                    onChange: onPOVChange
                )
                .disabled(!isEnabled || povState == .preparing)
                .padding(.top, 22)

                Spacer(minLength: 80)
            }
        }
        .accessibilityIdentifier(isEnabled ? "yeet.state.idle" : "yeet.state.preparing")
    }
}

private struct POVToggleRow: View {
    let isOn: Bool
    let isPreparing: Bool
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
                .font(.subheadline.weight(.bold))
                .foregroundStyle(YEETTheme.ink)

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
        .frame(minHeight: 58)
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
    let isRecording: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 68

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
                    Text("AIRBORNE")
                        .font(.system(size: displaySize, weight: .black, design: .default))
                        .fontWidth(.compressed)
                        .italic()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(YEETTheme.ink)

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
    let result: DetectionResult
    let povState: POVCaptureState
    let onStartAgain: () -> Void
    let onViewPOV: (URL) -> Void
    var isEnabled = true

    @ScaledMetric(relativeTo: .largeTitle) private var resultSize: CGFloat = 104
    @ScaledMetric(relativeTo: .title) private var suffixSize: CGFloat = 50

    private var formattedAirtime: String {
        result.airtime.formatted(.number.precision(.fractionLength(3)))
    }

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                Spacer(minLength: 96)

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

                Spacer(minLength: 86)

                YEETPrimaryButton(title: "YEET AGAIN", action: onStartAgain)
                    .disabled(!isEnabled)
                    .accessibilityHint(
                        isEnabled ? "Starts a new airtime measurement" : "Countdown starting"
                    )
                    .accessibilityIdentifier("yeet.startAgain")

                povAction
            }
        }
        .accessibilityIdentifier(isEnabled ? "yeet.state.result" : "yeet.state.preparing.result")
    }

    @ViewBuilder
    private var povAction: some View {
        switch povState {
        case .finalizing:
            YEETSecondaryButton(title: "PROCESSING POV…", action: {})
                .disabled(true)
                .accessibilityIdentifier("yeet.pov.processing")
                .padding(.top, 12)
                .padding(.bottom, 34)

        case let .available(url):
            YEETSecondaryButton(title: "VIEW POV") {
                onViewPOV(url)
            }
            .accessibilityHint("Opens the recorded point-of-view video")
            .accessibilityIdentifier("yeet.pov.view")
            .padding(.top, 12)
            .padding(.bottom, 34)

        default:
            Color.clear
                .frame(height: 34)
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

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 48

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                YEETBurstMark()

                Text("YEET")
                    .font(.system(size: titleSize, weight: .black, design: .default))
                    .fontWidth(.compressed)
                    .italic()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                YEETBurstMark()
                    .scaleEffect(x: -1)
            }
            .foregroundStyle(YEETTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 98)
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
    let result: DetectionResult
    let onDone: () -> Void

    @State private var player: AVPlayer
    @State private var isPlaying = false

    init(url: URL, result: DetectionResult, onDone: @escaping () -> Void) {
        self.url = url
        self.result = result
        self.onDone = onDone
        _player = State(initialValue: AVPlayer(url: url))
    }

    private var formattedAirtime: String {
        result.airtime.formatted(.number.precision(.fractionLength(2)))
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

                    Button("WATCH AGAIN", action: playFromStart)
                        .buttonStyle(POVReplayButtonStyle(isPrimary: true))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .statusBarHidden(true)
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
#Preview("Idle") {
    YEETScreen(state: .idle, onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}

#Preview("Preparing") {
    YEETScreen(state: .preparing(.idle), onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}

#Preview("Countdown · 3") {
    YEETScreen(state: .countdown(.three), onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}

#Preview("Countdown · 2") {
    YEETScreen(state: .countdown(.two), onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}

#Preview("Countdown · 1") {
    YEETScreen(state: .countdown(.one), onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}

#Preview("Waiting") {
    YEETScreen(state: .waiting, onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}

#Preview("Airborne") {
    YEETScreen(state: .airborne, onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}

#Preview("Result") {
    YEETScreen(
        state: .result(
            DetectionResult(
                airborneStartTimestamp: 1,
                landingTimestamp: 2.62,
                airtime: 1.62,
                preflightPeakAcceleration: 1.8,
                impactPeakAcceleration: 2.1,
                airborneSampleCount: 162
            )
        ),
        onStart: {},
        onStartAgain: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Invalid") {
    YEETScreen(state: .invalid(.tooShort), onStart: {}, onStartAgain: {})
        .preferredColorScheme(.light)
}
#endif
