import SwiftUI
import QuickLook

/// Zeigt das USDZ-3D-Modell eines gescannten Raums im Apple-QuickLook-Viewer:
/// drehen, zoomen, und über den AR-Knopf sogar in die reale Umgebung stellen.
struct ModelViewerScreen: View {
    let url: URL

    var body: some View {
        USDZPreview(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("3D-Modell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
    }
}

/// Bindeglied zu Apples QLPreviewController (USDZ-Viewer inkl. AR-Modus).
private struct USDZPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
