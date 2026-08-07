@testable import MissCat
import AVFoundation
import CoreGraphics
import Foundation
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
        XCTAssertTrue(compose.contains("PhotosPicker("))
        XCTAssertTrue(profile.contains("PhotosPicker("))
        XCTAssertTrue(compose.contains("MissCatCameraCaptureView"))
        XCTAssertTrue(profile.contains("MissCatCameraCaptureView"))
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
