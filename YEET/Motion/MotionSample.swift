import Foundation

struct MotionSample: Equatable, Sendable {
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double {
        sqrt((x * x) + (y * y) + (z * z))
    }

    var isFinite: Bool {
        timestamp.isFinite && x.isFinite && y.isFinite && z.isFinite && magnitude.isFinite
    }
}
