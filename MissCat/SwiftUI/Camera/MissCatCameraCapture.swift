import AVFoundation
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum MissCatCameraAccessState: Equatable {
    case idle
    case requesting
    case ready
    case denied
    case unavailable
    case failed(String)
}

enum MissCatCameraAccessPolicy {
    static var hasVideoDevice: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static func state(
        for status: AVAuthorizationStatus,
        hasVideoDevice: Bool
    ) -> MissCatCameraAccessState {
        switch status {
        case .notDetermined:
            return .requesting
        case .restricted, .denied:
            return .denied
        case .authorized:
            return hasVideoDevice ? .ready : .unavailable
        @unknown default:
            return .denied
        }
    }
}

struct MissCatCameraConfiguration: Equatable, Sendable {
    let allowsVideo: Bool

    static let compose = MissCatCameraConfiguration(allowsVideo: true)
    static let profile = MissCatCameraConfiguration(allowsVideo: false)
}

struct MissCatCameraCapture: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case photo
        case movie
    }

    let kind: Kind
    let data: Data
    let previewData: Data
    let pathExtension: String
    let mimeType: String

    static func photo(_ data: Data) -> MissCatCameraCapture {
        MissCatCameraCapture(
            kind: .photo,
            data: data,
            previewData: data,
            pathExtension: "jpg",
            mimeType: "image/jpeg"
        )
    }

    static func movie(data: Data, previewData: Data) -> MissCatCameraCapture {
        MissCatCameraCapture(
            kind: .movie,
            data: data,
            previewData: previewData,
            pathExtension: "mov",
            mimeType: "video/quicktime"
        )
    }
}

enum MissCatProfileImageTarget: Equatable, Sendable {
    case avatar
    case banner
}

enum MissCatCameraImageProcessor {
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpegData(from image: CGImage, compressionQuality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func normalizedJPEG(from data: Data, compressionQuality: CGFloat = 0.95) -> Data? {
        guard let image = decode(data) else { return nil }
        return jpegData(from: image, compressionQuality: compressionQuality)
    }

    static func profileJPEG(
        from data: Data,
        target: MissCatProfileImageTarget
    ) -> Data? {
        guard let image = decode(data) else { return nil }
        let output: CGImage
        switch target {
        case .banner:
            output = image
        case .avatar:
            let side = min(image.width, image.height)
            let crop = CGRect(
                x: (image.width - side) / 2,
                y: (image.height - side) / 2,
                width: side,
                height: side
            )
            guard let square = image.cropping(to: crop) else { return nil }
            output = square
        }
        return jpegData(from: output, compressionQuality: 0.9)
    }
}

struct MissCatCameraCaptureView: View {
    let configuration: MissCatCameraConfiguration
    let onCapture: (MissCatCameraCapture) -> Void
    let onCancel: () -> Void

    @StateObject private var model: MissCatCameraCaptureModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(
        configuration: MissCatCameraConfiguration,
        onCapture: @escaping (MissCatCameraCapture) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.configuration = configuration
        self.onCapture = onCapture
        self.onCancel = onCancel
        _model = StateObject(
            wrappedValue: MissCatCameraCaptureModel(configuration: configuration)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.capture) { _, capture in
            guard let capture else { return }
            onCapture(capture)
        }
        .accessibilityIdentifier("camera.capture.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch model.accessState {
        case .idle, .requesting:
            ProgressView("カメラを準備中")
                .tint(.white)
                .accessibilityIdentifier("camera.capture.loading")
        case .denied:
            stateMessage(
                symbol: "camera.fill",
                title: "カメラへのアクセスがありません",
                message: "設定でMissCatのカメラアクセスを許可してください。",
                settingsButton: true
            )
        case .unavailable:
            stateMessage(
                symbol: "camera.slash",
                title: "カメラを利用できません",
                message: "この端末では利用可能なカメラが見つかりませんでした。"
            )
        case let .failed(message):
            stateMessage(
                symbol: "exclamationmark.triangle",
                title: "カメラを起動できません",
                message: message
            )
        case .ready:
            cameraContent
        }
    }

