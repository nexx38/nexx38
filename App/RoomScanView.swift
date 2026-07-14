import SwiftUI
import RoomPlan
import KuehllastCore

/// Prüft, ob das Gerät einen LiDAR-Sensor hat und Raumscans unterstützt.
/// RoomPlan braucht ein iPhone 12 Pro/Pro Max oder neuer (Pro-Reihe) bzw. ein iPad Pro mit LiDAR.
enum RoomScanAvailability {
    static var isSupported: Bool {
        RoomCaptureSession.isSupported
    }
}

/// Scannt einen Raum per Kamera + LiDAR (Apple RoomPlan) – der direkte Ersatz
/// für das manuelle Vermessen. Erfasst Wände, Türen und Fenster automatisch.
/// Fensterausrichtung und g-Wert setzt man danach wie gewohnt im Raum-Editor,
/// da RoomPlan die Himmelsrichtung nicht mitliefert.
struct RoomScanView: View {
    @EnvironmentObject var store: RoomStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = RoomScanCoordinator()

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureRepresentable(coordinator: coordinator)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if let message = coordinator.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                HStack(spacing: 16) {
                    Button("Abbrechen", role: .cancel) {
                        coordinator.stop()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Fertig") {
                        coordinator.finish()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canFinish)
                }
            }
            .padding(.bottom, 48)
        }
        .onAppear {
            coordinator.onComplete = { captured in
                store.add(RoomPlanConverter.room(from: captured))
                dismiss()
            }
        }
        .statusBarHidden()
    }
}

/// Verbindet SwiftUI mit Apples `RoomCaptureView` (UIKit) und wertet die
/// Ergebnisse über die RoomPlan-Delegates aus.
@MainActor
final class RoomScanCoordinator: NSObject, ObservableObject,
                                 RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    @Published var statusMessage: String? = "Raum langsam abgehen – Wände, Türen und Fenster werden erfasst"
    @Published var canFinish = false

    /// Wird aufgerufen, sobald der Scan fertig verarbeitet ist.
    var onComplete: ((CapturedRoom) -> Void)?

    let captureView = RoomCaptureView(frame: .zero)
    private let sessionConfig = RoomCaptureSession.Configuration()
    private var started = false

    override init() {
        super.init()
        captureView.delegate = self
        captureView.captureSession.delegate = self
    }

    func start() {
        guard !started else { return }
        started = true
        captureView.captureSession.run(configuration: sessionConfig)
    }

    func stop() {
        captureView.captureSession.stop()
    }

    func finish() {
        statusMessage = "Wird verarbeitet …"
        captureView.captureSession.stop()
    }

    // MARK: RoomCaptureSessionDelegate

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        Task { @MainActor in
            canFinish = !room.walls.isEmpty
        }
    }

    // MARK: RoomCaptureViewDelegate

    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                                 error: Error?) -> Bool {
        error == nil
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                statusMessage = "Verarbeitung fehlgeschlagen: \(error!.localizedDescription)"
                return
            }
            onComplete?(processedResult)
        }
    }
}

struct RoomCaptureRepresentable: UIViewRepresentable {
    let coordinator: RoomScanCoordinator

    func makeUIView(context: Context) -> RoomCaptureView {
        coordinator.start()
        return coordinator.captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
