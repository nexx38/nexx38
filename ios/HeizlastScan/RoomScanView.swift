import SwiftUI
import RoomPlan

// SwiftUI wrapper around RoomPlan's RoomCaptureView.
// Drives the capture session and hands the finished CapturedRoom back to SwiftUI.
struct RoomScanView: UIViewRepresentable {
    @ObservedObject var model: ScanModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.captureView = view
        model.onStart = { view.captureSession.run(configuration: RoomCaptureSession.Configuration()) }
        model.onStop  = { view.captureSession.stop() }
        // Auto-start scanning as soon as the view appears
        DispatchQueue.main.async { model.start() }
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    func makeCoordinator() -> RoomScanCoordinator { RoomScanCoordinator(model: model) }
}

// Top-level (not nested in the struct) so this NSObject subclass gets a stable
// Objective-C runtime name — a nested NSObject subclass fails to archive under
// release-build whole-module optimisation ("unstable name via NSCoding").
final class RoomScanCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    let model: ScanModel
    weak var captureView: RoomCaptureView?

    init(model: ScanModel) { self.model = model }

    // Allow RoomCaptureView to run its own post-processing pass.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }

    // Final processed room delivered here.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.model.errorText = error.localizedDescription }
            return
        }
        DispatchQueue.main.async { self.model.finish(with: processedResult) }
    }
}
