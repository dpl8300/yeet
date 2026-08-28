import XCTest
@testable import YEET

final class AirtimeDetectorTests: XCTestCase {
    func testStationarySamplesRemainArmed() {
        var detector = armedDetector()

        for index in 0..<100 {
            _ = detector.process(sample(at: Double(index) * 0.01, magnitude: 1.0))
        }

        XCTAssertEqual(detector.state, .armed)
    }

    func testChangingAxesAtOneGMagnitudeDoesNotTrigger() {
        var detector = armedDetector()
        let samples = [
            MotionSample(timestamp: 0.00, x: 1, y: 0, z: 0),
            MotionSample(timestamp: 0.01, x: 0, y: -1, z: 0),
            MotionSample(timestamp: 0.02, x: 0, y: 0, z: 1),
            MotionSample(timestamp: 0.03, x: -1, y: 0, z: 0)
        ]

        samples.forEach { _ = detector.process($0) }

        XCTAssertEqual(detector.state, .armed)
    }

    func testBriefLowGSequenceReturnsToArmed() {
        var detector = armedDetector()
        _ = detector.process(sample(at: 0.00, magnitude: 1.0))
        for timestamp in [0.01, 0.02, 0.03] {
            _ = detector.process(sample(at: timestamp, magnitude: 0.1))
        }
        _ = detector.process(sample(at: 0.04, magnitude: 1.0))

        XCTAssertEqual(detector.state, .armed)
    }

    func testAirborneConfirmationBackdatesStartToFirstLowGSample() {
        var detector = armedDetector()
        _ = detector.process(sample(at: 1.00, magnitude: 1.0))
        for timestamp in [1.01, 1.02, 1.03, 1.04] {
            _ = detector.process(sample(at: timestamp, magnitude: 0.1))
        }

        XCTAssertEqual(detector.state, .airborne(start: 1.01))
    }

    func testHysteresisValuesDoNotEndAirborneState() {
        var detector = confirmedAirborneDetector(start: 1.0)

        _ = detector.process(sample(at: 1.04, magnitude: 0.30))
        _ = detector.process(sample(at: 1.05, magnitude: 0.49))

        XCTAssertEqual(detector.state, .airborne(start: 1.0))
    }

