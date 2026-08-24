import Foundation

enum DetectionInvalidReason: Error, Equatable, Sendable {
    case noThrow
    case tooShort
    case exceededMaximumAirtime
    case sampleGap
    case nonMonotonicTimestamp
    case invalidSample
    case sensorUnavailable
    case sensorError(String)
    case appInactive
    case sensorStalled

    var debugDescription: String {
        switch self {
        case .noThrow: "no throw before timeout"
        case .tooShort: "airtime below minimum"
        case .exceededMaximumAirtime: "airtime above maximum"
        case .sampleGap: "unsafe gap between in-flight samples"
        case .nonMonotonicTimestamp: "duplicate or out-of-order sample timestamp"
        case .invalidSample: "sample contained a non-finite value"
        case .sensorUnavailable: "accelerometer unavailable"
        case let .sensorError(message): "Core Motion error: \(message)"
        case .appInactive: "app became inactive"
        case .sensorStalled: "sensor updates stalled"
        }
    }
}

enum DetectionState: Equatable, Sendable {
    case idle
    case armed
    case possibleAirborne(candidateStart: TimeInterval, sampleCount: Int)
    case airborne(start: TimeInterval)
    case possibleLanding(start: TimeInterval, candidateEnd: TimeInterval, sampleCount: Int)
    case finished(DetectionResult)
    case invalid(DetectionInvalidReason)

    var debugName: String {
        switch self {
        case .idle: "idle"
        case .armed: "armed"
        case .possibleAirborne: "possibleAirborne"
        case .airborne: "airborne"
        case .possibleLanding: "possibleLanding"
        case .finished: "finished"
        case .invalid: "invalid"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .finished, .invalid: true
        default: false
        }
    }
}

enum DetectionEvent: Equatable, Sendable {
    case stateChanged(from: DetectionState, to: DetectionState)

    var state: DetectionState {
        switch self {
        case let .stateChanged(_, to): to
        }
    }
}
