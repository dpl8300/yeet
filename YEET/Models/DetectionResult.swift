import Foundation

struct DetectionResult: Equatable, Sendable {
    let airborneStartTimestamp: TimeInterval
    let landingTimestamp: TimeInterval
    let airtime: TimeInterval
    let preflightPeakAcceleration: Double
    let impactPeakAcceleration: Double
    let airborneSampleCount: Int
}
