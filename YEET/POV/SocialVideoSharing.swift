import AVFoundation
import AVKit
import Photos
import SwiftUI
import UIKit

struct ShareVideoContext: Equatable, Sendable {
    let result: DetectionResult
    let rank: Int?
    let candidateRank: Int?

    var rankCaption: String? {
        if let rank { return "#\(rank.formatted()) IN THE WORLD" }
        if let candidateRank { return "WOULD RANK #\(candidateRank.formatted())" }
        return nil
    }
}

enum SocialVideoExportError: LocalizedError {
    case missingVideo
    case couldNotCreateExporter
    case exportFailed(String)
    case photosDenied

    var errorDescription: String? {
        switch self {
        case .missingVideo:
            "The POV recording does not contain a video track."
        case .couldNotCreateExporter:
            "This device could not prepare the share video."
        case let .exportFailed(message):
            "The share video could not be created. \(message)"
        case .photosDenied:
            "Allow YEET to add videos to Photos, then try again."
        }
    }
}

final class BrandedVideoExporter: @unchecked Sendable {
    static let socialRenderSize = CGSize(width: 1080, height: 1920)

    func export(sourceURL: URL, context: ShareVideoContext) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoComposition = try await makeVideoComposition(asset: asset, context: context)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YEET-SHARE-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw SocialVideoExportError.couldNotCreateExporter
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.exportAsynchronously {
                    switch session.status {
                    case .completed:
                        continuation.resume(returning: outputURL)
                    case .cancelled:
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(throwing: CancellationError())
                    default:
                        try? FileManager.default.removeItem(at: outputURL)
                        continuation.resume(
                            throwing: SocialVideoExportError.exportFailed(
                                session.error?.localizedDescription ?? "Please try again."
                            )
                        )
                    }
                }
            }
        } onCancel: {
            session.cancelExport()
        }
    }

    func makeVideoComposition(
        asset: AVAsset,
        context: ShareVideoContext
    ) async throws -> AVMutableVideoComposition {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw SocialVideoExportError.missingVideo
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let renderSize = Self.socialRenderSize

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        var transform = preferredTransform
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        let scale = max(renderSize.width / orientedSize.width, renderSize.height / orientedSize.height)
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let scaledRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        transform.tx += (renderSize.width - scaledRect.width) / 2 - scaledRect.minX
        transform.ty += (renderSize.height - scaledRect.height) / 2 - scaledRect.minY
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)
        addBrandLayers(to: parentLayer, size: renderSize, context: context)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        return videoComposition
    }

    private func addBrandLayers(
        to parent: CALayer,
        size: CGSize,
        context: ShareVideoContext
    ) {
        let gradient = CAGradientLayer()
        gradient.frame = parent.bounds
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.62).cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.82).cgColor
        ]
        gradient.locations = [0, 0.48, 1]
        parent.addSublayer(gradient)

        addText(
            "I YEETED\nMY PHONE",
            frame: CGRect(x: 80, y: 1390, width: 920, height: 300),
            fontSize: 92,
            color: .white,
            alignment: .center,
            to: parent
        )
        addText(
            context.result.airtime.formatted(.number.precision(.fractionLength(2))) + "s",
            frame: CGRect(x: 80, y: 1010, width: 920, height: 300),
            fontSize: 210,
            color: UIColor(red: 1, green: 0.82, blue: 0.03, alpha: 1),
            alignment: .center,
            to: parent
        )
        if let rankCaption = context.rankCaption {
            addText(
                rankCaption,
                frame: CGRect(x: 80, y: 930, width: 920, height: 80),
                fontSize: 42,
                color: .white,
                alignment: .center,
                to: parent
            )
        }
        addText(
            "YEET",
            frame: CGRect(x: 720, y: 90, width: 280, height: 100),
            fontSize: 64,
            color: .white,
            alignment: .right,
            to: parent
        )
    }

    private func addText(
        _ value: String,
        frame: CGRect,
        fontSize: CGFloat,
        color: UIColor,
        alignment: CATextLayerAlignmentMode,
        to parent: CALayer
    ) {
        let layer = CATextLayer()
        layer.contentsScale = 3
        layer.frame = frame
        layer.string = value
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = alignment
        layer.isWrapped = true
        layer.font = UIFont.systemFont(ofSize: fontSize, weight: .black)
        layer.fontSize = fontSize
        parent.addSublayer(layer)
    }
}

