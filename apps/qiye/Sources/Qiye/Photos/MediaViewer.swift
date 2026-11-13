import SwiftUI
import Photos
import UIKit

struct MediaViewerItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    var previewURL: URL? = nil
}

/// Present in a fullScreenCover. Optional actions appear beside save and share.
@MainActor
struct MediaViewer: View {
    let items: [MediaViewerItem]
    let actions: AnyView?
    var onIndexChange: ((Int) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panOrigin: CGSize = .zero
    @State private var pageOffset: CGFloat = 0
    @State private var dismissOffset: CGFloat = 0
    @State private var dragAxis: DragAxis?
    @State private var isSaving = false
    @State private var feedback: String?
    @State private var showsFeedback = false
    @State private var share: ShareAsset?
    @State private var isPreparingShare = false
    @State private var shareTask: Task<Void, Never>?

    init(items: [MediaViewerItem], initialIndex: Int = 0, actions: AnyView? = nil, onIndexChange: ((Int) -> Void)? = nil) {
        self.items = items
        self.actions = actions
        self.onIndexChange = onIndexChange
        _index = State(initialValue: min(max(initialIndex, 0), max(items.count - 1, 0)))
    }

    private enum DragAxis { case horizontal, vertical, pan }
    private struct ShareAsset: Identifiable {
        let url: URL
        var id: URL { url }
    }
    private var current: MediaViewerItem? { items.indices.contains(index) ? items[index] : nil }
    private var effectiveZoom: CGFloat { min(max(zoom * magnification, 1), 5) }
    private var nearbyItems: [MediaViewerItem] {
        items.enumerated().filter { abs($0.offset - index) <= 1 }.map(\.element)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if current != nil {
                    imagePages(size: geometry.size)
                        .offset(y: dismissOffset)
                        .scaleEffect(1 - min(dismissOffset / max(geometry.size.height, 1), 0.2))
                        .opacity(1 - min(dismissOffset / max(geometry.size.height, 1), 0.5))
                        .gesture(dragGesture(size: geometry.size))
                        .simultaneousGesture(magnifyGesture)
                        .onTapGesture(count: 2, perform: toggleZoom)
                        .accessibilityLabel("照片，第 \(index + 1) 张，共 \(items.count) 张")
                        .accessibilityHint("左右滑动切换，双击或双指缩放，原始大小时向下滑动关闭")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: turnPage(by: 1)
                            case .decrement: turnPage(by: -1)
                            @unknown default: break
                            }
                        }
                } else {
                    ContentUnavailableView("暂无照片", systemImage: "photo")
                }
            }
            .overlay(alignment: .topLeading) {
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .viewerControl()
                    .padding(20)
                    .accessibilityIdentifier("media-viewer-close")
            }
            .overlay(alignment: .top) {
                if items.count > 1 {
                    Text("\(index + 1) / \(items.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 32)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) { viewerDock.padding(18) }
        }
        .background(.black)
        .accessibilityIdentifier("media-viewer")
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .alert("照片", isPresented: $showsFeedback) {
            Button("好", role: .cancel) { }
        } message: { Text(feedback ?? "") }
        .sheet(item: $share) { asset in
            MediaShareSheet(url: asset.url)
        }
        .onChange(of: index) { _, value in onIndexChange?(value) }
        .onDisappear { shareTask?.cancel() }
    }

    private func imagePages(size: CGSize) -> some View {
        ZStack {
            ForEach(nearbyItems) { item in
                let position = items.firstIndex(where: { $0.id == item.id }) ?? index
                MediaViewerImage(item: item)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(position == index ? effectiveZoom : 1)
                    .offset(position == index ? pan : .zero)
                    .offset(x: CGFloat(position - index) * size.width + pageOffset)
                    .accessibilityHidden(position != index)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(.rect)
        .clipped()
    }

    private var viewerDock: some View {
        HStack(spacing: 10) {
            if items.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                                Button {
                                    Haptics.selection()
                                    turnPage(by: position - index)
                                } label: {
                                    thumbnail(item)
                                        .frame(width: position == index ? 40 : 30, height: 44)
                                        .clipShape(.rect(cornerRadius: 6))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(.white.opacity(position == index ? 0.9 : 0), lineWidth: 2)
                                        }
                                        .opacity(position == index ? 1 : 0.6)
                                }
                                .buttonStyle(CollectionPressStyle())
                                .id(item.id)
                                .accessibilityLabel("转到第 \(position + 1) 张照片")
                                .accessibilityAddTraits(position == index ? [.isSelected] : [])
                            }
                        }.padding(8)
                    }
                    .frame(maxWidth: 190).frame(height: 60)
                    .background(.regularMaterial, in: Capsule())
                    .onChange(of: index) { _, value in
                        guard items.indices.contains(value) else { return }
                        withAnimation(reduceMotion ? nil : CollectionStyle.spring) { proxy.scrollTo(items[value].id, anchor: .center) }
                    }
                    .onAppear {
                        if let current { proxy.scrollTo(current.id, anchor: .center) }
                    }
                }
            }
            controls
        }
    }

    @ViewBuilder
    private func thumbnail(_ item: MediaViewerItem) -> some View {
        let url = item.previewURL ?? item.url
        if url.isFileURL { LocalPhotoImage(url: url) }
        else {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Color.white.opacity(0.1) }
            }
        }
    }

    private var controls: some View {
        Group {
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 14) {
                    controlsRow
                }
            } else {
                controlsRow
            }
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 14) {
            if let actions { actions.viewerControl() }
            Button(action: prepareShare) {
                if isPreparingShare { ProgressView().tint(.white) }
                else { Image(systemName: "square.and.arrow.up") }
            }
            .viewerControl()
            .disabled(current == nil || isPreparingShare)
            .accessibilityLabel("分享照片")
            Button {
                Task { await saveToPhotos() }
            } label: {
                if isSaving { ProgressView().tint(.white) }
                else { Image(systemName: "square.and.arrow.down") }
            }
            .viewerControl()
            .disabled(current == nil || isSaving)
            .accessibilityLabel("保存到系统相册")
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, 1), 5)
                if zoom <= 1 { resetZoom() }
                pageOffset = 0
                dismissOffset = 0
                dragAxis = nil
            }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard magnification == 1 else { return }
                if dragAxis == nil {
                    if zoom > 1 {
                        dragAxis = .pan
                        panOrigin = pan
                    } else {
                        dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                    }
                }
                switch dragAxis {
                case .pan:
                    pan = CGSize(
                        width: clamped(panOrigin.width + value.translation.width, limit: size.width * (zoom - 1) / 2),
                        height: clamped(panOrigin.height + value.translation.height, limit: size.height * (zoom - 1) / 2)
                    )
                case .horizontal:
                    let atEdge = (index == 0 && value.translation.width > 0) || (index == items.count - 1 && value.translation.width < 0)
                    pageOffset = value.translation.width * (atEdge ? 0.25 : 1)
                case .vertical: dismissOffset = max(value.translation.height, 0)
                case nil: break
                }
            }
            .onEnded { value in
                defer { dragAxis = nil }
                switch dragAxis {
                case .vertical:
                    if value.translation.height > 110 || (value.translation.height > 35 && value.predictedEndTranslation.height > 260) {
                        dismiss()
                    } else { animate { dismissOffset = 0 } }
                case .horizontal:
                    let distance = value.translation.width
                    let predicted = value.predictedEndTranslation.width
                    if abs(distance) > min(size.width * 0.22, 90) || abs(predicted) > size.width * 0.45 {
                        turnPage(by: distance < 0 ? 1 : -1)
                    } else { animate { pageOffset = 0 } }
                case .pan, nil: break
                }
            }
    }

    private func clamped(_ value: CGFloat, limit: CGFloat) -> CGFloat { min(max(value, -limit), limit) }

    private func turnPage(by delta: Int) {
        let next = min(max(index + delta, 0), max(items.count - 1, 0))
        animate {
            index = next
            pageOffset = 0
            dismissOffset = 0
            resetZoom()
        }
    }

    private func toggleZoom() {
        animate {
            if zoom > 1 { resetZoom() } else { zoom = 2.5 }
        }
    }

    private func resetZoom() {
        zoom = 1
        pan = .zero
        panOrigin = .zero
    }

    private func animate(_ changes: () -> Void) {
        withAnimation(reduceMotion ? nil : CollectionStyle.spring, changes)
    }

    private func report(_ message: String) {
        feedback = message
        showsFeedback = true
    }

    private func saveToPhotos() async {
        guard let item = current, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            report("尚未获得添加照片的权限，请在系统设置中允许访问照片。")
            return
        }
        do {
            let file = try await Self.localFile(for: item)
            try Task.checkCancellation()
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: file, options: nil)
            }
            report("已保存到系统相册。")
        } catch is CancellationError {
        } catch { report("保存失败：\(error.localizedDescription)") }
    }

    private func prepareShare() {
        guard let item = current, !isPreparingShare else { return }
        isPreparingShare = true
        shareTask = Task {
            defer { isPreparingShare = false }
            do {
                let file = try await Self.localFile(for: item)
                try Task.checkCancellation()
                share = ShareAsset(url: file)
            } catch is CancellationError {
            } catch { report("无法准备分享：\(error.localizedDescription)") }
        }
    }

    private static func localFile(for item: MediaViewerItem) async throws -> URL {
        if item.url.isFileURL { return item.url }
        let (downloaded, response) = try await URLSession.shared.download(from: item.url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let mime = http.mimeType, mime.hasPrefix("image/") else { throw URLError(.badServerResponse) }
        let directory = URL.temporaryDirectory.appendingPathComponent("MediaViewerShares", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let proposedExtension = URL(fileURLWithPath: response.suggestedFilename ?? "photo.jpg").pathExtension
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(proposedExtension.isEmpty ? "jpg" : proposedExtension)
        try FileManager.default.moveItem(at: downloaded, to: file)
        return file
    }
}

@MainActor
private struct MediaViewerImage: View {
    let item: MediaViewerItem
    @State private var retry = 0

    var body: some View {
        if item.url.isFileURL {
            LocalPhotoImage(url: item.url, contentMode: .fit, maximumPixelSize: 4_096)
        } else {
            AsyncImage(url: item.url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .empty:
                    ZStack {
                        preview
                        ProgressView().tint(.white)
                    }
                case .failure:
                    ZStack {
                        preview.opacity(0.4)
                        VStack(spacing: 12) {
                            Label("照片加载失败", systemImage: "wifi.exclamationmark")
                            Button("重试") { retry += 1 }.buttonStyle(.bordered)
                        }
                        .foregroundStyle(.white)
                    }
                @unknown default: ProgressView().tint(.white)
                }
            }
            .id(retry)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let preview = item.previewURL, preview != item.url {
            if preview.isFileURL {
                LocalPhotoImage(url: preview, contentMode: .fit)
            } else {
                AsyncImage(url: preview) { image in image.resizable().scaledToFit() } placeholder: { Color.clear }
            }
        } else { Color.clear }
    }
}

private extension View {
    @ViewBuilder
    func viewerControl() -> some View {
        if #available(iOS 26, *) {
            self
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
                .contentShape(Circle())
        } else {
            self
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
    }
}

private struct MediaShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
