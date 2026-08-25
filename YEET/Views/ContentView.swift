import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = YEETViewModel()

    var body: some View {
        YEETScreen(
            state: viewModel.state,
            onStart: viewModel.start,
            onStartAgain: viewModel.startAgain
        )
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
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
        }
    }
}

struct YEETScreen: View {
    let state: YEETViewState
    let onStart: () -> Void
    let onStartAgain: () -> Void

    var body: some View {
        switch state {
        case .idle:
            IdleView(onStart: onStart)

        case .waiting:
            WaitingView()

        case .airborne:
            AirborneView()

        case let .result(result):
            ResultView(result: result, onStartAgain: onStartAgain)

        case .invalid:
            InvalidView(onStartAgain: onStartAgain)
        }
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
    let onStart: () -> Void

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                YEETWordmark(size: 54)
                    .padding(.top, 10)

                YEETHeroButton(action: onStart)
                    .accessibilityHint("Starts listening for a phone toss")
                    .accessibilityIdentifier("yeet.start")
                    .padding(.top, 54)

                Spacer(minLength: 80)
            }
        }
        .accessibilityIdentifier("yeet.state.idle")
    }
}

private struct WaitingView: View {
    var body: some View {
        YEETPage(background: YEETTheme.yellow) {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

                YEETActionMark()

                Spacer(minLength: 80)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("YEET. Waiting for release.")
        .accessibilityIdentifier("yeet.state.waiting")
    }
}

private struct AirborneView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 68

    var body: some View {
        YEETPage(background: YEETTheme.paper) {
            VStack(spacing: 0) {
                Spacer(minLength: 80)

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
        .accessibilityLabel("Airborne.")
        .accessibilityIdentifier("yeet.state.airborne")
    }
}

private struct ResultView: View {
    let result: DetectionResult
    let onStartAgain: () -> Void

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

                Spacer(minLength: 120)

                YEETPrimaryButton(title: "YEET AGAIN", action: onStartAgain)
                    .accessibilityHint("Starts a new airtime measurement")
                    .accessibilityIdentifier("yeet.startAgain")
                    .padding(.bottom, 34)
            }
        }
        .accessibilityIdentifier("yeet.state.result")
    }
}

private struct InvalidView: View {
    let onStartAgain: () -> Void

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
                    .accessibilityHint("Starts a new airtime measurement")
                    .accessibilityIdentifier("yeet.startAgain")
                    .padding(.bottom, 34)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yeet.state.invalid")
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

#Preview("Idle") {
    YEETScreen(state: .idle, onStart: {}, onStartAgain: {})
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
