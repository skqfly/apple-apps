import SwiftUI

struct SitePhotoPicker: View {
    let photos: [WebsitePhoto]
    let limit: Int
    let onSelect: ([TalkImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []

    private var uniquePhotos: [WebsitePhoto] {
        var seen: Set<String> = []
        return photos.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if uniquePhotos.isEmpty {
                    ContentUnavailableView("照片墙还没有图片", systemImage: "photo.on.rectangle", description: Text("可先在照片页导入，或直接从相册选择。"))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(uniquePhotos) { photo in
                        Button { toggle(photo.id) } label: {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Group {
                                        if photo.preview.isFileURL { LocalPhotoImage(url: photo.preview) }
                                        else { AsyncImage(url: photo.preview) { phase in
                                            if let image = phase.image { image.resizable().scaledToFill() }
                                            else { Color.secondary.opacity(0.12).overlay { Image(systemName: "photo") } }
                                        } }
                                    }.allowsHitTesting(false)
                                }
                                .clipped().clipShape(.rect(cornerRadius: 7)).contentShape(.rect)
                                .overlay(alignment: .topTrailing) {
                                    if let index = selected.firstIndex(of: photo.id) {
                                        Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 24, height: 24).background(Color.appAccent, in: .circle).padding(6)
                                    } else { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5).frame(width: 24, height: 24).padding(6) }
                                }
                        }.buttonStyle(.plain).accessibilityLabel("选择照片").accessibilityAddTraits(selected.contains(photo.id) ? .isSelected : [])
                    }
                }.padding(12)
            }
            .navigationTitle("照片墙").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("加入 \(selected.count)") { confirm() }.disabled(selected.isEmpty) }
            }
        }
    }
    private func toggle(_ id: String) {
        if let index = selected.firstIndex(of: id) { selected.remove(at: index) }
        else if selected.count < limit { selected.append(id) }
    }
    private func confirm() {
        let result = selected.compactMap { id -> TalkImage? in
            guard let photo = uniquePhotos.first(where: { $0.id == id }) else { return nil }
            return TalkImage(src: photo.src.isFileURL ? photo.src.absoluteString : photo.sourcePath, width: photo.width, height: photo.height, alt: photo.alt,
                preview: photo.preview.absoluteString, previewLarge: photo.previewLarge.absoluteString)
        }
        onSelect(result); dismiss()
    }
}