@MainActor
final class SocialVideoExportModel: ObservableObject {
    enum State: Equatable {
        case idle
        case exporting
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var confirmation: String?

    private let exporter = BrandedVideoExporter()
    private var task: Task<Void, Never>?
    private var outputURL: URL?

    deinit {
        task?.cancel()
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    }

    func start(sourceURL: URL, context: ShareVideoContext) {
        guard state == .idle || state.isFailure else { return }
        confirmation = nil
        state = .exporting
        task?.cancel()
        task = Task { [weak self, exporter] in
            do {
                let url = try await exporter.export(sourceURL: sourceURL, context: context)
                guard !Task.isCancelled, let self else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                outputURL = url
                state = .ready(url)
            } catch is CancellationError {
                self?.state = .idle
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelAndCleanUp() {
        task?.cancel()
        task = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        state = .idle
    }

    func saveToPhotos(_ url: URL) async {
        confirmation = nil
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            state = .failed(SocialVideoExportError.photosDenied.localizedDescription)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            confirmation = "SAVED TO PHOTOS"
        } catch {
            state = .failed("Couldn’t save the video. \(error.localizedDescription)")
        }
    }
}

private extension SocialVideoExportModel.State {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct SocialShareView: View {
    let sourceURL: URL
    let context: ShareVideoContext
    let onDone: () -> Void

    @StateObject private var model = SocialVideoExportModel()
    @State private var isSharePresented = false
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .onAppear { model.start(sourceURL: sourceURL, context: context) }
        .onDisappear {
            player?.pause()
            model.cancelAndCleanUp()
        }
        .onChange(of: model.state) { _, state in
            if case let .ready(url) = state {
                let player = AVPlayer(url: url)
                player.actionAtItemEnd = .none
                self.player = player
                player.play()
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if case let .ready(url) = model.state {
                ActivityShareSheet(url: url) { completed in
                    if completed { model.confirmation = "SHARED" }
                }
            }
        }
        .accessibilityIdentifier("yeet.share.preview")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .exporting:
            VStack(spacing: 18) {
                ProgressView().tint(YEETTheme.yellow).scaleEffect(1.3)
                Text("CREATING YOUR YEET…")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Button("CANCEL", action: onDone)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.8))
            }

        case let .failed(message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(YEETTheme.yellow)
                Text("SHARE VIDEO FAILED").font(.headline.weight(.black))
                Text(message).font(.caption).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.72))
                Button("TRY AGAIN") { model.start(sourceURL: sourceURL, context: context) }
                    .buttonStyle(SocialActionButtonStyle(isPrimary: true))
                Button("DONE", action: onDone)
                    .buttonStyle(SocialActionButtonStyle(isPrimary: false))
            }
            .foregroundStyle(.white)
            .padding(24)

        case let .ready(url):
            VStack(spacing: 0) {
                HStack {
                    Button("DONE", action: onDone)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("SHARE").font(.headline.weight(.black)).foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 48, height: 1)
                }
                .padding(20)

                if let player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.horizontal, 20)
                }

                if let confirmation = model.confirmation {
                    Text(confirmation)
                        .font(.caption.weight(.black))
                        .foregroundStyle(YEETTheme.yellow)
                        .padding(.top, 12)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await model.saveToPhotos(url) }
                    } label: {
                        Label("SAVE", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(SocialActionButtonStyle(isPrimary: false))

                    Button {
                        isSharePresented = true
                    } label: {
                        Label("SHARE", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SocialActionButtonStyle(isPrimary: true))
                }
                .padding(20)
            }
        }
    }
}

private struct SocialActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.black))
            .foregroundStyle(isPrimary ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isPrimary ? YEETTheme.yellow : Color.white.opacity(0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
