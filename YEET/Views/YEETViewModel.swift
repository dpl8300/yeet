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

enum POVCaptureState: Equatable, Sendable {
    case disabled
    case preparing
    case ready
    case recording
    case finalizing
    case available(URL)
    case failed(POVCaptureError)
}

struct POVAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
    let offersSettings: Bool
}

@MainActor
final class YEETViewModel: ObservableObject {
    @Published private(set) var state: YEETViewState = .idle
    @Published private(set) var isPOVEnabled = false
    @Published private(set) var povState: POVCaptureState = .disabled
    @Published private(set) var povAlert: POVAlert?
#if DEBUG
    @Published private(set) var debugSnapshot: DebugSnapshot?
#endif

    private let config: DetectionConfig
    private let preCountdownSleep: @Sendable () async throws -> Void
    private let countdownSleep: @Sendable () async throws -> Void
    private let launchRenderSleep: @Sendable () async throws -> Void
    private let motionServiceFactory: () -> any MotionServicing
    private let povCaptureServiceFactory: () -> any POVCaptureServicing
    private let povPermissionsAuthorized: () -> Bool
    private var motionService: (any MotionServicing)?
    private var povCaptureService: (any POVCaptureServicing)?
    private var activeSessionID: UUID?
    private var countdownTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var povPreparationTask: Task<Void, Never>?
    private var povLifecycleTask: Task<Void, Never>?
    private var pendingPOVError: POVCaptureError?
    private var hasAppliedPOVDefault = false

    var canStart: Bool {
        !isPOVEnabled || povState == .ready
    }

    var canStartAgain: Bool {
        povState != .preparing && povState != .finalizing
    }

    var isPOVRecording: Bool {
        povState == .recording
    }

    var povVideoURL: URL? {
        guard case let .available(url) = povState else { return nil }
        return url
    }

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
        motionServiceFactory: @escaping () -> any MotionServicing = { MotionService() },
        povCaptureServiceFactory: @escaping () -> any POVCaptureServicing = {
            POVCaptureService()
        },
        povPermissionsAuthorized: @escaping () -> Bool = {
            POVCaptureService.requiredPermissionsAreAuthorized
        }
    ) {
        self.config = config
        self.preCountdownSleep = preCountdownSleep
        self.countdownSleep = countdownSleep
        self.launchRenderSleep = launchRenderSleep
        self.motionServiceFactory = motionServiceFactory
        self.povCaptureServiceFactory = povCaptureServiceFactory
        self.povPermissionsAuthorized = povPermissionsAuthorized
    }

    func start() {
        guard canStart else { return }
        startCountdown(from: .idle)
    }

    func startAgain() {
        guard canStartAgain else { return }
        let context: YEETPreparationContext = switch state {
        case let .result(result): .result(result)
        case let .invalid(reason): .invalid(reason)
        default: .idle
        }
        startCountdown(from: context)
    }

    func setPOVEnabled(_ enabled: Bool) {
        guard enabled != isPOVEnabled else { return }
        hasAppliedPOVDefault = true
        povAlert = nil

        if enabled {
            enablePOV()
        } else {
            disablePOV()
        }
    }

    func dismissPOVAlert() {
        povAlert = nil
    }

    func enablePOVByDefaultIfAuthorized() {
        guard !hasAppliedPOVDefault, !isPOVEnabled, povPermissionsAuthorized() else {
            return
        }
        hasAppliedPOVDefault = true
        enablePOV()
    }

    private func startCountdown(from context: YEETPreparationContext) {
        cancelActiveSession()
        clearPreviousPOV()

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

        if isPOVEnabled, let povCaptureService {
            do {
                try await povCaptureService.prepare()
                try Task.checkCancellation()
                guard sessionID == activeSessionID else {
                    await povCaptureService.discardRecording()
                    return
                }

                try await povCaptureService.startRecording()
                try Task.checkCancellation()
                guard sessionID == activeSessionID else {
                    await povCaptureService.discardRecording()
                    return
                }
                povState = .recording
            } catch is CancellationError {
                await povCaptureService.discardRecording()
                return
            } catch {
                recordPOVFailure(captureError(from: error), presentAlert: false)
            }
        }

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
        completePOVCapture(for: finalState)

        if let pendingPOVError {
            self.pendingPOVError = nil
            presentPOVAlert(for: pendingPOVError)
        }
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

    private func enablePOV() {
        isPOVEnabled = true
        povState = .preparing
        pendingPOVError = nil

        let service = povCaptureService ?? povCaptureServiceFactory()
        povCaptureService = service
        povPreparationTask?.cancel()
        povPreparationTask = Task { [weak self, service] in
            do {
                try await service.prepare()
                try Task.checkCancellation()
                guard let self, self.isPOVEnabled else {
                    await service.cleanUp()
                    return
                }
                self.povState = .ready
            } catch is CancellationError {
                await service.cleanUp()
            } catch {
                guard let self else { return }
                self.recordPOVFailure(self.captureError(from: error), presentAlert: true)
            }
        }
    }

    private func disablePOV() {
        isPOVEnabled = false
        povState = .disabled
        pendingPOVError = nil
        povPreparationTask?.cancel()
        povPreparationTask = nil
        povLifecycleTask?.cancel()
        povLifecycleTask = nil

        guard let service = povCaptureService else { return }
        povCaptureService = nil
        Task {
            await service.cleanUp()
        }
    }

    private func clearPreviousPOV() {
        guard case let .available(url) = povState else { return }
        try? FileManager.default.removeItem(at: url)
        povState = isPOVEnabled ? .ready : .disabled
    }

    private func completePOVCapture(for finalState: YEETViewState) {
        guard povState == .recording, let service = povCaptureService else { return }
        povState = .finalizing
        povLifecycleTask?.cancel()

        switch finalState {
        case .result:
            povLifecycleTask = Task { [weak self, service] in
                do {
                    let url = try await service.stopRecording()
                    try Task.checkCancellation()
                    guard let self else {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    self.povState = .available(url)
                } catch is CancellationError {
                    await service.discardRecording()
                } catch {
                    guard let self else { return }
                    self.recordPOVFailure(self.captureError(from: error), presentAlert: true)
                }
            }

        default:
            povLifecycleTask = Task { [weak self, service] in
                await service.discardRecording()
                guard let self else { return }
                self.povState = self.isPOVEnabled ? .ready : .disabled
            }
        }
    }

    private func recordPOVFailure(_ error: POVCaptureError, presentAlert: Bool) {
        isPOVEnabled = false
        povState = .failed(error)
        pendingPOVError = presentAlert ? nil : error

        if presentAlert {
            presentPOVAlert(for: error)
        }

        guard let service = povCaptureService else { return }
        povCaptureService = nil
        Task {
            await service.cleanUp()
        }
    }

    private func presentPOVAlert(for error: POVCaptureError) {
        povAlert = POVAlert(
            title: "POV Recording Unavailable",
            message: error.localizedDescription,
            offersSettings: error.shouldOfferSettings
        )
    }

    private func captureError(from error: Error) -> POVCaptureError {
        if let error = error as? POVCaptureError {
            return error
        }
        return .recordingFailed(error.localizedDescription)
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
