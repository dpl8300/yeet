import Foundation

struct DetectionSessionOutput: Sendable {
    let event: DetectionEvent?
#if DEBUG
    let debugSnapshot: DebugSnapshot?
#endif

    var shouldDeliverToUI: Bool {
#if DEBUG
        event != nil || debugSnapshot != nil
#else
        event != nil
#endif
    }
}

final class DetectionSession: @unchecked Sendable {
    private var detector: AirtimeDetector
    private let config: DetectionConfig
#if DEBUG
    private let trace: DebugTrace
    private var lastDebugPublishTimestamp: TimeInterval?
    private var didDumpTrace = false
#endif

    init(config: DetectionConfig = .spikeV1) {
        self.config = config
        detector = AirtimeDetector(config: config)
#if DEBUG
        trace = DebugTrace(config: config)
#endif
    }

    func arm() {
        _ = detector.arm()
#if DEBUG
        trace.reset()
        lastDebugPublishTimestamp = nil
        didDumpTrace = false
#endif
    }

    func process(_ sample: MotionSample) -> DetectionSessionOutput {
        let event = detector.process(sample)
#if DEBUG
        trace.record(sample: sample, state: detector.state, event: event)
        let shouldPublish = lastDebugPublishTimestamp.map {
            sample.timestamp - $0 >= config.debugPublishInterval
        } ?? true
        let snapshot = shouldPublish ? trace.snapshot() : nil
        if shouldPublish {
            lastDebugPublishTimestamp = sample.timestamp
        }
        if detector.state.isTerminal, !didDumpTrace {
            didDumpTrace = true
            trace.dumpCSV(terminalState: detector.state)
        }
        return DetectionSessionOutput(event: event, debugSnapshot: snapshot)
#else
        return DetectionSessionOutput(event: event)
#endif
    }
}
