import Foundation
import SwiftUI
import KuehllastCore

/// Hält Projekte (Kunde/Objekt) und alle Räume, gespeichert als JSON im
/// Dokumentenverzeichnis. Speichert bei JEDER Änderung sofort (didSet) – so
/// gehen Eingaben auch dann nicht verloren, wenn die App beendet wird.
@MainActor
final class RoomStore: ObservableObject {

    @Published var rooms: [Room] = [] {
        didSet { if !isLoading { save() } }
    }

    @Published var projects: [Project] = [] {
        didSet { if !isLoading { saveProjects() } }
    }

    /// Aktives Projekt – neue Scans/Räume landen hier, Listen filtern darauf.
    @Published var currentProjectID: UUID? {
        didSet {
            if !isLoading, let id = currentProjectID {
                UserDefaults.standard.set(id.uuidString, forKey: "currentProjectID")
            }
        }
    }

    private var isLoading = false

    var currentProject: Project? {
        projects.first { $0.id == currentProjectID }
    }

    /// Räume des aktiven Projekts (Reihenfolge wie erfasst).
    var currentRooms: [Room] {
        rooms.filter { $0.projectID == currentProjectID }
    }

    /// Anlagen-Einstellungen des aktiven Projekts (les- und schreibbar –
    /// Schreiben landet im Projekt und wird mitgespeichert).
    var building: BuildingSettings {
        get { currentProject?.building ?? BuildingSettings() }
        set {
            if let index = projects.firstIndex(where: { $0.id == currentProjectID }) {
                projects[index].building = newValue
            }
        }
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("rooms.json")
    }()

    private let projectsFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("projects.json")
    }()

    /// Altes globales Anlagen-Einstellungs-File (vor dem Projekte-Modul) –
    /// wird bei der Migration ins Standard-Projekt übernommen.
    private let legacyBuildingFileURL: URL = {
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

        if let data = try? Data(contentsOf: projectsFileURL),
           let decoded = try? JSONDecoder().decode([Project].self, from: data) {
            projects = decoded
        }
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Room].self, from: data) {
            rooms = decoded
        }

        // Migration: mindestens ein Projekt, alte globale Anlagen-Einstellungen
        // und projektlose Räume ins Standard-Projekt übernehmen.
        if projects.isEmpty {
            var standard = Project(name: "Mein Gebäude")
            if let data = try? Data(contentsOf: legacyBuildingFileURL),
               let legacy = try? JSONDecoder().decode(BuildingSettings.self, from: data) {
                standard.building = legacy
            }
            projects = [standard]
            saveProjects()
        }

        let saved = UserDefaults.standard.string(forKey: "currentProjectID")
            .flatMap(UUID.init(uuidString:))
        currentProjectID = projects.first { $0.id == saved }?.id ?? projects[0].id

        var migrated = false
        for index in rooms.indices where rooms[index].projectID == nil {
            rooms[index].projectID = currentProjectID
            migrated = true
        }
        if migrated { save() }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func saveProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: projectsFileURL, options: .atomic)
    }

    // MARK: - Projekte

    func addProject(named name: String) {
        let project = Project(name: name.isEmpty ? "Neues Projekt" : name)
        projects.append(project)
        currentProjectID = project.id
    }

    func updateProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        }
    }

    /// Löscht ein Projekt MITSAMT seiner Räume und deren Fotos.
    /// Das letzte Projekt kann nicht gelöscht werden.
    func deleteProject(id: UUID) {
        guard projects.count > 1 else { return }
        for room in rooms where room.projectID == id {
            (room.photoFilenames ?? []).forEach(removePhotoFile)
        }
        rooms.removeAll { $0.projectID == id }
        projects.removeAll { $0.id == id }
        if currentProjectID == id { currentProjectID = projects.first?.id }
    }

    // MARK: - Räume

    func add(_ room: Room) {
        var new = room
        if new.projectID == nil { new.projectID = currentProjectID }
        rooms.append(new)
    }

    func update(_ room: Room) {
        if let index = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[index] = room
        }
    }

    /// Löscht Räume über ihre IDs (die Listen zeigen gefilterte Ausschnitte,
    /// Offsets wären dort falsch). Fotos werden mit aufgeräumt.
    func deleteRooms(ids: [UUID]) {
        for room in rooms where ids.contains(room.id) {
            (room.photoFilenames ?? []).forEach(removePhotoFile)
        }
        rooms.removeAll { ids.contains($0.id) }
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

    /// Importiert einen HeizlastScan-JSON-Export als neuen Raum ins aktive Projekt.
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
