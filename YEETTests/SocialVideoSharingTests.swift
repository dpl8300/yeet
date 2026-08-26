import AVFoundation
import XCTest
@testable import YEET

final class SocialVideoSharingTests: XCTestCase {
    func testShareContextDistinguishesSavedAndHypotheticalRanks() {
        XCTAssertEqual(context(rank: 12, candidateRank: 4).rankCaption, "#12 IN THE WORLD")
        XCTAssertEqual(context(rank: nil, candidateRank: 4).rankCaption, "WOULD RANK #4")
        XCTAssertNil(context(rank: nil, candidateRank: nil).rankCaption)
    }

    func testExporterBuildsPortraitSocialComposition() async throws {
        let sourceURL = try await makeTestVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let composition = try await BrandedVideoExporter().makeVideoComposition(
            asset: AVURLAsset(url: sourceURL),
            context: context(rank: 42, candidateRank: nil)
        )
        XCTAssertEqual(composition.renderSize.width, 1080, accuracy: 1)
        XCTAssertEqual(composition.renderSize.height, 1920, accuracy: 1)
        XCTAssertEqual(composition.frameDuration, CMTime(value: 1, timescale: 30))
        XCTAssertEqual(composition.instructions.count, 1)
        XCTAssertNotNil(composition.animationTool)
    }

    private func context(rank: Int?, candidateRank: Int?) -> ShareVideoContext {
        ShareVideoContext(
            result: DetectionResult(
                airborneStartTimestamp: 1,
                landingTimestamp: 2.62,
                airtime: 1.62,
                preflightPeakAcceleration: 1.8,
                impactPeakAcceleration: 2.2,
                airborneSampleCount: 162
            ),
            rank: rank,
            candidateRank: candidateRank
        )
    }

    private func makeTestVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("YEET-Exporter-Test-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 320,
                AVVideoHeightKey: 480
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 480
            ]
        )
        guard writer.canAdd(input) else { throw SocialVideoExportError.couldNotCreateExporter }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? SocialVideoExportError.couldNotCreateExporter
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<6 {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool else {
                throw SocialVideoExportError.couldNotCreateExporter
            }
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, Int32(40 + frame * 24), CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(
                adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
            )
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? SocialVideoExportError.couldNotCreateExporter
        }
        return url
    }
}
