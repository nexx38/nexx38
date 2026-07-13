import Foundation
import SwiftUI
import KuehllastCore

/// Hält alle Räume und speichert sie als JSON im Dokumentenverzeichnis der App.
@MainActor
final class RoomStore: ObservableObject {
    @Published var rooms: [Room] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("rooms.json")
    }()

    init() {
        load()
    }

    func load() {
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

    func add(_ room: Room) {
        rooms.append(room)
        save()
    }

    func update(_ room: Room) {
        if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[idx] = room
            save()
        }
    }

    func delete(at offsets: IndexSet) {
        rooms.remove(atOffsets: offsets)
        save()
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