    private var cameraContent: some View {
        GeometryReader { proxy in
            ZStack {
                if let frame = model.previewFrame {
                    Image(decorative: frame, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .accessibilityIdentifier("camera.capture.preview")
                } else {
                    ProgressView()
                        .tint(.white)
                }

                VStack {
                    HStack {
                        Button(action: cancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .accessibilityLabel("キャンセル")
                        .accessibilityIdentifier("camera.capture.cancel")
                        Spacer()
                    }
                    .padding()

                    Spacer()

                    if configuration.allowsVideo {
                        Picker("撮影モード", selection: $model.mode) {
                            Text("写真").tag(MissCatCameraMode.photo)
                            Text("ビデオ").tag(MissCatCameraMode.movie)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 210)
                        .colorScheme(.dark)
                        .disabled(model.isRecording)
                        .accessibilityIdentifier("camera.capture.mode")
                    }

                    Button(action: model.triggerCapture) {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 5)
                                .frame(width: 76, height: 76)
                            if model.mode == .movie {
                                RoundedRectangle(cornerRadius: model.isRecording ? 5 : 29)
                                    .fill(.red)
                                    .frame(
                                        width: model.isRecording ? 30 : 58,
                                        height: model.isRecording ? 30 : 58
                                    )
                            } else {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 62, height: 62)
                            }
                        }
                    }
                    .disabled(model.isCapturingPhoto)
                    .accessibilityLabel(model.captureButtonLabel)
                    .accessibilityIdentifier("camera.capture.shutter")
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private func stateMessage(
        symbol: String,
        title: String,
        message: String,
        settingsButton: Bool = false
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 46))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if settingsButton, let settingsURL = URL(string: "app-settings:") {
                Button("設定を開く") { openURL(settingsURL) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("camera.capture.settings")
            }
            Button("閉じる", action: cancel)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("camera.capture.close")
        }
        .padding(28)
    }

    private func cancel() {
        model.cancel()
        onCancel()
        dismiss()
    }
}

enum MissCatCameraMode: Equatable, Sendable {
    case photo
    case movie
}

@MainActor
private final class MissCatCameraCaptureModel: ObservableObject {
    @Published var accessState: MissCatCameraAccessState = .idle
    @Published var previewFrame: CGImage?
    @Published var mode: MissCatCameraMode = .photo
    @Published var isCapturingPhoto = false
    @Published var isRecording = false
    @Published var capture: MissCatCameraCapture?

    private let configuration: MissCatCameraConfiguration
    private var engine: MissCatCameraEngine?
    private var started = false

    init(configuration: MissCatCameraConfiguration) {
        self.configuration = configuration
    }

    var captureButtonLabel: String {
        switch mode {
        case .photo:
            return "写真を撮る"
        case .movie:
            return isRecording ? "録画を停止" : "録画を開始"
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        accessState = .requesting

        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
        let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        )
        accessState = MissCatCameraAccessPolicy.state(
            for: status,
            hasVideoDevice: device != nil
        )
        guard accessState == .ready, let device else { return }

        if configuration.allowsVideo,
           AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
        {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        let engine = MissCatCameraEngine(
            device: device,
            allowsVideo: configuration.allowsVideo,
            onFrame: { [weak self] frame in
                DispatchQueue.main.async { self?.previewFrame = frame }
            },
            onCapture: { [weak self] capture in
                DispatchQueue.main.async {
                    self?.isCapturingPhoto = false
                    self?.isRecording = false
                    self?.capture = capture
                }
            },
            onRecordingChange: { [weak self] isRecording in
                DispatchQueue.main.async { self?.isRecording = isRecording }
            },
            onError: { [weak self] message in
                DispatchQueue.main.async {
                    self?.isCapturingPhoto = false
                    self?.isRecording = false
                    self?.accessState = .failed(message)
                }
            }
        )
        self.engine = engine
        engine.start()
    }

    func triggerCapture() {
        guard accessState == .ready else { return }
        switch mode {
        case .photo:
            guard !isCapturingPhoto else { return }
            isCapturingPhoto = true
            engine?.capturePhoto()
        case .movie:
            if isRecording {
                engine?.stopRecording()
            } else {
                engine?.startRecording()
            }
        }
    }

    func cancel() {
        engine?.cancelRecording()
    }

    func stop() {
        engine?.stop()
        engine = nil
        started = false
    }
}

private final class MissCatCameraEngine: NSObject {
    private let session = AVCaptureSession()
    private let device: AVCaptureDevice
    private let allowsVideo: Bool
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "misscat.camera.session")
    private let videoQueue = DispatchQueue(label: "misscat.camera.preview")
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var configured = false
    private var discardMovie = false

