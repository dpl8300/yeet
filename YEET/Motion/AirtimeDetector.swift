import Foundation

struct AirtimeDetector: Sendable {
    private(set) var state: DetectionState = .idle

    private let config: DetectionConfig
    private var firstArmedSampleTimestamp: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var preflightPeakAcceleration = 0.0
    private var impactPeakAcceleration = 0.0
    private var airborneSampleCount = 0

    init(config: DetectionConfig = .spikeV1) {
        self.config = config
    }

    mutating func arm() -> DetectionEvent {
        let oldState = state
        resetMeasurements()
        state = .armed
        return .stateChanged(from: oldState, to: state)
    }

    mutating func reset() -> DetectionEvent? {
        let oldState = state
        resetMeasurements()
        state = .idle
        guard oldState != .idle else { return nil }
        return .stateChanged(from: oldState, to: state)
    }

    mutating func process(_ sample: MotionSample) -> DetectionEvent? {
        guard !state.isTerminal, state != .idle else { return nil }
        guard sample.isFinite else { return transition(to: .invalid(.invalidSample)) }

        if let lastTimestamp {
            guard sample.timestamp > lastTimestamp else {
                return transition(to: .invalid(.nonMonotonicTimestamp))
            }

            let gap = sample.timestamp - lastTimestamp
            if gap > config.maximumInFlightSampleGap {
                switch state {
                case .airborne, .possibleLanding:
                    return transition(to: .invalid(.sampleGap))
                case .possibleAirborne:
                    state = .armed
                default:
                    break
                }
            }
        }

        lastTimestamp = sample.timestamp
        if firstArmedSampleTimestamp == nil {
            firstArmedSampleTimestamp = sample.timestamp
        }

        if isWaitingForAirborne,
           let firstArmedSampleTimestamp,
           sample.timestamp - firstArmedSampleTimestamp >= config.armedTimeout {
            return transition(to: .invalid(.noThrow))
        }

        switch state {
        case .armed:
            preflightPeakAcceleration = max(preflightPeakAcceleration, sample.magnitude)
            if sample.magnitude <= config.airborneEntryMaximumG {
                beginFlightCandidate(with: sample)
                return transition(
                    to: .possibleAirborne(candidateStart: sample.timestamp, sampleCount: 1)
                )
            }

        case let .possibleAirborne(candidateStart, sampleCount):
            if sample.magnitude <= config.airborneEntryMaximumG {
                let nextCount = sampleCount + 1
                recordAirborneSample(sample)
                if nextCount >= config.airborneConfirmationSamples,
                   duration(sample.timestamp - candidateStart, reaches: config.airborneConfirmationDuration) {
                    return transition(to: .airborne(start: candidateStart))
                }
                return transition(
                    to: .possibleAirborne(candidateStart: candidateStart, sampleCount: nextCount)
                )
            }

            clearFlightCandidate()
            preflightPeakAcceleration = max(preflightPeakAcceleration, sample.magnitude)
            return transition(to: .armed)

        case let .airborne(start):
            recordAirborneSample(sample)
            if sample.magnitude >= config.airborneExitMinimumG {
                impactPeakAcceleration = sample.magnitude
                return transition(
                    to: .possibleLanding(
                        start: start,
                        candidateEnd: sample.timestamp,
                        sampleCount: 1
                    )
                )
            }

            if let maximumAirtime = config.maximumAirtime,
               sample.timestamp - start > maximumAirtime {
                return transition(to: .invalid(.exceededMaximumAirtime))
            }

        case let .possibleLanding(start, candidateEnd, sampleCount):
            recordAirborneSample(sample)
            impactPeakAcceleration = max(impactPeakAcceleration, sample.magnitude)

            if sample.magnitude >= config.airborneExitMinimumG {
                let nextCount = sampleCount + 1
                if nextCount >= config.landingConfirmationSamples,
                   duration(sample.timestamp - candidateEnd, reaches: config.landingConfirmationDuration) {
                    return finish(start: start, end: candidateEnd)
                }
                return transition(
                    to: .possibleLanding(
                        start: start,
                        candidateEnd: candidateEnd,
                        sampleCount: nextCount
                    )
                )
            }

            if let maximumAirtime = config.maximumAirtime,
               sample.timestamp - start > maximumAirtime {
                return transition(to: .invalid(.exceededMaximumAirtime))
            }
            impactPeakAcceleration = 0
            return transition(to: .airborne(start: start))

        case .idle, .finished, .invalid:
            break
        }

        return nil
    }

    private var isWaitingForAirborne: Bool {
        switch state {
        case .armed, .possibleAirborne: true
        default: false
        }
    }

    private mutating func beginFlightCandidate(with sample: MotionSample) {
        impactPeakAcceleration = 0
        airborneSampleCount = 0
        recordAirborneSample(sample)
    }

    private mutating func recordAirborneSample(_ sample: MotionSample) {
        airborneSampleCount += 1
    }

    private mutating func clearFlightCandidate() {
        impactPeakAcceleration = 0
        airborneSampleCount = 0
    }

    private mutating func finish(start: TimeInterval, end: TimeInterval) -> DetectionEvent {
        let airtime = end - start
        if airtime < config.minimumAirtime {
            return transition(to: .invalid(.tooShort))
        }
        if let maximumAirtime = config.maximumAirtime, airtime > maximumAirtime {
            return transition(to: .invalid(.exceededMaximumAirtime))
        }

        let result = DetectionResult(
            airborneStartTimestamp: start,
            landingTimestamp: end,
            airtime: airtime,
            preflightPeakAcceleration: preflightPeakAcceleration,
            impactPeakAcceleration: impactPeakAcceleration,
            airborneSampleCount: airborneSampleCount
        )
        return transition(to: .finished(result))
    }

    private func duration(_ value: TimeInterval, reaches threshold: TimeInterval) -> Bool {
        value + 1e-9 >= threshold
    }

    private mutating func transition(to newState: DetectionState) -> DetectionEvent {
        let oldState = state
        state = newState
        return .stateChanged(from: oldState, to: newState)
    }

    private mutating func resetMeasurements() {
        firstArmedSampleTimestamp = nil
        lastTimestamp = nil
        preflightPeakAcceleration = 0
        impactPeakAcceleration = 0
        airborneSampleCount = 0
    }
}
