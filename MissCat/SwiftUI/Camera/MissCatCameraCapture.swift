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

enum MissCatCameraAudioAccessState: Equatable, Sendable {
    case idle
    case requesting
    case available
    case silentDenied
    case silentUnavailable

    var recordsAudio: Bool { self == .available }

    var statusMessage: String? {
        switch self {
        case .idle:
            return nil
        case .requesting:
            return "マイクへのアクセスを確認中です。"
        case .available:
            return "音声付きで録画します。"
        case .silentDenied:
            return "マイクが許可されていないため、ビデオは無音で録画されます。"
        case .silentUnavailable:
            return "利用可能なマイクがないため、ビデオは無音で録画されます。"
        }
    }
}

struct MissCatCameraAudioPermissionFlow: Equatable, Sendable {
    private(set) var state: MissCatCameraAudioAccessState = .idle

    @discardableResult
    mutating func begin(
        status: AVAuthorizationStatus,
        hasAudioDevice: Bool
    ) -> Bool {
        switch status {
        case .notDetermined:
            state = .requesting
            return true
        case .authorized:
            state = hasAudioDevice ? .available : .silentUnavailable
        case .denied, .restricted:
            state = .silentDenied
        @unknown default:
            state = .silentDenied
        }
        return false
    }

    mutating func resolve(
        status: AVAuthorizationStatus,
        hasAudioDevice: Bool
    ) {
        _ = begin(status: status, hasAudioDevice: hasAudioDevice)
    }

    mutating func cancelRequest() {
        guard state == .requesting else { return }
        state = .idle
    }

    mutating func retry() {
        state = .idle
    }

