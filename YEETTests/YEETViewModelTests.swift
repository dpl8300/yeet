import XCTest
@testable import YEET

@MainActor
final class YEETViewModelTests: XCTestCase {
    func testCountdownAdvancesInOrderAndArmsOnlyOnLaunch() async {
        let service = MockMotionService()
        let preCountdownSleeper = ManualCountdownSleeper()
        let stepSleeper = ManualCountdownSleeper()
        let launchRenderSleeper = ManualCountdownSleeper()
        let viewModel = YEETViewModel(
            preCountdownSleep: { try await preCountdownSleeper.sleep() },
            countdownSleep: { try await stepSleeper.sleep() },
            launchRenderSleep: { try await launchRenderSleeper.sleep() },
            motionServiceFactory: { service }
        )

        viewModel.start()
        XCTAssertEqual(viewModel.state, .preparing(.idle))
        XCTAssertFalse(service.didStart)

        await preCountdownSleeper.advance()
        await wait(for: .countdown(.three), in: viewModel)
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

    func testCountdownHapticsAreUniqueAndProgressivelyStronger() {
        let transitions: [(YEETViewState, YEETViewState, YEETHapticCue)] = [
            (.preparing(.idle), .countdown(.three), .light),
            (.countdown(.three), .countdown(.two), .medium),
            (.countdown(.two), .countdown(.one), .strong),
            (.countdown(.one), .waiting, .launch)
        ]

        for (oldState, newState, expectedCue) in transitions {
            XCTAssertEqual(
                YEETHapticCue.forTransition(from: oldState, to: newState),
                expectedCue
            )
        }

        let intensities = YEETHapticCue.allCases.map(\.intensity)
        XCTAssertEqual(Set(intensities).count, YEETHapticCue.allCases.count)
        for pair in zip(intensities, intensities.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }

        let durations = YEETHapticCue.allCases.map(\.duration)
        XCTAssertEqual(Set(durations).count, YEETHapticCue.allCases.count)
        for pair in zip(durations, durations.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
    }

    func testStartAndSuccessfulResultFlow() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(
            preCountdownSleep: {},
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
        XCTAssertEqual(viewModel.state, .airborne)

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
        XCTAssertEqual(viewModel.state, .preparing(.result(result)))
    }

    func testUnavailableSensorMapsToInvalidState() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(
            preCountdownSleep: {},
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
            preCountdownSleep: {},
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
            preCountdownSleep: {},
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
        XCTAssertEqual(
            viewModel.state,
            .preparing(.invalid(.sensorUnavailable))
        )
        await settle()
        XCTAssertEqual(viewModel.state, .waiting)
        XCTAssertTrue(first.didStop)
        XCTAssertTrue(second.didStart)
    }

    func testInactiveAppInvalidatesActiveSession() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(
            preCountdownSleep: {},
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
        let preCountdownSleeper = ManualCountdownSleeper()
        let viewModel = YEETViewModel(
            preCountdownSleep: { try await preCountdownSleeper.sleep() },
            countdownSleep: {},
            launchRenderSleep: {},
            motionServiceFactory: { service }
        )

        viewModel.start()
        XCTAssertEqual(viewModel.state, .preparing(.idle))

        viewModel.handleScenePhase(.inactive)
        await settle()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(service.didStart)
    }

    private func sample(at timestamp: TimeInterval, magnitude: Double) -> MotionSample {
        MotionSample(timestamp: timestamp, x: magnitude, y: 0, z: 0)
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
    private var handler: (@Sendable (Result<MotionSample, MotionServiceError>) -> Void)?
    private(set) var didStart = false
    private(set) var didStop = false

    func start(
        handler: @escaping @Sendable (Result<MotionSample, MotionServiceError>) -> Void
    ) {
        lock.lock()
        didStart = true
        self.handler = handler
        lock.unlock()
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
