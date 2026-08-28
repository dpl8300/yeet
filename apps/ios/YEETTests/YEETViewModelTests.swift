import XCTest
@testable import YEET

@MainActor
final class YEETViewModelTests: XCTestCase {
    func testCountdownAdvancesInOrderAndArmsOnlyOnLaunch() async {
        let service = MockMotionService()
        let stepSleeper = ManualCountdownSleeper()
        let launchRenderSleeper = ManualCountdownSleeper()
        let viewModel = YEETViewModel(
            countdownSleep: { try await stepSleeper.sleep() },
            launchRenderSleep: { try await launchRenderSleeper.sleep() },
            motionServiceFactory: { service }
        )
        viewModel.start()
        XCTAssertEqual(viewModel.state, .countdown(.three))
        XCTAssertFalse(service.didStart)

        await stepSleeper.advance()
        await wait(for: .countdown(.two), in: viewModel)
        XCTAssertFalse(service.didStart)

        await stepSleeper.advance()
        await wait(for: .countdown(.one), in: viewModel)
        XCTAssertFalse(service.didStart)

        await stepSleeper.advance()
        await wait(for: .waiting, in: viewModel)
        XCTAssertFalse(service.didStart)

        await launchRenderSleeper.advance()
        await waitForMotionStart(service)
        XCTAssertTrue(service.didStart)
    }

