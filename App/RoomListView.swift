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
            .navigationTitle("Kühllast")
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
            .alert("Import fehlgeschlagen", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var roomList: some View {
        List {
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
                    .onDisappear { store.save() }
            }
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

    private var load: Double {
        let region = ClimateRegion.region(id: room.climateRegionID)
        return CoolingLoadCalculator(region: region).calculate(room).total
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).font(.body.weight(.medium))
                Text(String(format: "%.1f m² · %d Fenster", room.floorArea, room.windows.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.0f W", load.rounded()))
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