    mutating func markAudioInputUnavailable() {
        state = .silentUnavailable
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
        .onChange(of: model.mode) { _, mode in
            model.modeChanged(to: mode)
        }
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

                        if model.mode == .movie,
                           let message = model.audioAccessState.statusMessage
                        {
                            VStack(spacing: 6) {
                                Text(message)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .accessibilityIdentifier("camera.capture.audio-status")
                                if model.audioAccessState == .silentDenied {
                                    HStack(spacing: 12) {
                                        if let settingsURL = URL(string: "app-settings:") {
                                            Button("設定を開く") { openURL(settingsURL) }
                                                .accessibilityIdentifier("camera.capture.audio-settings")
                                        }
                                        Button("再確認") { model.retryAudioPermission() }
                                            .accessibilityIdentifier("camera.capture.audio-retry")
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }
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
    @Published private(set) var audioAccessState: MissCatCameraAudioAccessState = .idle

    private let configuration: MissCatCameraConfiguration
    private var engine: MissCatCameraEngine?
    private var audioPermissionFlow = MissCatCameraAudioPermissionFlow()
    private var audioPreparationTask: Task<Void, Never>?
    private var audioPreparationGeneration = 0
    private var recordAfterAudioPreparation = false
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

        let engine = MissCatCameraEngine(
            device: device,
            allowsVideo: configuration.allowsVideo,
            onFrame: { [weak self] frame in
                self?.previewFrame = frame
            },
            onCapture: { [weak self] capture in
                self?.isCapturingPhoto = false
                self?.isRecording = false
                self?.capture = capture
            },
            onRecordingChange: { [weak self] isRecording in
                self?.isRecording = isRecording
            },
            onError: { [weak self] message in
                self?.isCapturingPhoto = false
                self?.isRecording = false
                self?.accessState = .failed(message)
            }
        )
        self.engine = engine
        await engine.start()
    }

    func modeChanged(to mode: MissCatCameraMode) {
        switch mode {
        case .photo:
            cancelAudioPreparation()
            audioPermissionFlow.cancelRequest()
            audioAccessState = audioPermissionFlow.state
        case .movie:
            prepareAudio(startRecording: false)
        }
    }

    func triggerCapture() {
        guard accessState == .ready else { return }
        switch mode {
        case .photo:
            guard !isCapturingPhoto else { return }
            isCapturingPhoto = true
            guard let engine else { return }
            Task { await engine.capturePhoto() }
        case .movie:
            if isRecording {
                guard let engine else { return }
                Task { await engine.stopRecording() }
            } else {
                prepareAudio(startRecording: true)
            }
        }
    }

    func retryAudioPermission() {
        cancelAudioPreparation()
        audioPermissionFlow.retry()
        audioAccessState = audioPermissionFlow.state
        guard mode == .movie else { return }
        prepareAudio(startRecording: false)
    }

    func cancel() {
        cancelAudioPreparation()
        audioPermissionFlow.cancelRequest()
        audioAccessState = audioPermissionFlow.state
        guard let engine else { return }
        Task { await engine.cancelRecording() }
    }

    func stop() {
        cancelAudioPreparation()
        let currentEngine = engine
        engine = nil
        started = false
        guard let currentEngine else { return }
        Task { await currentEngine.stop() }
    }

    private func prepareAudio(startRecording: Bool) {
        if startRecording { recordAfterAudioPreparation = true }
        guard audioPreparationTask == nil else { return }
        audioPreparationGeneration += 1
        let generation = audioPreparationGeneration
        audioPreparationTask = Task { [weak self] in
            await self?.prepareAudioAndOptionallyRecord(generation: generation)
        }
    }

    private func prepareAudioAndOptionallyRecord(generation: Int) async {
        defer {
            if generation == audioPreparationGeneration {
                audioPreparationTask = nil
                recordAfterAudioPreparation = false
            }
        }
        let initialStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let shouldRequest = audioPermissionFlow.begin(
            status: initialStatus,
            hasAudioDevice: AVCaptureDevice.default(for: .audio) != nil
        )
        audioAccessState = audioPermissionFlow.state

        if shouldRequest {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled, generation == audioPreparationGeneration else { return }
            audioPermissionFlow.resolve(
                status: AVCaptureDevice.authorizationStatus(for: .audio),
                hasAudioDevice: AVCaptureDevice.default(for: .audio) != nil
            )
            audioAccessState = audioPermissionFlow.state
        }

        guard recordAfterAudioPreparation,
              !Task.isCancelled,
              generation == audioPreparationGeneration,
              let engine
        else {
            return
        }
        let result = await engine.startRecording(includeAudio: audioAccessState.recordsAudio)
        guard !Task.isCancelled, generation == audioPreparationGeneration else {
            await engine.cancelRecording()
            return
        }
        if audioAccessState.recordsAudio, result.started, !result.recordsAudio {
            audioPermissionFlow.markAudioInputUnavailable()
            audioAccessState = audioPermissionFlow.state
        }
    }

    private func cancelAudioPreparation() {
        audioPreparationGeneration += 1
        audioPreparationTask?.cancel()
        audioPreparationTask = nil
        recordAfterAudioPreparation = false
    }
}

private struct MissCatCameraRecordingStart: Equatable, Sendable {
    let started: Bool
    let recordsAudio: Bool

    static let notStarted = MissCatCameraRecordingStart(started: false, recordsAudio: false)
}

private actor MissCatCameraEngine {
    private let session = AVCaptureSession()
    private let device: AVCaptureDevice
    private let allowsVideo: Bool
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoQueue = DispatchQueue(label: "misscat.camera.preview")
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var audioInput: AVCaptureDeviceInput?
    private var configured = false
    private var discardMovie = false

    private let onFrame: @MainActor @Sendable (CGImage) -> Void
    private let onCapture: @MainActor @Sendable (MissCatCameraCapture) -> Void
    private let onRecordingChange: @MainActor @Sendable (Bool) -> Void
    private let onError: @MainActor @Sendable (String) -> Void

    private lazy var captureDelegate = MissCatCameraCaptureDelegate(
        onFrame: { [weak self] frame in
            Task { await self?.receive(frame: frame) }
        },
        onPhoto: { [weak self] data, failed in
            Task { await self?.receivePhoto(data: data, failed: failed) }
        },
        onMovie: { [weak self] url, failed in
            Task { await self?.receiveMovie(url: url, failed: failed) }
        }
    )

    init(
        device: AVCaptureDevice,
        allowsVideo: Bool,
        onFrame: @escaping @MainActor @Sendable (CGImage) -> Void,
        onCapture: @escaping @MainActor @Sendable (MissCatCameraCapture) -> Void,
        onRecordingChange: @escaping @MainActor @Sendable (Bool) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) {
        self.device = device
        self.allowsVideo = allowsVideo
        self.onFrame = onFrame
        self.onCapture = onCapture
        self.onRecordingChange = onRecordingChange
        self.onError = onError
    }

    func start() async {
        do {
            if !configured { try configure() }
            guard !session.isRunning else { return }
            session.startRunning()
        } catch {
            await onError("カメラの準備に失敗しました。")
        }
    }

    func stop() {
        if movieOutput.isRecording {
            discardMovie = true
            movieOutput.stopRecording()
        }
        if session.isRunning { session.stopRunning() }
    }

    func capturePhoto() {
        guard configured else { return }
        applyCaptureRotation()
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.photoQualityPrioritization = .balanced
        photoOutput.capturePhoto(with: settings, delegate: captureDelegate)
    }

    func startRecording(includeAudio: Bool) async -> MissCatCameraRecordingStart {
        guard allowsVideo, configured, !movieOutput.isRecording else { return .notStarted }
        let recordsAudio = configureAudioInput(enabled: includeAudio)
        discardMovie = false
        applyCaptureRotation()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("misscat-camera-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        try? FileManager.default.removeItem(at: url)
        movieOutput.startRecording(to: url, recordingDelegate: captureDelegate)
        await onRecordingChange(true)
        return MissCatCameraRecordingStart(started: true, recordsAudio: recordsAudio)
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    func cancelRecording() {
        guard movieOutput.isRecording else { return }
        discardMovie = true
        movieOutput.stopRecording()
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        let videoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(videoInput) else { throw CameraError.configuration }
        session.addInput(videoInput)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.setSampleBufferDelegate(captureDelegate, queue: videoQueue)
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
            Task { await self?.applyRotation(angle) }
        }
        applyCaptureRotation()
        configured = true
    }

    private func configureAudioInput(enabled: Bool) -> Bool {
        if !enabled {
            guard let audioInput else { return false }
            session.beginConfiguration()
            session.removeInput(audioInput)
            session.commitConfiguration()
            self.audioInput = nil
            return false
        }
        if audioInput != nil { return movieOutput.connection(with: .audio) != nil }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let audioDevice = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: audioDevice)
        else {
            return false
        }
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        audioInput = input
        session.commitConfiguration()
        return movieOutput.connection(with: .audio) != nil
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

    private func receive(frame: CGImage) async {
        await onFrame(frame)
    }

    private func receivePhoto(data: Data?, failed: Bool) async {
        guard !failed,
              let data,
              let jpeg = MissCatCameraImageProcessor.normalizedJPEG(from: data)
        else {
            await onError("写真を保存できませんでした。")
            return
        }
        await onCapture(.photo(jpeg))
    }

    private func receiveMovie(url outputFileURL: URL, failed: Bool) async {
        defer { try? FileManager.default.removeItem(at: outputFileURL) }
        await onRecordingChange(false)
        guard !discardMovie else {
            discardMovie = false
            return
        }
        guard !failed,
              let data = try? Data(contentsOf: outputFileURL),
              !data.isEmpty
        else {
            await onError("ビデオを保存できませんでした。")
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
        await onCapture(.movie(data: data, previewData: previewData))
    }
}

private final class MissCatCameraCaptureDelegate: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCapturePhotoCaptureDelegate,
    AVCaptureFileOutputRecordingDelegate
{
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @Sendable (CGImage) -> Void
    private let onPhoto: @Sendable (Data?, Bool) -> Void
    private let onMovie: @Sendable (URL, Bool) -> Void

    init(
        onFrame: @escaping @Sendable (CGImage) -> Void,
        onPhoto: @escaping @Sendable (Data?, Bool) -> Void,
        onMovie: @escaping @Sendable (URL, Bool) -> Void
    ) {
        self.onFrame = onFrame
        self.onPhoto = onPhoto
        self.onMovie = onMovie
        super.init()
    }

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

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        onPhoto(error == nil ? photo.fileDataRepresentation() : nil, error != nil)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        onMovie(outputFileURL, error != nil)
    }
}
