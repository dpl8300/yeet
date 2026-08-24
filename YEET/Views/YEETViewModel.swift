import Foundation
import SwiftUI

enum YEETViewState: Equatable, Sendable {
    case idle
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
    private let motionServiceFactory: () -> any MotionServicing
    private var motionService: (any MotionServicing)?
    private var activeSessionID: UUID?
    private var timeoutTask: Task<Void, Never>?

    init(
        config: DetectionConfig = .spikeV1,
        motionServiceFactory: @escaping () -> any MotionServicing = { MotionService() }
    ) {
        self.config = config
        self.motionServiceFactory = motionServiceFactory
    }

    func start() {
        cancelActiveSession()

        let sessionID = UUID()
        let service = motionServiceFactory()
        let session = DetectionSession(config: config)
        session.arm()

        activeSessionID = sessionID
        motionService = service
        state = .waiting
#if DEBUG
        debugSnapshot = nil
#endif
        scheduleTimeout(
            after: config.armedTimeout + 0.5,
            sessionID: sessionID,
            reason: .noThrow
        )

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

    func startAgain() {
        start()
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        guard scenePhase != .active, activeSessionID != nil else { return }
        invalidateActiveSession(reason: .appInactive)
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
        motionService?.stop()
        motionService = nil
        activeSessionID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        state = finalState
    }

    private func cancelActiveSession() {
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
