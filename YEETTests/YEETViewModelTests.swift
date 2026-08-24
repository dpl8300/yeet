import XCTest
@testable import YEET

@MainActor
final class YEETViewModelTests: XCTestCase {
    func testStartAndSuccessfulResultFlow() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(motionServiceFactory: { service })

        viewModel.start()
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
    }

    func testUnavailableSensorMapsToInvalidState() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(motionServiceFactory: { service })
        viewModel.start()

        service.fail(.unavailable)
        await settle()

        XCTAssertEqual(viewModel.state, .invalid(.sensorUnavailable))
    }

    func testSensorUpdateErrorMapsToInvalidState() async {
        let service = MockMotionService()
        let viewModel = YEETViewModel(motionServiceFactory: { service })
        viewModel.start()

        service.fail(.updateFailed("synthetic failure"))
        await settle()

        XCTAssertEqual(viewModel.state, .invalid(.sensorError("synthetic failure")))
        XCTAssertTrue(service.didStop)
    }

    func testStartAgainCreatesFreshSession() async {
        let first = MockMotionService()
        let second = MockMotionService()
        var services = [first, second]
        let viewModel = YEETViewModel { services.removeFirst() }

        viewModel.start()
        first.fail(.unavailable)
        await settle()
        XCTAssertEqual(viewModel.state, .invalid(.sensorUnavailable))

        viewModel.startAgain()
        XCTAssertEqual(viewModel.state, .waiting)
        XCTAssertTrue(first.didStop)
        XCTAssertTrue(second.didStart)
    }

    func testInactiveAppInvalidatesActiveSession() {
        let service = MockMotionService()
        let viewModel = YEETViewModel(motionServiceFactory: { service })
        viewModel.start()

        viewModel.handleScenePhase(.inactive)

        XCTAssertEqual(viewModel.state, .invalid(.appInactive))
        XCTAssertTrue(service.didStop)
    }

    private func sample(at timestamp: TimeInterval, magnitude: Double) -> MotionSample {
        MotionSample(timestamp: timestamp, x: magnitude, y: 0, z: 0)
    }

    private func settle() async {
        await Task.yield()
        await Task.yield()
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
