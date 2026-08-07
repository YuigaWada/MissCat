@testable import MissCat
import AVFoundation
import CoreGraphics
import Foundation
import Observation
import XCTest

final class MissCatCameraCaptureTests: XCTestCase {
    func testAccessStateDistinguishesRequestingDeniedUnavailableAndReady() {
        XCTAssertEqual(
            MissCatCameraAccessPolicy.state(for: .notDetermined, hasVideoDevice: true),
            .requesting
        )
        XCTAssertEqual(
            MissCatCameraAccessPolicy.state(for: .denied, hasVideoDevice: true),
            .denied
        )
        XCTAssertEqual(
            MissCatCameraAccessPolicy.state(for: .restricted, hasVideoDevice: true),
            .denied
        )
        XCTAssertEqual(
            MissCatCameraAccessPolicy.state(for: .authorized, hasVideoDevice: false),
            .unavailable
        )
        XCTAssertEqual(
            MissCatCameraAccessPolicy.state(for: .authorized, hasVideoDevice: true),
            .ready
        )
    }

    func testCaptureResultPreservesPhotoAndMovieAttachmentContracts() {
        let photo = MissCatCameraCapture.photo(Data([1, 2, 3]))
        XCTAssertEqual(photo.kind, .photo)
        XCTAssertEqual(photo.data, Data([1, 2, 3]))
        XCTAssertEqual(photo.previewData, Data([1, 2, 3]))
        XCTAssertEqual(photo.pathExtension, "jpg")
        XCTAssertEqual(photo.mimeType, "image/jpeg")

        let movie = MissCatCameraCapture.movie(
            data: Data([4, 5, 6]),
            previewData: Data([7, 8])
        )
        XCTAssertEqual(movie.kind, .movie)
        XCTAssertEqual(movie.data, Data([4, 5, 6]))
        XCTAssertEqual(movie.previewData, Data([7, 8]))
        XCTAssertEqual(movie.pathExtension, "mov")
        XCTAssertEqual(movie.mimeType, "video/quicktime")
        XCTAssertFalse(MissCatCameraConfiguration.profile.allowsVideo)
        XCTAssertTrue(MissCatCameraConfiguration.compose.allowsVideo)
    }

    func testAudioPermissionFlowDoesNotRequestWhenAlreadyResolved() {
        var available = MissCatCameraAudioPermissionFlow()
        XCTAssertFalse(available.begin(status: .authorized, hasAudioDevice: true))
        XCTAssertEqual(available.state, .available)
        XCTAssertTrue(available.state.recordsAudio)

        var denied = MissCatCameraAudioPermissionFlow()
        XCTAssertFalse(denied.begin(status: .denied, hasAudioDevice: true))
        XCTAssertEqual(denied.state, .silentDenied)
        XCTAssertFalse(denied.state.recordsAudio)
        XCTAssertEqual(
            denied.state.statusMessage,
            "マイクが許可されていないため、ビデオは無音で録画されます。"
        )

        var unavailable = MissCatCameraAudioPermissionFlow()
        XCTAssertFalse(unavailable.begin(status: .authorized, hasAudioDevice: false))
        XCTAssertEqual(unavailable.state, .silentUnavailable)
        XCTAssertFalse(unavailable.state.recordsAudio)
    }

