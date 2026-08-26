final class DetectionSession: @unchecked Sendable {
    private var detector: AirtimeDetector

    init(config: DetectionConfig = .spikeV1) {
        detector = AirtimeDetector(config: config)
    }

    func arm() {
        _ = detector.arm()
    }

    func process(_ sample: MotionSample) -> DetectionEvent? {
        detector.process(sample)
    }
}