    func testStartAndSuccessfulResultFlow() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { service }
        )

        viewModel.start()
        await settle()
        XCTAssertEqual(viewModel.state, .waiting)

        for timestamp in [1.00, 1.01, 1.02, 1.03] {
            service.emit(sample(at: timestamp, magnitude: 0.1))
        }
        await settle()
        XCTAssertEqual(viewModel.state, .airborne(startTimestamp: 1.0))

        for hundredth in 4...19 {
            service.emit(
                sample(at: 1.0 + (Double(hundredth) / 100), magnitude: 0.1)
            )
        }
        service.emit(sample(at: 1.20, magnitude: 0.8))
        service.emit(sample(at: 1.21, magnitude: 0.9))
        service.emit(sample(at: 1.22, magnitude: 1.0))
        await settle()

        guard case let .result(result) = viewModel.state else {
            return XCTFail("Expected a result")
        }
        XCTAssertEqual(result.airtime, 0.2, accuracy: 0.000_001)
        XCTAssertTrue(service.didStop)

        viewModel.startAgain()
        XCTAssertEqual(viewModel.state, .countdown(.three))
    }

    func testUnavailableSensorMapsToInvalidState() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { service }
        )
        viewModel.start()
        await settle()

        service.fail(.unavailable)
        await settle()

        XCTAssertEqual(viewModel.state, .invalid(.sensorUnavailable))
    }

    func testSensorUpdateErrorMapsToInvalidState() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { service }
        )
        viewModel.start()
        await settle()

        service.fail(.updateFailed("synthetic failure"))
        await settle()

        XCTAssertEqual(viewModel.state, .invalid(.sensorError("synthetic failure")))
        XCTAssertTrue(service.didStop)
    }

    func testStartAgainCreatesFreshSession() async {
        let first = MockMotionService()
        let second = MockMotionService()
        var services = [first, second]
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { services.removeFirst() }
        )

        viewModel.start()
        await settle()
        first.fail(.unavailable)
        await settle()
        XCTAssertEqual(viewModel.state, .invalid(.sensorUnavailable))

        viewModel.startAgain()
        XCTAssertEqual(viewModel.state, .countdown(.three))
        await settle()
        XCTAssertEqual(viewModel.state, .waiting)
        XCTAssertTrue(first.didStop)
        XCTAssertTrue(second.didStart)
    }

    func testInactiveAppInvalidatesActiveSession() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { service }
        )
        viewModel.start()
        await settle()

        viewModel.handleScenePhase(.inactive)

        XCTAssertEqual(viewModel.state, .invalid(.appInactive))
        XCTAssertTrue(service.didStop)
    }

    func testInactiveAppCancelsPreparationWithoutStartingMotion() async {
        let service = MockMotionService()
        let stepSleeper = ManualCountdownSleeper()
        let viewModel = YEETViewModel(
            countdownSleep: { try await stepSleeper.sleep() },
            launchRenderSleep: {},
            motionServiceFactory: { service }
        )

        viewModel.start()
        XCTAssertEqual(viewModel.state, .countdown(.three))

        viewModel.handleScenePhase(.inactive)
        await settle()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(service.didStart)
    }

    func testEnablingAndDisablingPOVPreparesAndCleansUpCapture() async {
        let capture = MockPOVCaptureService()
        let viewModel = YEETViewModel(
            povCaptureServiceFactory: { capture }
        )

        XCTAssertFalse(viewModel.isPOVEnabled)
        XCTAssertEqual(viewModel.povState, .disabled)

        viewModel.setPOVEnabled(true)
        XCTAssertTrue(viewModel.isPOVEnabled)
        await waitForPOVState(.ready, in: viewModel)
        XCTAssertEqual(capture.prepareCallCount, 1)

        viewModel.setPOVEnabled(false)
        XCTAssertFalse(viewModel.isPOVEnabled)
        XCTAssertEqual(viewModel.povState, .disabled)
        await waitUntil { capture.cleanUpCallCount == 1 }
    }

    func testPOVRestoresPersistedSelectionOnlyOnce() async {
        let capture = MockPOVCaptureService()
        var storedPreference = true
        let viewModel = YEETViewModel(
            povCaptureServiceFactory: { capture },
            readPOVPreference: { storedPreference },
            writePOVPreference: { storedPreference = $0 }
        )

        viewModel.restorePOVPreference()
        await waitForPOVState(.ready, in: viewModel)

        XCTAssertTrue(viewModel.isPOVEnabled)
        XCTAssertEqual(capture.prepareCallCount, 1)

        viewModel.setPOVEnabled(false)
        await waitUntil { capture.cleanUpCallCount == 1 }
        viewModel.restorePOVPreference()

        XCTAssertFalse(viewModel.isPOVEnabled)
        XCTAssertFalse(storedPreference)
        XCTAssertEqual(viewModel.povState, .disabled)
        XCTAssertEqual(capture.prepareCallCount, 1)
    }

    func testDeniedPOVPermissionKeepsSelectionAndRecoversAfterSettings() async {
        let capture = MockPOVCaptureService()
        capture.prepareError = POVCaptureError.permissionDenied(.camera)
        var storedPreference = false
        let viewModel = YEETViewModel(
            povCaptureServiceFactory: { capture },
            readPOVPreference: { storedPreference },
            writePOVPreference: { storedPreference = $0 }
        )

        viewModel.setPOVEnabled(true)
        await waitForPOVState(
            .failed(.permissionDenied(.camera)),
            in: viewModel
        )

        XCTAssertTrue(viewModel.isPOVEnabled)
        XCTAssertTrue(storedPreference)
        XCTAssertTrue(viewModel.canStart)
        XCTAssertEqual(viewModel.povAlert?.title, "POV Recording Unavailable")
        XCTAssertEqual(viewModel.povAlert?.offersSettings, true)
        await waitUntil { capture.cleanUpCallCount == 1 }

        capture.prepareError = nil
        viewModel.restorePOVPreference()
        await waitForPOVState(.ready, in: viewModel)
        XCTAssertEqual(capture.prepareCallCount, 2)
    }

    func testPOVRecordingStartsBeforeMotionAndFinalizesSuccessfulResult() async {
        let order = CallOrderRecorder()
        let motion = MockMotionService(orderRecorder: order)
        let capture = MockPOVCaptureService(orderRecorder: order)
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { motion },
            povCaptureServiceFactory: { capture }
        )

        viewModel.setPOVEnabled(true)
        await waitForPOVState(.ready, in: viewModel)
        viewModel.start()
        await wait(for: .waiting, in: viewModel)
        await waitUntil { motion.didStart }

        XCTAssertEqual(viewModel.povState, .recording)
        let povStartIndex = order.index(of: "pov.start")
        let motionStartIndex = order.index(of: "motion.start")
        XCTAssertNotNil(povStartIndex)
        XCTAssertNotNil(motionStartIndex)
        if let povStartIndex, let motionStartIndex {
            XCTAssertLessThan(povStartIndex, motionStartIndex)
        }

        emitSuccessfulToss(with: motion)
        await waitForResult(in: viewModel)
        await waitForPOVState(.available(capture.outputURL), in: viewModel)

        XCTAssertEqual(capture.stopCallCount, 1)
        XCTAssertEqual(viewModel.povVideoURL, capture.outputURL)
        XCTAssertTrue(viewModel.isPOVEnabled)
        XCTAssertTrue(viewModel.canStart)

        viewModel.releaseAttemptPOV()
        XCTAssertNil(viewModel.povVideoURL)
        XCTAssertEqual(viewModel.povState, .ready)
    }

    func testInvalidAttemptDiscardsPOVAndKeepsPreferenceReadyForRetry() async {
        let motion = MockMotionService()
        let capture = MockPOVCaptureService()
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { motion },
            povCaptureServiceFactory: { capture }
        )

        viewModel.setPOVEnabled(true)
        await waitForPOVState(.ready, in: viewModel)
        viewModel.start()
        await wait(for: .waiting, in: viewModel)
        await waitUntil { motion.didStart }

        motion.fail(.unavailable)
        await wait(for: .invalid(.sensorUnavailable), in: viewModel)
        await waitForPOVState(.ready, in: viewModel)

        XCTAssertEqual(capture.discardCallCount, 1)
        XCTAssertNil(viewModel.povVideoURL)
        XCTAssertTrue(viewModel.isPOVEnabled)
    }

    func testInactiveAppDiscardsActivePOVRecording() async {
        let motion = MockMotionService()
        let capture = MockPOVCaptureService()
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { motion },
            povCaptureServiceFactory: { capture }
        )

        viewModel.setPOVEnabled(true)
        await waitForPOVState(.ready, in: viewModel)
        viewModel.start()
        await wait(for: .waiting, in: viewModel)

        viewModel.handleScenePhase(.inactive)
        await wait(for: .invalid(.appInactive), in: viewModel)
        await waitForPOVState(.ready, in: viewModel)

        XCTAssertEqual(capture.discardCallCount, 1)
        XCTAssertNil(viewModel.povVideoURL)
    }

    func testPOVStartFailureDoesNotBlockAirtimeMeasurement() async {
        let motion = MockMotionService()
        let capture = MockPOVCaptureService()
        capture.startError = POVCaptureError.recordingFailed("synthetic failure")
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { motion },
            povCaptureServiceFactory: { capture }
        )

        viewModel.setPOVEnabled(true)
        await waitForPOVState(.ready, in: viewModel)
        viewModel.start()
        await wait(for: .waiting, in: viewModel)
        await waitUntil { motion.didStart }

        XCTAssertTrue(viewModel.isPOVEnabled)
        XCTAssertTrue(viewModel.canStart)
        XCTAssertEqual(
            viewModel.povState,
            .failed(.recordingFailed("synthetic failure"))
        )

        emitSuccessfulToss(with: motion)
        await waitForResult(in: viewModel)

        XCTAssertEqual(viewModel.povAlert?.offersSettings, false)
        XCTAssertNil(viewModel.povVideoURL)
    }

    func testNonPOVAttemptNeverCreatesCaptureService() async {
        let motion = MockMotionService()
        var captureFactoryCallCount = 0
        let viewModel = YEETViewModel(
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { motion },
            povCaptureServiceFactory: {
                captureFactoryCallCount += 1
                return MockPOVCaptureService()
            }
        )

        viewModel.start()
        await wait(for: .waiting, in: viewModel)
        await waitUntil { motion.didStart }

        XCTAssertEqual(captureFactoryCallCount, 0)
        XCTAssertEqual(viewModel.povState, .disabled)
    }

    private func sample(at timestamp: TimeInterval, magnitude: Double) -> MotionSample {
        MotionSample(timestamp: timestamp, x: magnitude, y: 0, z: 0)
    }

    private func emitSuccessfulToss(with service: MockMotionService) {
        for timestamp in [1.00, 1.01, 1.02, 1.03] {
            service.emit(sample(at: timestamp, magnitude: 0.1))
        }
        for hundredth in 4...19 {
            service.emit(
                sample(at: 1.0 + (Double(hundredth) / 100), magnitude: 0.1)
            )
        }
        service.emit(sample(at: 1.20, magnitude: 0.8))
        service.emit(sample(at: 1.21, magnitude: 0.9))
        service.emit(sample(at: 1.22, magnitude: 1.0))
    }

    private func settle() async {
        await Task.yield()
        await Task.yield()
    }

    private func wait(
        for expectedState: YEETViewState,
        in viewModel: YEETViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 where viewModel.state != expectedState {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.state, expectedState, file: file, line: line)
    }

    private func waitForMotionStart(
        _ service: MockMotionService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 where !service.didStart {
            await Task.yield()
        }
        XCTAssertTrue(service.didStart, file: file, line: line)
    }

    private func waitForPOVState(
        _ expectedState: POVCaptureState,
        in viewModel: YEETViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 where viewModel.povState != expectedState {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(viewModel.povState, expectedState, file: file, line: line)
    }

    private func waitForResult(
        in viewModel: YEETViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if case .result = viewModel.state {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Expected a result", file: file, line: line)
    }

    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

private actor ManualCountdownSleeper {
    private var pendingAdvances = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func sleep() async throws {
        try Task.checkCancellation()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if pendingAdvances > 0 {
                    pendingAdvances -= 1
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelPendingSleep() }
        }

        try Task.checkCancellation()
    }

    func advance() {
        if let continuation {
            self.continuation = nil
            continuation.resume()
        } else {
            pendingAdvances += 1
        }
    }

    private func cancelPendingSleep() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume()
    }
}

