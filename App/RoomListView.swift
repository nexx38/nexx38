import SwiftUI
import UniformTypeIdentifiers
import KuehllastCore

/// Welcher Scan-Ablauf soll im Vollbild laufen?
/// Beide teilen sich bewusst EIN `fullScreenCover` – zwei Vollbild-Präsentationen
/// an derselben Ansicht vertragen sich in SwiftUI nicht zuverlässig.
private enum ScanTarget: String, Identifiable {
    /// Bewährter Einzelraum-Scan (unverändert).
    case einzel
    /// Mehrere Räume in EINER Sitzung – erkennt Trennwände automatisch.
    case mehrraum
    var id: String { rawValue }
}

struct RoomListView: View {
    @EnvironmentObject var store: RoomStore
    @State private var showImporter = false
    @State private var scanTarget: ScanTarget?
    @State private var importError: String?
    @State private var showNewProjectAlert = false
    @State private var newProjectName = ""
    @State private var editingProject: Project?
    @State private var showDeleteProjectConfirm = false

    private var accent: Color { Color(red: 0.33, green: 0.29, blue: 0.72) }

    var body: some View {
        NavigationStack {
            Group {
                if store.currentRooms.isEmpty {
                    emptyState
                } else {
                    roomList
                }
            }
            .navigationTitle(store.currentProject?.name ?? "LastScan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    projectMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if RoomScanAvailability.isSupported {
                            Button {
                                scanTarget = .einzel
                            } label: {
                                Label("Raum scannen", systemImage: "camera.viewfinder")
                            }
                            // Mehrere Räume ohne Unterbrechung: nur so liegen
                            // alle Wände im selben Koordinatensystem und die
                            // Trennwände lassen sich automatisch erkennen.
                            Button {
                                scanTarget = .mehrraum
                            } label: {
                                Label("Mehrere Räume scannen", systemImage: "square.stack.3d.up")
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
            .fullScreenCover(item: $scanTarget) { target in
                switch target {
                case .einzel:   RoomScanView()
                case .mehrraum: MultiRoomScanView()
                }
            }
            .sheet(item: $editingProject) { project in
                ProjectEditView(project: project)
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
            .alert("Neues Projekt", isPresented: $showNewProjectAlert) {
                TextField("Name (z. B. EFH Müller)", text: $newProjectName)
                Button("Anlegen") {
                    store.addProject(named: newProjectName)
                    newProjectName = ""
                }
                Button("Abbrechen", role: .cancel) { newProjectName = "" }
            } message: {
                Text("Jedes Projekt hat eigene Räume und eigene Anlagen-Einstellungen.")
            }
            .confirmationDialog("Projekt und alle seine Räume löschen?",
                                isPresented: $showDeleteProjectConfirm,
                                titleVisibility: .visible) {
                Button("Endgültig löschen", role: .destructive) {
                    if let id = store.currentProjectID {
                        store.deleteProject(id: id)
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    /// Projekt-Umschalter: Kunde/Objekt wählen, anlegen, bearbeiten, löschen.
    private var projectMenu: some View {
        Menu {
            ForEach(store.projects) { project in
                Button {
                    store.currentProjectID = project.id
                } label: {
                    if project.id == store.currentProjectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
            Divider()
            Button {
                showNewProjectAlert = true
            } label: {
                Label("Neues Projekt", systemImage: "plus")
            }
            Button {
                editingProject = store.currentProject
            } label: {
                Label("Projekt bearbeiten", systemImage: "pencil")
            }
            if store.projects.count > 1 {
                Button(role: .destructive) {
                    showDeleteProjectConfirm = true
                } label: {
                    Label("Projekt löschen", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "folder")
        }
    }

    private var roomList: some View {
        List {
            buildingSummary
            ForEach(store.currentRooms) { room in
                NavigationLink(value: room.id) {
                    RoomRow(room: room)
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { store.currentRooms[$0].id }
                store.deleteRooms(ids: ids)
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let idx = store.rooms.firstIndex(where: { $0.id == id }) {
                RoomEditView(room: $store.rooms[idx])
            }
        }
    }

    /// Gebäude-Gesamtsumme des aktiven Projekts – Einstieg in die
    /// Anlagen-Auslegung (WP, Multisplit, Heizkörper, Abgleich).
    private var buildingSummary: some View {
        let rooms = store.currentRooms
        let cooling = rooms.reduce(0.0) { sum, room in
            let region = ClimateRegion.region(id: room.climateRegionID)
            return sum + CoolingLoadCalculator(region: region).calculate(room).total
        }
        let heating = rooms.reduce(0.0) { sum, room in
            sum + HeatingLoadCalculator().calculate(room).total
        }
        let area = rooms.reduce(0.0) { $0 + $1.floorArea }

        return Section {
            NavigationLink {
                BuildingView()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gebäude / Anlage")
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
                    Text(String(format: "%d Räume · %.0f m² · WP-Auslegung, Multisplit, Heizkörper-Check →",
                                rooms.count, area))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wind.snow")
                .font(.system(size: 52))
                .foregroundStyle(accent)
            Text("Noch keine Räume in diesem Projekt")
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
                    scanTarget = .einzel
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
