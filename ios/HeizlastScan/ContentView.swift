import SwiftUI
import RoomPlan
import UniformTypeIdentifiers

// Observable state shared between the scan view and SwiftUI chrome.
final class ScanModel: ObservableObject {
    enum Phase { case idle, scanning, done }
    @Published var phase: Phase = .idle
    @Published var capturedRoom: CapturedRoom?
    @Published var errorText: String?
    @Published var roomName: String = "Raum 1"

    var onStart: (() -> Void)?
    var onStop:  (() -> Void)?

    func start() { phase = .scanning; onStart?() }
    func stop()  { onStop?() }

    func finish(with room: CapturedRoom) {
        capturedRoom = room
        phase = .done
    }

    func reset() {
        capturedRoom = nil
        errorText = nil
        phase = .idle
    }

    // Build the export JSON and write it to a temporary file for the share sheet.
    func exportURL() -> URL? {
        guard let room = capturedRoom else { return nil }
        let export = RoomExporter.make(from: room, name: roomName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(export) else { return nil }
        let safeName = roomName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeizlastScan_\(safeName).json")
        do { try data.write(to: url); return url } catch { return nil }
    }
}

// Identifiable wrapper so the share sheet only presents once the URL exists
// (driving a sheet by two separate @State vars races → black screen).
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @StateObject private var model = ScanModel()
    @State private var shareItem: ShareItem?

    var body: some View {
        Group {
            if !RoomCaptureSession.isSupported {
                unsupportedView
            } else {
                switch model.phase {
                case .idle, .scanning: scanView
                case .done:            resultView
                }
            }
        }
    }

    // MARK: Scanning

    private var scanView: some View {
        ZStack(alignment: .bottom) {
            RoomScanView(model: model).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Geh langsam durch den Raum und richte die Kamera auf alle Wände, Fenster und Türen.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                Button {
                    model.stop()
                } label: {
                    Text("Scan fertig")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: Result

    private var resultView: some View {
        let export = model.capturedRoom.map { RoomExporter.make(from: $0, name: model.roomName) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("📐 Scan abgeschlossen")
                    .font(.largeTitle.bold())

                TextField("Raumname", text: $model.roomName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                if let e = export {
                    statGrid(e)
                    detailList("🧱 Wände", e.walls)
                    detailList("🪟 Fenster", e.windows)
                    detailList("🚪 Türen", e.doors)
                }

                if let err = model.errorText {
                    Text(err).foregroundColor(.red).font(.footnote)
                }

                VStack(spacing: 12) {
                    Button {
                        if let url = model.exportURL() {
                            shareItem = ShareItem(url: url)
                        } else {
                            model.errorText = "JSON konnte nicht erstellt werden."
                        }
                    } label: {
                        Label("JSON teilen / sichern", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundColor(.white)
                    }
                    Button("Neuen Raum scannen") { model.reset() }
                        .padding(.vertical, 8)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    private func statGrid(_ e: RoomExport) -> some View {
        let area = e.floorArea
        let winArea = e.windows.reduce(0) { $0 + $1.area }
        let doorArea = e.doors.reduce(0) { $0 + $1.area }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("Fläche", String(format: "%.1f m²", area))
            stat("Höhe", String(format: "%.2f m", e.height))
            stat("Fenster", String(format: "%.1f m² (%d)", winArea, e.windows.count))
            stat("Türen", String(format: "%.1f m² (%d)", doorArea, e.doors.count))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundColor(.accentColor)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailList(_ title: String, _ items: [RoomExport.Opening]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, o in
                        Text(String(format: "  %.2f × %.2f m  =  %.2f m²", o.width, o.height, o.area))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Unsupported

    private var unsupportedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Dieses Gerät unterstützt kein RoomPlan.")
                .font(.headline)
            Text("Benötigt wird ein iPhone/iPad mit LiDAR-Sensor (iPhone 12 Pro oder neuer, iPad Pro 2020+).")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

// UIKit share sheet bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
