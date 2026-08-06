import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MissCatMediaPickerView: View {
    let existingMedia: [MissCatComposeMedia]
    let onLoaded: ([MissCatComposeMedia]) -> Void
    @State private var selection: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("画像または動画を選択")
                    .font(.headline)
                Text("画像は4枚まで、動画は1件のみ追加できます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                PhotosPicker(
                    selection: $selection,
                    maxSelectionCount: max(1, MissCatComposeSubmissionBuilder.maximumMediaCount - existingMedia.count),
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("写真ライブラリを開く", systemImage: "photo.stack")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("compose.media.library")

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    NavigationLink {
                        MissCatCameraPicker { item in
                            onLoaded([item])
                            dismiss()
                        }
                        .ignoresSafeArea()
                    } label: {
                        Label("カメラを開く", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("compose.media.camera")
                }

                if isLoading {
                    ProgressView("読み込み中")
                        .accessibilityIdentifier("compose.media.loading")
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("メディア")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onChange(of: selection) { _, newSelection in
                guard !newSelection.isEmpty else { return }
                Task { await load(newSelection) }
            }
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("閉じる") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .accessibilityIdentifier("compose.media.picker")
    }

    @MainActor
    private func load(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }
        do {
            var loaded: [MissCatComposeMedia] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                    throw PickerError.unreadable
                }
                let type = item.supportedContentTypes.first
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                loaded.append(
                    MissCatComposeMedia(
                        kind: isVideo ? .video : .image,
                        data: data,
                        previewData: isVideo ? Data() : data,
                        filename: UUID().uuidString + "." + (type?.preferredFilenameExtension ?? (isVideo ? "mp4" : "jpg")),
                        mimeType: type?.preferredMIMEType ?? (isVideo ? "video/mp4" : "image/jpeg")
                    )
                )
            }
            onLoaded(loaded)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            selection = []
        }
    }

    private enum PickerError: LocalizedError {
        case unreadable
        var errorDescription: String? { "選択したメディアを読み込めませんでした" }
    }
}

/// UIImagePickerController is retained only for the system camera, which has
/// no native SwiftUI equivalent on iOS 17. All composer-owned surfaces remain
/// SwiftUI views.
struct MissCatCameraPicker: UIViewControllerRepresentable {
    let onPicked: (MissCatComposeMedia) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onPicked: (MissCatComposeMedia) -> Void

        init(onPicked: @escaping (MissCatComposeMedia) -> Void) {
            self.onPicked = onPicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { picker.dismiss(animated: true) }
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.95)
            {
                onPicked(
                    MissCatComposeMedia(
                        kind: .image,
                        data: data,
                        filename: UUID().uuidString + ".jpeg",
                        mimeType: "image/jpeg"
                    )
                )
                return
            }
            if let url = info[.mediaURL] as? URL,
               let data = try? Data(contentsOf: url),
               !data.isEmpty
            {
                onPicked(
                    MissCatComposeMedia(
                        kind: .video,
                        data: data,
                        previewData: Self.videoThumbnailData(url: url),
                        filename: UUID().uuidString + ".mov",
                        mimeType: "video/quicktime"
                    )
                )
            }
        }

        private static func videoThumbnailData(url: URL) -> Data {
            let generator = AVAssetImageGenerator(asset: AVAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return Data() }
            return UIImage(cgImage: image).jpegData(compressionQuality: 0.75) ?? Data()
        }
    }
}

struct MissCatMediaEditorView: View {
    let media: MissCatComposeMedia
    let onSave: (Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var rotation = Angle.zero
    @State private var isMirrored = false
    @State private var editMode = EditMode.transform
    @State private var strokes: [MarkupStroke] = []
    @State private var activeStroke: MarkupStroke?
    @State private var strokeColor = Color.red
    @State private var overlayText = ""
    @State private var canvasSize = CGSize(width: 320, height: 320)
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { proxy in
                    editorCanvas
                        .onAppear { canvasSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in canvasSize = newSize }
                }
                .aspectRatio(1, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 12)

                Picker("編集モード", selection: $editMode) {
                    Label("切り抜き", systemImage: "crop").tag(EditMode.transform)
                    Label("描画", systemImage: "pencil.tip").tag(EditMode.draw)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .accessibilityIdentifier("compose.media.editor.mode")

                if editMode == .transform {
                    transformControls
                } else {
                    markupControls
                }

                TextField("画像に追加するテキスト", text: $overlayText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("compose.media.editor.text")
            }
            .padding(.vertical, 8)
            .navigationTitle("画像を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { save() }
                        .accessibilityIdentifier("compose.media.editor.done")
                }
            }
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("閉じる") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .accessibilityIdentifier("compose.media.editor")
    }

