import SwiftUI
import UniformTypeIdentifiers
import KuehllastCore

struct RoomListView: View {
    @EnvironmentObject var store: RoomStore
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var importError: String?

    private var accent: Color { Color(red: 0.33, green: 0.29, blue: 0.72) }

    var body: some View {
        NavigationStack {
            Group {
                if store.rooms.isEmpty {
                    emptyState
                } else {
                    roomList
                }
            }
            .navigationTitle("LastScan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if RoomScanAvailability.isSupported {
                            Button {
                                showScanner = true
                            } label: {
                                Label("Raum scannen", systemImage: "camera.viewfinder")
                            }
                        }
                        Button {
                            store.add(Room(name: "Neuer Raum", floorArea: 20, height: 2.5))
                        } label: {
                            Label("Neuer Raum", systemImage: "square.dashed")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("JSON-Scan importieren", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .fullScreenCover(isPresented: $showScanner) {
                RoomScanView()
            }
            .alert("Import fehlgeschlagen",
                   isPresented: Binding(
                       get: { importError != nil },
                       set: { if !$0 { importError = nil } }
                   )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var roomList: some View {
        List {
            if store.rooms.count >= 2 {
                buildingSummary
            }
            ForEach(store.rooms) { room in
                NavigationLink(value: room.id) {
                    RoomRow(room: room)
                }
            }
            .onDelete { store.delete(at: $0) }
        }
        .navigationDestination(for: UUID.self) { id in
            if let idx = store.rooms.firstIndex(where: { $0.id == id }) {
                RoomEditView(room: $store.rooms[idx])
            }
        }
    }

    /// Gebäude-Gesamtsumme über alle Räume – die Grundlage der
    /// Multisplit-Auslegung (mehrere Räume, ein Außengerät).
    private var buildingSummary: some View {
        let cooling = store.rooms.reduce(0.0) { sum, room in
            let region = ClimateRegion.region(id: room.climateRegionID)
            return sum + CoolingLoadCalculator(region: region).calculate(room).total
        }
        let heating = store.rooms.reduce(0.0) { sum, room in
            sum + HeatingLoadCalculator().calculate(room).total
        }
        let area = store.rooms.reduce(0.0) { $0 + $1.floorArea }

        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Gebäude gesamt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    Label(String(format: "%.1f kW Kühlung", cooling / 1000),
                          systemImage: "air.conditioner.horizontal")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(accent)
                    Label(String(format: "%.1f kW Heizung", heating / 1000),
                          systemImage: "thermometer")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(red: 0.9, green: 0.4, blue: 0.1))
                }
                Text(String(format: "%d Räume · %.0f m² · Multisplit-Außengerät ab %.1f kW",
                            store.rooms.count, area, cooling / 1000))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wind.snow")
                .font(.system(size: 52))
                .foregroundStyle(accent)
            Text("Noch keine Räume")
                .font(.title3.weight(.medium))
            Text(RoomScanAvailability.isSupported
                 ? "Scanne einen Raum mit der Kamera oder lege ihn von Hand an."
                 : "Lege einen Raum an und gib seine Maße ein.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if RoomScanAvailability.isSupported {
                Button {
                    showScanner = true
                } label: {
                    Label("Raum scannen", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                Button {
                    store.add(Room(name: "Neuer Raum", floorArea: 20, height: 2.5))
                } label: {
                    Text("oder Raum von Hand anlegen")
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    store.add(Room(name: "Neuer Raum", floorArea: 20, height: 2.5))
                } label: {
                    Label("Raum anlegen", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                Button {
                    showImporter = true
                } label: {
                    Text("oder JSON-Scan importieren")
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do { try store.importScan(from: url) }
            catch { importError = error.localizedDescription }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

private struct RoomRow: View {
    let room: Room

    private var coolingLoad: Double {
        let region = ClimateRegion.region(id: room.climateRegionID)
        return CoolingLoadCalculator(region: region).calculate(room).total
    }

    private var heatingLoad: Double {
        HeatingLoadCalculator().calculate(room).total
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).font(.body.weight(.medium))
                Text(String(format: "%.1f m² · %d Fenster", room.floorArea, room.windows.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(String(format: "%.0f W", coolingLoad.rounded()), systemImage: "air.conditioner.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Label(String(format: "%.0f W", heatingLoad.rounded()), systemImage: "thermometer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