    func testAudioPermissionRequestCanBeCancelledAndRetried() {
        var flow = MissCatCameraAudioPermissionFlow()

        XCTAssertTrue(flow.begin(status: .notDetermined, hasAudioDevice: true))
        XCTAssertEqual(flow.state, .requesting)

        flow.cancelRequest()
        XCTAssertEqual(flow.state, .idle)

        XCTAssertTrue(flow.begin(status: .notDetermined, hasAudioDevice: true))
        flow.resolve(status: .denied, hasAudioDevice: true)
        XCTAssertEqual(flow.state, .silentDenied)

        flow.retry()
        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.begin(status: .authorized, hasAudioDevice: true))
        XCTAssertEqual(flow.state, .available)
    }

    @MainActor
    func testObservationTracksCameraPermissionAndCaptureState() async {
        let model = MissCatCameraCaptureModel(configuration: .profile)
        let accessChanged = expectation(description: "Observation reports camera access mutation")

        withObservationTracking {
            _ = model.accessState
        } onChange: {
            accessChanged.fulfill()
        }
        model.applyAccessState(.ready)
        await fulfillment(of: [accessChanged], timeout: 1)
        XCTAssertEqual(model.accessState, .ready)

        let captureChanged = expectation(description: "Observation reports camera capture mutation")
        withObservationTracking {
            _ = model.capture
        } onChange: {
            captureChanged.fulfill()
        }
        let photo = MissCatCameraCapture.photo(Data([9, 8, 7]))
        model.receiveCapture(photo)
        await fulfillment(of: [captureChanged], timeout: 1)
        XCTAssertEqual(model.capture, photo)
        XCTAssertFalse(model.isCapturingPhoto)
        XCTAssertFalse(model.isRecording)
    }

    @MainActor
    func testInjectedCameraModelIsRetainedOnlyForViewLifetime() {
        var model: MissCatCameraCaptureModel? = MissCatCameraCaptureModel(configuration: .profile)
        weak var retainedModel = model
        var screen: MissCatCameraCaptureView? = MissCatCameraCaptureView(
            configuration: .profile,
            onCapture: { _ in },
            model: model!
        )

        model = nil
        XCTAssertNotNil(retainedModel)

        screen = nil
        XCTAssertNil(retainedModel)
    }

    func testProfileAvatarProcessingProducesOrientedSquareJPEG() throws {
        let source = try XCTUnwrap(makeJPEG(width: 12, height: 8))
        let avatar = try XCTUnwrap(
            MissCatCameraImageProcessor.profileJPEG(from: source, target: .avatar)
        )
        let banner = try XCTUnwrap(
            MissCatCameraImageProcessor.profileJPEG(from: source, target: .banner)
        )
        let avatarImage = try XCTUnwrap(MissCatCameraImageProcessor.decode(avatar))
        let bannerImage = try XCTUnwrap(MissCatCameraImageProcessor.decode(banner))

        XCTAssertEqual(avatarImage.width, avatarImage.height)
        XCTAssertEqual(bannerImage.width, 12)
        XCTAssertEqual(bannerImage.height, 8)
    }

    func testShippingCameraBoundaryUsesSwiftUIFramesAndAVFoundationOutputs() throws {
        let camera = try source(named: "MissCat/SwiftUI/Camera/MissCatCameraCapture.swift")
        let compose = try source(named: "MissCat/SwiftUI/Compose/MissCatComposeMediaViews.swift")
        let profile = try source(named: "MissCat/SwiftUI/Profile/MissCatProfileViews.swift")

        for value in [camera, compose, profile] {
            XCTAssertFalse(value.contains("import UIKit"))
            XCTAssertFalse(value.contains("UIImage"))
            XCTAssertFalse(value.contains("UIViewControllerRepresentable"))
            XCTAssertFalse(value.contains("UIViewRepresentable"))
        }
        XCTAssertTrue(camera.contains("import AVFoundation"))
        XCTAssertTrue(camera.contains("AVCaptureSession"))
        XCTAssertTrue(camera.contains("AVCaptureVideoDataOutput"))
        XCTAssertTrue(camera.contains("AVCapturePhotoOutput"))
        XCTAssertTrue(camera.contains("AVCaptureMovieFileOutput"))
        XCTAssertTrue(camera.contains("CGImage"))
        XCTAssertTrue(camera.contains("videoRotationAngle"))
        XCTAssertTrue(camera.contains("private actor MissCatCameraEngine"))
        XCTAssertFalse(camera.contains("@unchecked Sendable"))
        XCTAssertFalse(camera.contains("sessionQueue.async"))
        XCTAssertTrue(camera.contains("camera.capture.audio-status"))
        XCTAssertTrue(camera.contains("ビデオは無音で録画されます"))

        let initialStart = try XCTUnwrap(
            camera.range(of: "func start() async")?.lowerBound
        )
        let modeChange = try XCTUnwrap(
            camera.range(of: "func modeChanged", range: initialStart..<camera.endIndex)?.lowerBound
        )
        let initialCameraStart = String(camera[initialStart..<modeChange])
        XCTAssertFalse(initialCameraStart.contains("requestAccess(for: .audio)"))

        XCTAssertTrue(compose.contains("PhotosPicker("))
        XCTAssertTrue(profile.contains("PhotosPicker("))
        XCTAssertTrue(compose.contains("MissCatCameraCaptureView"))
        XCTAssertTrue(profile.contains("MissCatCameraCaptureView"))
    }

    func testProfileDiscoveryAndCameraStateOwnersUseObservationOnly() throws {
        let sources = try [
            source(named: "MissCat/SwiftUI/Profile/MissCatProfileCore.swift"),
            source(named: "MissCat/SwiftUI/Profile/MissCatProfileViews.swift"),
            source(named: "MissCat/SwiftUI/Discovery/MissCatDiscoveryCore.swift"),
            source(named: "MissCat/SwiftUI/Discovery/MissCatDiscoveryViews.swift"),
            source(named: "MissCat/SwiftUI/Camera/MissCatCameraCapture.swift"),
        ]
        let combined = sources.joined(separator: "\n")

        XCTAssertTrue(combined.contains("import Observation"))
        XCTAssertTrue(combined.contains("@Observable"))
        for legacy in ["import Combine", "ObservableObject", "@Published", "@StateObject", "@ObservedObject"] {
            XCTAssertFalse(combined.contains(legacy), "Found legacy state owner: \(legacy)")
        }
        XCTAssertTrue(combined.contains("@State private var store: MissCatProfileStore"))
        XCTAssertTrue(combined.contains("@State private var store: MissCatDiscoveryStore"))
        XCTAssertTrue(combined.contains("@State private var model: MissCatCameraCaptureModel"))
        XCTAssertTrue(combined.contains("@Bindable var store = store"))
        XCTAssertTrue(combined.contains("@Bindable var model = model"))
    }

    private func makeJPEG(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        return MissCatCameraImageProcessor.jpegData(from: image, compressionQuality: 0.95)
    }

    private func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
