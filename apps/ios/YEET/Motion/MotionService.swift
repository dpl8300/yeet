import CoreMotion
import Foundation

enum MotionServiceError: Error, Equatable, Sendable {
    case unavailable
    case updateFailed(String)
}

protocol MotionServicing: AnyObject, Sendable {
    func start(
        handler: @escaping @Sendable (Result<MotionSample, MotionServiceError>) -> Void
    )
    func stop()
}

final class MotionService: MotionServicing, @unchecked Sendable {
    private let motionManager: CMMotionManager
    private let operationQueue: OperationQueue
    private let config: DetectionConfig
    private let lock = NSLock()
    private var running = false

    init(
        motionManager: CMMotionManager = CMMotionManager(),
        config: DetectionConfig = .spikeV1
    ) {
        self.motionManager = motionManager
        self.config = config

        let queue = OperationQueue()
        queue.name = "com.dpl8300.yeet.motion"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        operationQueue = queue
    }

    func start(
        handler: @escaping @Sendable (Result<MotionSample, MotionServiceError>) -> Void
    ) {
        guard motionManager.isAccelerometerAvailable else {
            handler(.failure(.unavailable))
            return
        }

        let shouldStart = lock.withLock {
            guard !running else { return false }
            running = true
            return true
        }
        guard shouldStart else { return }

        motionManager.accelerometerUpdateInterval = config.requestedSampleInterval
        motionManager.startAccelerometerUpdates(to: operationQueue) { [weak self] data, error in
            guard let self, self.isRunning else { return }

            if let error {
                handler(.failure(.updateFailed(error.localizedDescription)))
                self.stop()
                return
            }

            guard let data else { return }
            let acceleration = data.acceleration
            handler(
                .success(
                    MotionSample(
                        timestamp: data.timestamp,
                        x: acceleration.x,
                        y: acceleration.y,
                        z: acceleration.z
                    )
                )
            )
        }
    }

    func stop() {
        let shouldStop = lock.withLock {
            let wasRunning = running
            running = false
            return wasRunning
        }
        if shouldStop {
            motionManager.stopAccelerometerUpdates()
        }
    }

    private var isRunning: Bool {
        lock.withLock { running }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
