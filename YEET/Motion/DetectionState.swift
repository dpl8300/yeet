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

}

enum DetectionState: Equatable, Sendable {
    case idle
    case armed
    case possibleAirborne(candidateStart: TimeInterval, sampleCount: Int)
    case airborne(start: TimeInterval)
    case possibleLanding(start: TimeInterval, candidateEnd: TimeInterval, sampleCount: Int)
    case finished(DetectionResult)
    case invalid(DetectionInvalidReason)

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