    func testLandingConfirmationBackdatesEndAndExcludesConfirmationDelay() throws {
        var detector = confirmedAirborneDetector(start: 1.0)
        feedLowG(into: &detector, fromHundredth: 4, throughHundredth: 19)
        _ = detector.process(sample(at: 1.20, magnitude: 0.8))
        _ = detector.process(sample(at: 1.21, magnitude: 0.9))
        _ = detector.process(sample(at: 1.22, magnitude: 1.0))

        let result = try XCTUnwrap(finishedResult(from: detector.state))
        XCTAssertEqual(result.airborneStartTimestamp, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(result.landingTimestamp, 1.2, accuracy: 0.000_001)
        XCTAssertEqual(result.airtime, 0.2, accuracy: 0.000_001)
    }

    func testSingleLandingSpikeDoesNotFinish() {
        var detector = confirmedAirborneDetector(start: 1.0)
        feedLowG(into: &detector, fromHundredth: 4, throughHundredth: 9)
        _ = detector.process(sample(at: 1.10, magnitude: 1.8))
        _ = detector.process(sample(at: 1.11, magnitude: 0.1))

        XCTAssertEqual(detector.state, .airborne(start: 1.0))
    }

    func testGradualSoftCatchFinishes() {
        var detector = confirmedAirborneDetector(start: 1.0)
        feedLowG(into: &detector, fromHundredth: 4, throughHundredth: 19)
        _ = detector.process(sample(at: 1.20, magnitude: 0.50))
        _ = detector.process(sample(at: 1.21, magnitude: 0.65))
        _ = detector.process(sample(at: 1.22, magnitude: 0.80))

        XCTAssertNotNil(finishedResult(from: detector.state))
    }

    func testTooShortEventIsRejected() {
        var detector = confirmedAirborneDetector(start: 1.0)
        feedLowG(into: &detector, fromHundredth: 4, throughHundredth: 9)
        _ = detector.process(sample(at: 1.10, magnitude: 0.8))
        _ = detector.process(sample(at: 1.11, magnitude: 0.9))
        _ = detector.process(sample(at: 1.12, magnitude: 1.0))

        XCTAssertEqual(detector.state, .invalid(.tooShort))
    }

    func testNoThrowTimesOutUsingSensorTimestamps() {
        var detector = armedDetector()
        _ = detector.process(sample(at: 10.0, magnitude: 1.0))
        _ = detector.process(sample(at: 25.0, magnitude: 1.0))

        XCTAssertEqual(detector.state, .invalid(.noThrow))
    }

    func testInFlightSampleGapIsRejected() {
        var detector = confirmedAirborneDetector(start: 1.0)
        _ = detector.process(sample(at: 1.10, magnitude: 0.1))

        XCTAssertEqual(detector.state, .invalid(.sampleGap))
    }

    func testAirtimeLongerThanThreeSecondsIsAccepted() throws {
        var detector = confirmedAirborneDetector(start: 1.0)
        for index in 1...100 {
            _ = detector.process(sample(at: 1.03 + (Double(index) * 0.04), magnitude: 0.1))
        }
        _ = detector.process(sample(at: 5.04, magnitude: 0.8))
        _ = detector.process(sample(at: 5.05, magnitude: 0.9))
        _ = detector.process(sample(at: 5.06, magnitude: 1.0))

        let result = try XCTUnwrap(finishedResult(from: detector.state))
        XCTAssertGreaterThan(result.airtime, 3)
    }

    func testOutOfOrderTimestampIsRejected() {
        var detector = armedDetector()
        _ = detector.process(sample(at: 1.0, magnitude: 1.0))
        _ = detector.process(sample(at: 1.0, magnitude: 1.0))

        XCTAssertEqual(detector.state, .invalid(.nonMonotonicTimestamp))
    }

    func testNonFiniteSampleIsRejected() {
        var detector = armedDetector()
        _ = detector.process(MotionSample(timestamp: 1.0, x: .nan, y: 0, z: 0))

        XCTAssertEqual(detector.state, .invalid(.invalidSample))
    }

    func testResetClearsPriorCandidateAndTimestamps() {
        var detector = confirmedAirborneDetector(start: 1.0)
        _ = detector.reset()
        _ = detector.arm()
        _ = detector.process(sample(at: 0.5, magnitude: 1.0))

        XCTAssertEqual(detector.state, .armed)
    }

    private func armedDetector() -> AirtimeDetector {
        var detector = AirtimeDetector()
        _ = detector.arm()
        return detector
    }

    private func confirmedAirborneDetector(start: TimeInterval) -> AirtimeDetector {
        var detector = armedDetector()
        _ = detector.process(sample(at: start, magnitude: 0.1))
        _ = detector.process(sample(at: start + 0.01, magnitude: 0.1))
        _ = detector.process(sample(at: start + 0.02, magnitude: 0.1))
        _ = detector.process(sample(at: start + 0.03, magnitude: 0.1))
        return detector
    }

    private func sample(at timestamp: TimeInterval, magnitude: Double) -> MotionSample {
        MotionSample(timestamp: timestamp, x: magnitude, y: 0, z: 0)
    }

    private func feedLowG(
        into detector: inout AirtimeDetector,
        fromHundredth first: Int,
        throughHundredth last: Int
    ) {
        guard first <= last else { return }
        for hundredth in first...last {
            _ = detector.process(
                sample(at: 1.0 + (Double(hundredth) / 100), magnitude: 0.1)
            )
        }
    }

    private func finishedResult(from state: DetectionState) -> DetectionResult? {
        guard case let .finished(result) = state else { return nil }
        return result
    }
}
