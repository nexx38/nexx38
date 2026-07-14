import SwiftUI
import RoomPlan
import KuehllastCore

/// Prüft, ob das Gerät LiDAR hat und Raumscans unterstützt.
/// RoomPlan braucht ein iPhone 12 Pro/Pro Max oder neuer (Pro-Reihe) bzw. ein iPad Pro mit LiDAR.
enum RoomScanAvailability {
    static var isSupported: Bool { RoomCaptureSession.isSupported }
}

/// Beobachtbarer Zustand des Scans, den die SwiftUI-Ansicht anzeigt.
/// Alle Änderungen laufen über den Main-Thread (der Coordinator dispatcht dorthin).
final class ScanModel: ObservableObject {
    @Published var statusMessage: String? = "Raum langsam abgehen – Wände, Türen und Fenster werden erfasst"
    @Published var canFinish = false
    @Published var errorText: String?

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onFinished: ((CapturedRoom) -> Void)?

    func start() { onStart?() }

    /// Beendet den Scan und stößt die Nachbearbeitung an (liefert am Ende den Raum).
    func requestFinish() {
        statusMessage = "Wird verarbeitet …"
        onStop?()
    }

    func finish(with room: CapturedRoom) { onFinished?(room) }
}

/// SwiftUI-Ansicht: Kamera-Scan mit Bedien-Overlay (Abbrechen / Fertig).
struct RoomScanView: View {
    @EnvironmentObject var store: RoomStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ScanModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomScanRepresentable(model: model)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if let message = model.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                HStack(spacing: 16) {
                    Button("Abbrechen", role: .cancel) {
                        model.onStop?()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Fertig") {
                        model.requestFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canFinish)
                }
            }
            .padding(.bottom, 48)
        }
        .onAppear {
            model.onFinished = { captured in
                store.add(RoomPlanConverter.room(from: captured))
                dismiss()
            }
        }
        .statusBarHidden()
    }
}

/// Bindeglied zwischen SwiftUI und Apples `RoomCaptureView` (UIKit).
struct RoomScanRepresentable: UIViewRepresentable {
    @ObservedObject var model: ScanModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        view.delegate = context.coordinator
        context.coordinator.captureView = view
        model.onStart = { view.captureSession.run(configuration: RoomCaptureSession.Configuration()) }
        model.onStop  = { view.captureSession.stop() }
        // Scan startet automatisch, sobald die Ansicht erscheint.
        DispatchQueue.main.async { model.start() }
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    func makeCoordinator() -> RoomScanCoordinator { RoomScanCoordinator(model: model) }
}

/// Top-level (nicht verschachtelt), damit diese NSObject-Unterklasse einen stabilen
/// Objective-C-Laufzeitnamen bekommt – eine verschachtelte NSObject-Unterklasse
/// scheitert beim Archivieren im Release-Build.
final class RoomScanCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    let model: ScanModel
    weak var captureView: RoomCaptureView?

    init(model: ScanModel) { self.model = model }

    // RoomCaptureViewDelegate erbt NSCoding, weil RoomCaptureView seinen Delegate
    // intern zur Laufzeit archiviert. `nil` würde RoomPlan abstürzen lassen – daher
    // eine echte, aber inaktive Instanz. Die Callbacks erreichen weiter den in
    // makeUIView zugewiesenen, lebenden Coordinator.
    required init?(coder: NSCoder) {
        self.model = ScanModel()
        super.init()
    }
    func encode(with coder: NSCoder) {}

    // MARK: RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async { self.model.canFinish = !room.walls.isEmpty }
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { self.model.errorText = error.localizedDescription }
            return
        }
        DispatchQueue.main.async { self.model.finish(with: processedResult) }
    }
}
