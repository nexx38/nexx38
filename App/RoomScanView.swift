import SwiftUI
import RoomPlan
import ARKit
import CoreImage
import UIKit
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
    @Published var photoCount = 0

    /// Während des Scans aufgenommene Fotos (JPEG) – werden beim Abschluss
    /// zusammen mit dem Raum gespeichert.
    var capturedJPEGs: [Data] = []

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCapturePhoto: (() -> Void)?
    var onFinished: ((CapturedRoom) -> Void)?

    func start() { onStart?() }

    /// Beendet den Scan und stößt die Nachbearbeitung an (liefert am Ende den Raum).
    func requestFinish() {
        statusMessage = "Wird verarbeitet …"
        onStop?()
    }

    func finish(with room: CapturedRoom) { onFinished?(room) }
}

/// SwiftUI-Ansicht: Kamera-Scan mit Bedien-Overlay (Abbrechen / Foto / Fertig).
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

                    // Foto zur Dokumentation (Heizkörper, Zähler, Bestand) –
                    // ohne den laufenden Scan zu unterbrechen.
                    Button {
                        model.onCapturePhoto?()
                    } label: {
                        Label(model.photoCount > 0 ? "\(model.photoCount)" : "Foto",
                              systemImage: "camera.fill")
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
                // Eindeutiger Name, damit Mehrfach-Scans unterscheidbar bleiben.
                let base = "Gescannter Raum"
                let existing = store.currentRooms.filter { $0.name.hasPrefix(base) }.count
                let name = existing == 0 ? base : "\(base) \(existing + 1)"
                var room = RoomPlanConverter.room(from: captured, name: name)
                let names = model.capturedJPEGs.compactMap { store.savePhotoData($0) }
                if !names.isEmpty { room.photoFilenames = names }
                store.add(room)
                dismiss()
            }
        }
        .alert("Scan fehlgeschlagen",
               isPresented: Binding(
                   get: { model.errorText != nil },
                   set: { if !$0 { model.errorText = nil } }
               )) {
            Button("OK") {
                model.errorText = nil
                dismiss()
            }
        } message: {
            Text(model.errorText ?? "")
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
        model.onCapturePhoto = { [weak view, weak model] in
            guard let view, let model,
                  let frame = view.captureSession.arSession.currentFrame,
                  let data = ScanPhotoConverter.jpegData(from: frame) else { return }
            model.capturedJPEGs.append(data)
            model.photoCount = model.capturedJPEGs.count
        }
        // Scan startet automatisch, sobald die Ansicht erscheint.
        DispatchQueue.main.async { model.start() }
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    func makeCoordinator() -> RoomScanCoordinator { RoomScanCoordinator(model: model) }
}

/// Wandelt das aktuelle Kamerabild der laufenden AR-Session in JPEG-Daten um.
/// Nutzt bewusst `currentFrame` (synchron, funktioniert immer) statt der
/// asynchronen High-Res-Aufnahme – für Baustellen-Doku reicht die Auflösung.
enum ScanPhotoConverter {
    static func jpegData(from frame: ARFrame) -> Data? {
        // Kamerabild liegt quer (Landscape) – für die Portrait-App aufrichten.
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }
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
