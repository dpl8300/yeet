@preconcurrency import AVFoundation
import Foundation

enum POVCapturePermission: String, Equatable, Sendable {
    case camera
    case microphone
}

enum POVCaptureError: Error, Equatable, LocalizedError, Sendable {
    case permissionDenied(POVCapturePermission)
    case deviceUnavailable(POVCapturePermission)
    case configurationFailed(String)
    case recordingFailed(String)
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case let .permissionDenied(permission):
            "\(permission.rawValue.capitalized) access is required to record POV video."
        case let .deviceUnavailable(permission):
            "This device does not have an available \(permission.rawValue)."
        case let .configurationFailed(message):
            "POV recording could not be prepared. \(message)"
        case let .recordingFailed(message):
            "POV recording failed. \(message)"
        case .noActiveRecording:
            "There is no active POV recording."
        }
    }

    var shouldOfferSettings: Bool {
        if case .permissionDenied = self {
            return true
        }
        return false
    }
}

protocol POVCaptureServicing: AnyObject {
    func prepare() async throws
    func startRecording() async throws
    func stopRecording() async throws -> URL
    func discardRecording() async
    func cleanUp() async
}

final class POVCaptureService: NSObject, POVCaptureServicing, @unchecked Sendable {
    static var requiredPermissionsAreAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private let captureQueue = DispatchQueue(label: "com.dpl8300.yeet.pov-capture")
    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var isConfigured = false
    private var currentOutputURL: URL?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    func prepare() async throws {
        try await Self.requirePermission(for: .video, permission: .camera)
        try await Self.requirePermission(for: .audio, permission: .microphone)

        try await performThrowingOnCaptureQueue {
            if !self.isConfigured {
                try self.configureSession()
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            guard self.captureSession.isRunning else {
                throw POVCaptureError.configurationFailed("The camera session did not start.")
            }
        }
    }

    func startRecording() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            captureQueue.async {
                guard self.isConfigured, self.captureSession.isRunning else {
                    continuation.resume(
                        throwing: POVCaptureError.configurationFailed(
                            "The camera session is not ready."
                        )
                    )
                    return
                }
                guard !self.movieOutput.isRecording, self.startContinuation == nil else {
                    continuation.resume(
                        throwing: POVCaptureError.recordingFailed(
                            "A recording is already in progress."
                        )
                    )
                    return
                }

                self.removeCurrentOutput()
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("YEET-POV-\(UUID().uuidString)")
                    .appendingPathExtension("mov")

                self.currentOutputURL = outputURL
                self.startContinuation = continuation
                self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            }
        }
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            captureQueue.async {
                guard self.movieOutput.isRecording else {
                    continuation.resume(throwing: POVCaptureError.noActiveRecording)
                    return
                }
                guard self.stopContinuation == nil else {
                    continuation.resume(
                        throwing: POVCaptureError.recordingFailed(
                            "The recording is already being finalized."
                        )
                    )
                    return
                }

                self.stopContinuation = continuation
                self.movieOutput.stopRecording()
            }
        }
    }

    func discardRecording() async {
        let wasRecording = await performOnCaptureQueue {
            self.movieOutput.isRecording
        }

        if wasRecording {
            _ = try? await stopRecording()
        }

        await performOnCaptureQueue {
            self.removeCurrentOutput()
        }
    }

    func cleanUp() async {
        await discardRecording()
        await performOnCaptureQueue {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }

            if self.isConfigured {
                self.captureSession.beginConfiguration()
                for input in self.captureSession.inputs {
                    self.captureSession.removeInput(input)
                }
                for output in self.captureSession.outputs {
                    self.captureSession.removeOutput(output)
                }
                self.captureSession.commitConfiguration()
                self.isConfigured = false
            }
        }
    }

    private func configureSession() throws {
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw POVCaptureError.deviceUnavailable(.camera)
        }
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw POVCaptureError.deviceUnavailable(.microphone)
        }

        let cameraInput: AVCaptureDeviceInput
        let microphoneInput: AVCaptureDeviceInput
        do {
            cameraInput = try AVCaptureDeviceInput(device: camera)
            microphoneInput = try AVCaptureDeviceInput(device: microphone)
        } catch {
            throw POVCaptureError.configurationFailed(error.localizedDescription)
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else {
            captureSession.sessionPreset = .high
        }

        guard captureSession.canAddInput(cameraInput) else {
            throw POVCaptureError.configurationFailed("The rear camera input is unavailable.")
        }
        captureSession.addInput(cameraInput)

        guard captureSession.canAddInput(microphoneInput) else {
            throw POVCaptureError.configurationFailed("The microphone input is unavailable.")
        }
        captureSession.addInput(microphoneInput)

        guard captureSession.canAddOutput(movieOutput) else {
            throw POVCaptureError.configurationFailed("Movie recording is unavailable.")
        }
        captureSession.addOutput(movieOutput)

        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        captureSession.automaticallyConfiguresApplicationAudioSession = true
        isConfigured = true
    }

    private func removeCurrentOutput() {
        guard let currentOutputURL else { return }
        try? FileManager.default.removeItem(at: currentOutputURL)
        self.currentOutputURL = nil
    }

    private func performOnCaptureQueue<T>(
        _ work: @escaping () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            captureQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    private func performThrowingOnCaptureQueue<T>(
        _ work: @escaping () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func requirePermission(
        for mediaType: AVMediaType,
        permission: POVCapturePermission
    ) async throws {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
            guard granted else {
                throw POVCaptureError.permissionDenied(permission)
            }
        case .denied, .restricted:
            throw POVCaptureError.permissionDenied(permission)
        @unknown default:
            throw POVCaptureError.permissionDenied(permission)
        }
    }
}

extension POVCaptureService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        captureQueue.async {
            self.startContinuation?.resume()
            self.startContinuation = nil
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        captureQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }

            let wasSuccessful: Bool
            if let error = error as NSError? {
                wasSuccessful = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
                    ?? false
            } else {
                wasSuccessful = true
            }

            if !wasSuccessful {
                let captureError = POVCaptureError.recordingFailed(
                    error?.localizedDescription ?? "The movie file could not be completed."
                )
                self.startContinuation?.resume(throwing: captureError)
                self.stopContinuation?.resume(throwing: captureError)
                self.startContinuation = nil
                self.stopContinuation = nil
                self.removeCurrentOutput()
                return
            }

            self.currentOutputURL = outputFileURL
            self.startContinuation?.resume()
            self.stopContinuation?.resume(returning: outputFileURL)
            self.startContinuation = nil
            self.stopContinuation = nil
        }
    }
}