    @ViewBuilder
    private var editorCanvas: some View {
        if editMode == .draw {
            canvasContent
                .contentShape(Rectangle())
                .gesture(drawingGesture)
        } else {
            canvasContent
                .contentShape(Rectangle())
                .gesture(transformGesture)
                .simultaneousGesture(magnificationGesture)
        }
    }

    private var canvasContent: some View {
        MissCatEditableMediaCanvas(
            imageData: media.data,
            zoom: zoom,
            offset: offset,
            rotation: rotation,
            isMirrored: isMirrored,
            strokes: activeStroke.map { strokes + [$0] } ?? strokes,
            overlayText: overlayText
        )
    }

    private var transformControls: some View {
        HStack(spacing: 28) {
            Button {
                rotation += .degrees(90)
            } label: {
                Label("回転", systemImage: "rotate.right")
            }
            Button {
                isMirrored.toggle()
            } label: {
                Label("反転", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            Button {
                zoom = 1
                baseZoom = 1
                offset = .zero
                baseOffset = .zero
                rotation = .zero
                isMirrored = false
            } label: {
                Label("リセット", systemImage: "arrow.counterclockwise")
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(height: 40)
    }

    private var markupControls: some View {
        HStack(spacing: 24) {
            SwiftUI.ColorPicker("描画色", selection: $strokeColor, supportsOpacity: false)
                .labelsHidden()
                .accessibilityIdentifier("compose.media.editor.color")
            Button {
                _ = strokes.popLast()
            } label: {
                Label("元に戻す", systemImage: "arrow.uturn.backward")
            }
            .disabled(strokes.isEmpty)
            Button(role: .destructive) {
                strokes = []
            } label: {
                Label("描画を消去", systemImage: "trash")
            }
            .disabled(strokes.isEmpty)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(height: 40)
    }

    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeStroke == nil {
                    activeStroke = MarkupStroke(color: strokeColor, points: [value.location])
                } else {
                    activeStroke?.points.append(value.location)
                }
            }
            .onEnded { _ in
                if let activeStroke { strokes.append(activeStroke) }
                activeStroke = nil
            }
    }

    private var transformGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in baseOffset = offset }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoom = min(max(baseZoom * value, 1), 6) }
            .onEnded { _ in baseZoom = zoom }
    }

    @MainActor
    private func save() {
        let content = MissCatEditableMediaCanvas(
            imageData: media.data,
            zoom: zoom,
            offset: offset,
            rotation: rotation,
            isMirrored: isMirrored,
            strokes: strokes,
            overlayText: overlayText
        )
        let renderer = ImageRenderer(content: content.frame(width: canvasSize.width, height: canvasSize.height))
        renderer.scale = min(3, 1_024 / max(canvasSize.width, 1))
        guard let image = renderer.uiImage,
              let data = image.jpegData(compressionQuality: 0.92)
        else {
            errorMessage = "編集した画像を保存できませんでした"
            return
        }
        onSave(data)
        dismiss()
    }

    private enum EditMode: String, CaseIterable, Identifiable {
        case transform
        case draw
        var id: String { rawValue }
    }
}

private struct MissCatEditableMediaCanvas: View {
    let imageData: Data
    let zoom: CGFloat
    let offset: CGSize
    let rotation: Angle
    let isMirrored: Bool
    let strokes: [MarkupStroke]
    let overlayText: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(x: isMirrored ? -zoom : zoom, y: zoom)
                        .rotationEffect(rotation)
                        .offset(offset)
                }

                Canvas { context, _ in
                    for stroke in strokes where stroke.points.count > 1 {
                        var path = Path()
                        path.move(to: stroke.points[0])
                        for point in stroke.points.dropFirst() { path.addLine(to: point) }
                        context.stroke(path, with: .color(stroke.color), lineWidth: 5)
                    }
                }

                if !overlayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(overlayText)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .padding()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

private struct MarkupStroke: Equatable {
    let color: Color
    var points: [CGPoint]
}
