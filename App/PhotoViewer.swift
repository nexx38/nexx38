import SwiftUI

/// Vollbild-Foto-Viewer: Wischen blättert zwischen den Fotos, Kneifen zoomt,
/// Doppeltipp setzt den Zoom zurück.
struct PhotoViewerView: View {
    let photoNames: [String]
    let startIndex: Int
    let urlFor: (String) -> URL

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(photoNames: [String], startIndex: Int, urlFor: @escaping (String) -> URL) {
        self.photoNames = photoNames
        self.startIndex = startIndex
        self.urlFor = urlFor
        self._selection = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(photoNames.enumerated()), id: \.offset) { index, name in
                    ZoomableImage(url: urlFor(name))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photoNames.count > 1 ? .automatic : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(16)
            }
        }
        .statusBarHidden()
    }
}

/// Ein Foto mit Pinch-Zoom (1–5×) und Doppeltipp zum Zurücksetzen.
private struct ZoomableImage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .containerRelativeFrame([.horizontal, .vertical])
                        .scaleEffect(scale)
                }
                .defaultScrollAnchor(.center)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1
                        lastScale = 1
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.gray)
            }
        }
    }
}
