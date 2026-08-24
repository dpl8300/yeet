#if DEBUG
import Foundation
import OSLog

struct DebugSnapshot: Equatable, Sendable {
    let state: String
    let magnitude: Double?
    let observedSampleRate: Double?
    let lastTransition: String
    let candidateStart: TimeInterval?
    let candidateEnd: TimeInterval?
}

private struct DebugTraceEntry: Sendable {
    let sample: MotionSample
    let delta: TimeInterval?
    let state: DetectionState
    let eventDescription: String
}

final class DebugTrace: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.dpl8300.yeet", category: "MotionTrace")
    private let config: DetectionConfig
    private var entries: [DebugTraceEntry] = []
    private var lastTimestamp: TimeInterval?
    private var lastMagnitude: Double?
    private var lastTransition = "armed"

    init(config: DetectionConfig) {
        self.config = config
        entries.reserveCapacity(config.debugTraceCapacity)
    }

    func reset() {
        entries.removeAll(keepingCapacity: true)
        lastTimestamp = nil
        lastMagnitude = nil
        lastTransition = "armed"
    }

    func record(sample: MotionSample, state: DetectionState, event: DetectionEvent?) {
        let delta = lastTimestamp.map { sample.timestamp - $0 }
        lastTimestamp = sample.timestamp

        var descriptions: [String] = []
        if let lastMagnitude {
            if lastMagnitude > config.airborneEntryMaximumG,
               sample.magnitude <= config.airborneEntryMaximumG {
                descriptions.append(
                    String(format: "crossed airborne entry <= %.2f g", config.airborneEntryMaximumG)
                )
            }
            if lastMagnitude < config.airborneExitMinimumG,
               sample.magnitude >= config.airborneExitMinimumG {
                descriptions.append(
                    String(format: "crossed airborne exit >= %.2f g", config.airborneExitMinimumG)
                )
            }
            if lastMagnitude < config.diagnosticImpactThresholdG,
               sample.magnitude >= config.diagnosticImpactThresholdG {
                descriptions.append(
                    String(format: "crossed impact marker >= %.2f g", config.diagnosticImpactThresholdG)
                )
            }
        }
        lastMagnitude = sample.magnitude
        if let event {
            descriptions.append(Self.describe(event))
        }
        let description = descriptions.joined(separator: "; ")
        if !description.isEmpty {
            lastTransition = description
            logger.debug("\(description, privacy: .public)")
        }

        entries.append(
            DebugTraceEntry(
                sample: sample,
                delta: delta,
                state: state,
                eventDescription: description
            )
        )
        if entries.count > config.debugTraceCapacity {
            entries.removeFirst(entries.count - config.debugTraceCapacity)
        }
    }

    func snapshot() -> DebugSnapshot {
        let latest = entries.last
        let rate = latest?.delta.flatMap { $0 > 0 ? 1 / $0 : nil }
        return DebugSnapshot(
            state: latest?.state.debugName ?? "armed",
            magnitude: latest?.sample.magnitude,
            observedSampleRate: rate,
            lastTransition: lastTransition,
            candidateStart: latest.flatMap { Self.candidateStart(in: $0.state) },
            candidateEnd: latest.flatMap { Self.candidateEnd(in: $0.state) }
        )
    }

    func dumpCSV(terminalState: DetectionState) {
        print("YEET_TRACE_BEGIN")
        print("timestamp,delta,x,y,z,magnitude,state,event")
        for entry in entries {
            let delta = entry.delta.map { String(format: "%.6f", $0) } ?? ""
            let row = [
                String(format: "%.6f", entry.sample.timestamp),
                delta,
                String(format: "%.6f", entry.sample.x),
                String(format: "%.6f", entry.sample.y),
                String(format: "%.6f", entry.sample.z),
                String(format: "%.6f", entry.sample.magnitude),
                entry.state.debugName,
                entry.eventDescription
            ].joined(separator: ",")
            print(row)
        }
        print("terminal,\(String(describing: terminalState))")
        print("YEET_TRACE_END")
    }

    private static func describe(_ event: DetectionEvent) -> String {
        switch event {
        case let .stateChanged(from, to):
            let destination: String
            switch to {
            case let .finished(result):
                destination = String(format: "finished (%.6f seconds)", result.airtime)
            case let .invalid(reason):
                destination = "invalid (\(reason.debugDescription))"
            default:
                destination = to.debugName
            }
            return "\(from.debugName) -> \(destination)"
        }
    }

    private static func candidateStart(in state: DetectionState) -> TimeInterval? {
        switch state {
        case let .possibleAirborne(candidateStart, _): candidateStart
        case let .airborne(start): start
        case let .possibleLanding(start, _, _): start
        case let .finished(result): result.airborneStartTimestamp
        default: nil
        }
    }

    private static func candidateEnd(in state: DetectionState) -> TimeInterval? {
        switch state {
        case let .possibleLanding(_, candidateEnd, _): candidateEnd
        case let .finished(result): result.landingTimestamp
        default: nil
        }
    }
}
#endif