private final class MockMotionService: MotionServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let orderRecorder: CallOrderRecorder?
    private var handler: (@Sendable (Result<MotionSample, MotionServiceError>) -> Void)?
    private(set) var didStart = false
    private(set) var didStop = false

    init(orderRecorder: CallOrderRecorder? = nil) {
        self.orderRecorder = orderRecorder
    }

    func start(
        handler: @escaping @Sendable (Result<MotionSample, MotionServiceError>) -> Void
    ) {
        lock.lock()
        didStart = true
        self.handler = handler
        lock.unlock()
        orderRecorder?.record("motion.start")
    }

    func stop() {
        lock.lock()
        didStop = true
        lock.unlock()
    }

    func emit(_ sample: MotionSample) {
        currentHandler?(.success(sample))
    }

    func fail(_ error: MotionServiceError) {
        currentHandler?(.failure(error))
    }

    private var currentHandler: (@Sendable (Result<MotionSample, MotionServiceError>) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}

private final class MockPOVCaptureService: POVCaptureServicing, @unchecked Sendable {
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mock-pov.mov")

    var prepareError: Error?
    var startError: Error?
    var stopError: Error?

    private let lock = NSLock()
    private let orderRecorder: CallOrderRecorder?
    private var _prepareCallCount = 0
    private var _startCallCount = 0
    private var _stopCallCount = 0
    private var _discardCallCount = 0
    private var _cleanUpCallCount = 0

    init(orderRecorder: CallOrderRecorder? = nil) {
        self.orderRecorder = orderRecorder
    }

    var prepareCallCount: Int { locked { _prepareCallCount } }
    var startCallCount: Int { locked { _startCallCount } }
    var stopCallCount: Int { locked { _stopCallCount } }
    var discardCallCount: Int { locked { _discardCallCount } }
    var cleanUpCallCount: Int { locked { _cleanUpCallCount } }

    func prepare() async throws {
        locked { _prepareCallCount += 1 }
        if let prepareError {
            throw prepareError
        }
    }

    func startRecording() async throws {
        locked { _startCallCount += 1 }
        orderRecorder?.record("pov.start")
        if let startError {
            throw startError
        }
    }

    func stopRecording() async throws -> URL {
        locked { _stopCallCount += 1 }
        if let stopError {
            throw stopError
        }
        return outputURL
    }

    func discardRecording() async {
        locked { _discardCallCount += 1 }
    }

    func cleanUp() async {
        locked { _cleanUpCallCount += 1 }
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }
}

private final class CallOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func index(of event: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return events.firstIndex(of: event)
    }
}
