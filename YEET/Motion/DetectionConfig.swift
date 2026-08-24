import Foundation

struct DetectionConfig: Equatable, Sendable {
    let requestedSampleInterval: TimeInterval
    let airborneEntryMaximumG: Double
    let airborneConfirmationSamples: Int
    let airborneConfirmationDuration: TimeInterval
    let airborneExitMinimumG: Double
    let landingConfirmationSamples: Int
    let landingConfirmationDuration: TimeInterval
    let minimumAirtime: TimeInterval
    let maximumAirtime: TimeInterval
    let armedTimeout: TimeInterval
    let maximumInFlightSampleGap: TimeInterval
    let diagnosticImpactThresholdG: Double
    let debugPublishInterval: TimeInterval
    let debugTraceCapacity: Int

    static let spikeV1 = DetectionConfig(
        requestedSampleInterval: 0.01,
        airborneEntryMaximumG: 0.25,
        airborneConfirmationSamples: 4,
        airborneConfirmationDuration: 0.03,
        airborneExitMinimumG: 0.50,
        landingConfirmationSamples: 3,
        landingConfirmationDuration: 0.02,
        minimumAirtime: 0.12,
        maximumAirtime: 3.0,
        armedTimeout: 15.0,
        maximumInFlightSampleGap: 0.05,
        diagnosticImpactThresholdG: 1.50,
        debugPublishInterval: 0.10,
        debugTraceCapacity: 2_500
    )
}
