import Foundation
import SwiftUI

enum YEETCountdownStep: Int, CaseIterable, Equatable, Sendable {
    case three = 3
    case two = 2
    case one = 1
}

enum YEETPreparationContext: Equatable, Sendable {
    case idle
    case result(DetectionResult)
    case invalid(DetectionInvalidReason)
}

enum YEETViewState: Equatable, Sendable {
    case idle
    case preparing(YEETPreparationContext)
    case countdown(YEETCountdownStep)
    case waiting
    case airborne
    case result(DetectionResult)
    case invalid(DetectionInvalidReason)
}

@MainActor
final class YEETViewModel: ObservableObject {
    @Published private(set) var state: YEETViewState = .idle
#if DEBUG
    @Published private(set) var debugSnapshot: DebugSnapshot?
#endif

    private let config: DetectionConfig
    private let preCountdownSleep: @Sendable () async throws -> Void
    private let countdownSleep: @Sendable () async throws -> Void
    private let launchRenderSleep: @Sendable () async throws -> Void
    private let motionServiceFactory: () -> any MotionServicing
    private var motionService: (any MotionServicing)?
    private var activeSessionID: UUID?
    private var countdownTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        config: DetectionConfig = .spikeV1,
        preCountdownSleep: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(400))
        },
        countdownSleep: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .seconds(1))
        },
        launchRenderSleep: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(16))
        },
        motionServiceFactory: @escaping () -> any MotionServicing = { MotionService() }
    ) {
        self.config = config
        self.preCountdownSleep = preCountdownSleep
        self.countdownSleep = countdownSleep
        self.launchRenderSleep = launchRenderSleep
        self.motionServiceFactory = motionServiceFactory
    }

    func start() {
        startCountdown(from: .idle)
    }

    func startAgain() {
        let context: YEETPreparationContext = switch state {
        case let .result(result): .result(result)
        case let .invalid(reason): .invalid(reason)
        default: .idle
        }
        startCountdown(from: context)
    }

    private func startCountdown(from context: YEETPreparationContext) {
        cancelActiveSession()

        state = .preparing(context)
        motionService = motionServiceFactory()
#if DEBUG
        debugSnapshot = nil
#endif

        let initialSleep = preCountdownSleep
        let stepSleep = countdownSleep
        countdownTask = Task { [weak self, initialSleep, stepSleep] in
            do {
                try await initialSleep()
                try Task.checkCancellation()
                self?.state = .countdown(.three)

                try await stepSleep()
                try Task.checkCancellation()
                self?.state = .countdown(.two)

                try await stepSleep()
                try Task.checkCancellation()
                self?.state = .countdown(.one)

                try await stepSleep()
                try Task.checkCancellation()
                try await self?.beginDetection()
            } catch {
                // Cancellation is expected when the app backgrounds or a new run starts.
            }
        }
    }

    private func beginDetection() async throws {
        let sessionID = UUID()
        guard let service = motionService else { return }
        let session = DetectionSession(config: config)
        session.arm()

        activeSessionID = sessionID
        state = .waiting
        try await launchRenderSleep()
        try Task.checkCancellation()
        guard sessionID == activeSessionID else { return }

        scheduleTimeout(
            after: config.armedTimeout + 0.5,
            sessionID: sessionID,
            reason: .noThrow
        )
        countdownTask = nil

        service.start { [weak self] result in
            switch result {
            case let .success(sample):
                let output = session.process(sample)
                guard output.shouldDeliverToUI else { return }
                Task { @MainActor [weak self] in
                    self?.receive(output, for: sessionID)
                }

            case .failure(.unavailable):
                Task { @MainActor [weak self] in
                    self?.fail(.sensorUnavailable, for: sessionID)
                }

            case let .failure(.updateFailed(message)):
                Task { @MainActor [weak self] in
                    self?.fail(.sensorError(message), for: sessionID)
                }
            }
        }
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        guard scenePhase != .active else { return }

        switch state {
        case .preparing, .countdown:
            cancelActiveSession()
            state = .idle
        default:
            if activeSessionID != nil {
                invalidateActiveSession(reason: .appInactive)
            }
        }
    }

    private func receive(_ output: DetectionSessionOutput, for sessionID: UUID) {
        guard sessionID == activeSessionID else { return }
#if DEBUG
        if let snapshot = output.debugSnapshot {
            debugSnapshot = snapshot
        }
#endif
        guard let event = output.event else { return }

        switch event.state {
        case .airborne:
            state = .airborne
            scheduleTimeout(
                after: config.maximumAirtime + 0.5,
                sessionID: sessionID,
                reason: .sensorStalled
            )

        case .possibleLanding:
            state = .airborne

        case let .finished(result):
            finish(.result(result))

        case let .invalid(reason):
            finish(.invalid(reason))

        case .idle, .armed, .possibleAirborne:
            state = .waiting
        }
    }

    private func fail(_ reason: DetectionInvalidReason, for sessionID: UUID) {
        guard sessionID == activeSessionID else { return }
        finish(.invalid(reason))
    }

    private func invalidateActiveSession(reason: DetectionInvalidReason) {
        guard activeSessionID != nil else { return }
        finish(.invalid(reason))
    }

    private func finish(_ finalState: YEETViewState) {
        countdownTask?.cancel()
        countdownTask = nil
        motionService?.stop()
        motionService = nil
        activeSessionID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        state = finalState
    }

    private func cancelActiveSession() {
        countdownTask?.cancel()
        countdownTask = nil
        motionService?.stop()
        motionService = nil
        activeSessionID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func scheduleTimeout(
        after duration: TimeInterval,
        sessionID: UUID,
        reason: DetectionInvalidReason
    ) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.fail(reason, for: sessionID)
        }
    }
}
