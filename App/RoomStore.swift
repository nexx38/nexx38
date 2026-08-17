import Foundation
import SwiftUI
import KuehllastCore

/// Hält alle Räume und speichert sie als JSON im Dokumentenverzeichnis der App.
/// Speichert bei JEDER Änderung sofort (didSet) – so gehen Eingaben auch dann
/// nicht verloren, wenn die App im Hintergrund beendet wird.
@MainActor
final class RoomStore: ObservableObject {
    @Published var rooms: [Room] = [] {
        didSet { if !isLoading { save() } }
    }

    /// Gebäudeweite Anlagen-Einstellungen (WP, Klima, Abgleich).
    @Published var building = BuildingSettings() {
        didSet { if !isLoading { saveBuilding() } }
    }

    private var isLoading = false

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("rooms.json")
    }()

    private let buildingFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("building.json")
    }()

    /// Ablage der Scan-Fotos (Dateinamen stehen in Room.photoFilenames).
    private let photosDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoomPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        load()
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        if let data = try? Data(contentsOf: buildingFileURL),
           let decoded = try? JSONDecoder().decode(BuildingSettings.self, from: data) {
            building = decoded
        }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Room].self, from: data) else {
            return
        }
        rooms = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func saveBuilding() {
        guard let data = try? JSONEncoder().encode(building) else { return }
        try? data.write(to: buildingFileURL, options: .atomic)
    }

    func add(_ room: Room) {
        rooms.append(room)
    }

    func update(_ room: Room) {
        if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[idx] = room
        }
    }

    func delete(at offsets: IndexSet) {
        // Fotos gelöschter Räume mit aufräumen, sonst sammeln sich Waisen an.
        for index in offsets {
            (rooms[index].photoFilenames ?? []).forEach(removePhotoFile)
        }
        rooms.remove(atOffsets: offsets)
    }

    // MARK: - Fotos

    /// Legt ein Foto (JPEG-Daten) in der Foto-Ablage ab und gibt den Dateinamen
    /// zurück – der wird in Room.photoFilenames eingetragen.
    func savePhotoData(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: photosDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func photoURL(named name: String) -> URL {
        photosDirectory.appendingPathComponent(name)
    }

    func removePhotoFile(named name: String) {
        try? FileManager.default.removeItem(at: photoURL(named: name))
    }

    /// Importiert einen HeizlastScan-JSON-Export als neuen Raum.
    @discardableResult
    func importScan(from url: URL) throws -> Room {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let room = try HeizlastScanImport.room(fromJSON: data)
        add(room)
        return room
    }
}
