import Foundation

/// Nutzungsprofil eines Raums: setzt mit einem Griff die Norm-Innentemperatur
/// (Heizfall, DIN EN 12831) und die inneren Lasten (Kühlfall, VDI 2078).
///
/// Warum das mehr ist als Bequemlichkeit: Ein Bad wird auf 24 °C ausgelegt
/// statt auf 20 – das sind rund 15 % mehr Heizlast in diesem Raum, und genau
/// das wird beim Aufmaß regelmäßig vergessen. Eine Küche wiederum hat mit
/// Herd und Kühlschrank ein Vielfaches der Gerätelast eines Schlafzimmers.
/// Die Werte sind übliche Auslegungsannahmen für Wohngebäude, keine
/// Messwerte – der Fachbetrieb darf sie im Raum-Editor überschreiben.
public enum UsageProfile: String, Codable, CaseIterable, Sendable {
    case wohnen, schlafen, kueche, bad, buero, flur, keller, lager

    public var label: String {
        switch self {
        case .wohnen:   return "Wohnen / Esszimmer"
        case .schlafen: return "Schlafzimmer"
        case .kueche:   return "Küche"
        case .bad:      return "Bad"
        case .buero:    return "Büro / Arbeitszimmer"
        case .flur:     return "Flur / Diele"
        case .keller:   return "Keller (beheizt)"
        case .lager:    return "Lager / Abstellraum"
        }
    }

    /// Norm-Innentemperatur θ_i im Heizfall (°C).
    public var heatingIndoorTemp: Double {
        switch self {
        case .wohnen, .kueche, .buero: return 20
        case .schlafen:                return 20
        case .bad:                     return 24
        case .flur:                    return 15
        case .keller:                  return 18
        case .lager:                   return 12
        }
    }

    /// Wunsch-Raumtemperatur im Kühlfall (°C). Auslegung meist 26 °C;
    /// Schlafräume werden gern etwas kühler gewünscht.
    public var coolingIndoorTemp: Double {
        switch self {
        case .schlafen: return 25
        case .lager, .keller: return 27
        default: return 26
        }
    }

    /// Typische Personenzahl im Auslegungsfall.
    public var persons: Int {
        switch self {
        case .wohnen:   return 4
        case .schlafen: return 2
        case .kueche:   return 2
        case .bad:      return 1
        case .buero:    return 2
        case .flur, .keller, .lager: return 0
        }
    }

    /// Geräte-/Prozesslast im Raum in W (Kühlfall).
    public var equipmentWatt: Double {
        switch self {
        case .wohnen:   return 300      // Fernseher, Receiver, Kleingeräte
        case .schlafen: return 60
        case .kueche:   return 1500     // Herd, Kühlschrank, Spülmaschine
        case .bad:      return 100
        case .buero:    return 400      // Rechner, Bildschirme, Drucker
        case .flur:     return 0
        case .keller:   return 100
        case .lager:    return 50
        }
    }

    /// Beleuchtung in W/m².
    public var lightingWattPerSqm: Double {
        switch self {
        case .wohnen, .schlafen, .flur: return 6
        case .kueche, .bad:             return 8
        case .buero:                    return 12
        case .keller, .lager:           return 4
        }
    }

    /// Luftwechselrate n in 1/h.
    public var airChangeRate: Double {
        switch self {
        case .bad, .kueche: return 1.0   // Feuchte-/Geruchslast
        case .schlafen:     return 0.6
        case .lager:        return 0.3
        default:            return 0.5
        }
    }

    /// Schreibt das Profil in einen Raum (Heiz- und Kühlseite zugleich).
    /// Geometrie und U-Werte bleiben unberührt – hier geht es nur um Nutzung.
    public func applied(to room: Room) -> Room {
        var r = room
        r.usageProfile = rawValue
        r.indoorTemperature = coolingIndoorTemp
        r.airChangeRate = airChangeRate
        r.internalLoads = InternalLoads(persons: persons,
                                        wattPerPerson: r.internalLoads.wattPerPerson,
                                        equipmentWatt: equipmentWatt,
                                        lightingWattPerSqm: lightingWattPerSqm)
        var heating = r.heating ?? HeatingParameters()
        heating.indoorTemperature = heatingIndoorTemp
        heating.airChangeRate = airChangeRate
        r.heating = heating
        return r
    }

    /// Rät das Profil aus dem Raumnamen – der Scan liefert bei Apple nur
    /// fünf Raumtypen und oft gar keinen, der Name ist der bessere Hinweis.
    public static func guessed(fromName name: String) -> UsageProfile? {
        let n = name.lowercased()
        if n.contains("bad") || n.contains("wc") || n.contains("dusch") { return .bad }
        if n.contains("küche") || n.contains("kueche") { return .kueche }
        if n.contains("schlaf") || n.contains("kinder") { return .schlafen }
        if n.contains("büro") || n.contains("buero") || n.contains("arbeit") { return .buero }
        if n.contains("flur") || n.contains("diele") || n.contains("treppe") { return .flur }
        if n.contains("keller") { return .keller }
        if n.contains("lager") || n.contains("abstell") { return .lager }
        if n.contains("wohn") || n.contains("ess") { return .wohnen }
        return nil
    }
}