    private let onFrame: (CGImage) -> Void
    private let onCapture: (MissCatCameraCapture) -> Void
    private let onRecordingChange: (Bool) -> Void
    private let onError: (String) -> Void

    init(
        device: AVCaptureDevice,
        allowsVideo: Bool,
        onFrame: @escaping (CGImage) -> Void,
        onCapture: @escaping (MissCatCameraCapture) -> Void,
        onRecordingChange: @escaping (Bool) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.device = device
        self.allowsVideo = allowsVideo
        self.onFrame = onFrame
        self.onCapture = onCapture
        self.onRecordingChange = onRecordingChange
        self.onError = onError
        super.init()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !configured { try configure() }
                guard !session.isRunning else { return }
                session.startRunning()
            } catch {
                onError("カメラの準備に失敗しました。")
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if movieOutput.isRecording {
                discardMovie = true
                movieOutput.stopRecording()
            }
            if session.isRunning { session.stopRunning() }
        }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self, configured else { return }
            applyCaptureRotation()
            let settings: AVCapturePhotoSettings
            if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.photoQualityPrioritization = .balanced
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording() {
        guard allowsVideo else { return }
        sessionQueue.async { [weak self] in
            guard let self, configured, !movieOutput.isRecording else { return }
            discardMovie = false
            applyCaptureRotation()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("misscat-camera-\(UUID().uuidString)")
                .appendingPathExtension("mov")
            try? FileManager.default.removeItem(at: url)
            movieOutput.startRecording(to: url, recordingDelegate: self)
            onRecordingChange(true)
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, movieOutput.isRecording else { return }
            movieOutput.stopRecording()
        }
    }

    func cancelRecording() {
        sessionQueue.async { [weak self] in
            guard let self, movieOutput.isRecording else { return }
            discardMovie = true
            movieOutput.stopRecording()
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        let videoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(videoInput) else { throw CameraError.configuration }
        session.addInput(videoInput)

        if allowsVideo,
           AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput)
        {
            session.addInput(audioInput)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.configuration }
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else { throw CameraError.configuration }
        session.addOutput(photoOutput)

        if allowsVideo {
            guard session.canAddOutput(movieOutput) else { throw CameraError.configuration }
            session.addOutput(movieOutput)
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let angle = change.newValue else { return }
            self?.sessionQueue.async { [weak self] in self?.applyRotation(angle) }
        }
        applyCaptureRotation()
        configured = true
    }

    private func applyCaptureRotation() {
        applyRotation(rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0)
    }

    private func applyRotation(_ angle: CGFloat) {
        let connections = [
            videoOutput.connection(with: .video),
            photoOutput.connection(with: .video),
            allowsVideo ? movieOutput.connection(with: .video) : nil,
        ]
        for connection in connections.compactMap({ $0 })
            where connection.isVideoRotationAngleSupported(angle)
        {
            connection.videoRotationAngle = angle
        }
    }

    private enum CameraError: Error {
        case configuration
    }
}

extension MissCatCameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let frame = imageContext.createCGImage(image, from: image.extent) else { return }
        onFrame(frame)
    }
}

extension MissCatCameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let jpeg = MissCatCameraImageProcessor.normalizedJPEG(from: data)
        else {
            onError("写真を保存できませんでした。")
            return
        }
        onCapture(.photo(jpeg))
    }
}

extension MissCatCameraEngine: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        defer { try? FileManager.default.removeItem(at: outputFileURL) }
        onRecordingChange(false)
        guard !discardMovie else {
            discardMovie = false
            return
        }
        guard error == nil,
              let data = try? Data(contentsOf: outputFileURL),
              !data.isEmpty
        else {
            onError("ビデオを保存できませんでした。")
            return
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: outputFileURL))
        generator.appliesPreferredTrackTransform = true
        let previewData: Data
        if let image = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            previewData = MissCatCameraImageProcessor.jpegData(
                from: image,
                compressionQuality: 0.75
            ) ?? Data()
        } else {
            previewData = Data()
        }
        onCapture(.movie(data: data, previewData: previewData))
    }
}
