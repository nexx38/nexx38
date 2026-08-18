import Foundation
import KuehllastCore

/// Ein Projekt = ein Kunde/Objekt mit eigenen Räumen und eigenen
/// Anlagen-Einstellungen. Damit vermischen sich mehrere Kunden nicht mehr
/// in einer Raumliste.
struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var customerName: String
    var address: String
    var createdAt: Date
    /// Anlagen-Einstellungen (WP, Klima, Abgleich) gelten je Projekt.
    var building: BuildingSettings

    init(id: UUID = UUID(), name: String,
         customerName: String = "", address: String = "",
         createdAt: Date = Date(),
         building: BuildingSettings = BuildingSettings()) {
        self.id = id
        self.name = name
        self.customerName = customerName
        self.address = address
        self.createdAt = createdAt
        self.building = building
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, customerName, address, createdAt, building
    }

    // Fehlende Schlüssel robust auf Vorgaben zurückfallen lassen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Projekt"
        self.customerName = (try? c.decode(String.self, forKey: .customerName)) ?? ""
        self.address = (try? c.decode(String.self, forKey: .address)) ?? ""
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.building = (try? c.decode(BuildingSettings.self, forKey: .building)) ?? BuildingSettings()
    }
}
