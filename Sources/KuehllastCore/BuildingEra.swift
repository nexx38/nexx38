import Foundation

/// Baujahr-Klasse eines Gebäudes mit typischen U-Werten der Bauteile.
///
/// Die Werte sind übliche Anhaltswerte für unsanierte Gebäude der jeweiligen
/// Epoche (angelehnt an die bekannten Sanierungs-/Bauteiltabellen, u. a.
/// WSchV 77/84/95, EnEV, GEG). Sie sind AN­NAHMEN für das Kurzverfahren –
/// der PDF-Bericht weist sie entsprechend aus („vom Fachbetrieb zu prüfen").
public enum BuildingEra: String, Codable, CaseIterable, Sendable {
    case vor1949   = "vor1949"
    case bis1968   = "1949_1968"
    case bis1978   = "1969_1978"
    case bis1994   = "1979_1994"
    case bis2001   = "1995_2001"
    case bis2015   = "2002_2015"
    case ab2016    = "ab2016"

    public var label: String {
        switch self {
        case .vor1949: return "vor 1949"
        case .bis1968: return "1949–1968"
        case .bis1978: return "1969–1978"
        case .bis1994: return "1979–1994 (WSchV 77/84)"
        case .bis2001: return "1995–2001 (WSchV 95)"
        case .bis2015: return "2002–2015 (EnEV)"
        case .ab2016:  return "ab 2016 (EnEV/GEG)"
        }
    }

    /// U-Wert Außenwand in W/(m²K).
    public var wallU: Double {
        switch self {
        case .vor1949: return 1.7
        case .bis1968: return 1.4
        case .bis1978: return 1.0
        case .bis1994: return 0.8
        case .bis2001: return 0.5
        case .bis2015: return 0.35
        case .ab2016:  return 0.24
        }
    }

    /// U-Wert Fenster (Verglasung + Rahmen) in W/(m²K).
    public var windowU: Double {
        switch self {
        case .vor1949, .bis1968: return 2.7
        case .bis1978:           return 2.6
        case .bis1994:           return 2.6
        case .bis2001:           return 1.8
        case .bis2015:           return 1.3
        case .ab2016:            return 1.1
        }
    }

    /// Gesamtenergiedurchlassgrad g der epochentypischen Verglasung.
    public var windowG: Double {
        switch self {
        case .vor1949, .bis1968, .bis1978: return 0.8   // Einfach-/frühes Isolierglas
        case .bis1994:                     return 0.75
        case .bis2001:                     return 0.7
        case .bis2015:                     return 0.6
        case .ab2016:                      return 0.55
        }
    }

    /// U-Wert massive Außentür in W/(m²K).
    public var doorU: Double {
        switch self {
        case .vor1949, .bis1968: return 3.0
        case .bis1978, .bis1994: return 2.5
        case .bis2001:           return 2.0
        case .bis2015:           return 1.8
        case .ab2016:            return 1.3
        }
    }

    /// U-Wert Dach / oberste Geschossdecke in W/(m²K).
    public var roofU: Double {
        switch self {
        case .vor1949, .bis1968: return 1.4
        case .bis1978:           return 0.8
        case .bis1994:           return 0.5
        case .bis2001:           return 0.4
        case .bis2015:           return 0.25
        case .ab2016:            return 0.2
        }
    }

    /// U-Wert Boden / Kellerdecke in W/(m²K).
    public var floorU: Double {
        switch self {
        case .vor1949: return 1.2
        case .bis1968: return 1.0
        case .bis1978: return 0.9
        case .bis1994: return 0.8
        case .bis2001: return 0.6
        case .bis2015: return 0.4
        case .ab2016:  return 0.3
        }
    }

    /// Überträgt die Vorgaben dieser Klasse auf alle Bauteile des Raums.
    /// Decke/Boden werden nur überschrieben, wenn sie bereits angesetzt sind
    /// (nur das oberste Geschoss hat eine Außendecke – das entscheidet der
    /// Nutzer über das Setzen des U-Werts, nicht die Baujahr-Klasse).
    public func applied(to room: Room) -> Room {
        var r = room
        r.constructionEra = rawValue
        r.walls = r.walls.map { wall in
            var w = wall
            w.uValue = wallU
            return w
        }
        r.windows = r.windows.map { win in
            var w = win
            w.uValue = windowU
            w.gValue = windowG
            return w
        }
        r.doors = r.doors.map { door in
            var d = door
            d.uValue = d.isGlazed ? windowU : doorU
            if d.isGlazed { d.gValue = windowG }
            return d
        }
        if var h = r.heating {
            if h.ceilingUValue != nil { h.ceilingUValue = roofU }
            if h.floorUValue != nil { h.floorUValue = floorU }
            r.heating = h
        }
        return r
    }
}

/// Plausibilitätsprüfung der flächenspezifischen Last (W/m²).
/// Liefert `nil`, wenn der Wert im üblichen Band liegt, sonst einen
/// deutschen Hinweistext für App und PDF.
public enum Plausibility {

    /// Übliche Bandbreite der Kühllast von Wohn-/Büroräumen in W/m².
    public static let coolingBand: ClosedRange<Double> = 40...200
    /// Übliche Bandbreite der Heizlast (Neubau bis unsanierter Altbau) in W/m².
    public static let heatingBand: ClosedRange<Double> = 30...150

    public static func coolingNote(specific v: Double) -> String? {
        note(specific: v, band: coolingBand,
             lowHint: "Eingaben prüfen: Fenster erfasst? Ausrichtung gesetzt?",
             highHint: "Verschattung, g-Werte und Flächen prüfen.")
    }

    public static func heatingNote(specific v: Double) -> String? {
        note(specific: v, band: heatingBand,
             lowHint: "Eingaben prüfen: Außenbauteile und U-Werte gesetzt?",
             highHint: "U-Werte und Außenflächen prüfen.")
    }

    /// Übliche lichte Raumhöhe in Wohngebäuden; darüber ist es entweder eine
    /// Galerie/Halle oder – viel häufiger – ein verunglückter Scan.
    public static let plausibleRoomHeight: ClosedRange<Double> = 2.0...3.2
    /// Übliche Höhe von Türen und Terrassen-/Schiebetüren.
    public static let plausibleDoorHeight = 2.6

    /// Prüft die GEOMETRIE eines gescannten Raums auf offensichtlich falsche
    /// Maße. Hintergrund: RoomPlan zieht Wände bis unter die obere Decke, wenn
    /// beim Scannen ein offener Treppenraum oder eine Galerie im Bild war –
    /// dann kommt der halbe Raum in doppelter Höhe heraus und Heiz- wie
    /// Kühllast sind stillschweigend etwa doppelt so hoch. Genau das ist im
    /// Feldtest passiert (2,62 m realer Raum als 4,76 m erfasst).
    /// Liefert die Fundstellen als fertige deutsche Hinweistexte.
    public static func geometryNotes(for room: Room) -> [String] {
        var notes: [String] = []

        if room.height > plausibleRoomHeight.upperBound {
            notes.append(String(format: "Raumhöhe %.2f m ist für einen Wohnraum ungewöhnlich hoch. "
                                + "Beim Scan durch einen offenen Treppenraum gefilmt? Höhe nachmessen.",
                                room.height))
        } else if room.height < plausibleRoomHeight.lowerBound {
            notes.append(String(format: "Raumhöhe %.2f m ist ungewöhnlich niedrig – bitte nachmessen.",
                                room.height))
        }

        let tallDoors = room.doors.filter { $0.height > plausibleDoorHeight }
        if let highest = tallDoors.map({ $0.height }).max() {
            notes.append(String(format: "%d Tür(en) über %.1f m hoch (höchste %.2f m). "
                                + "Übliche Terrassen-/Schiebetüren sind ~2,20 m – Maße prüfen.",
                                tallDoors.count, plausibleDoorHeight, highest))
        }

        // Wandhöhen, die stark von der Raumhöhe abweichen, deuten auf
        // Wandstücke aus einem anderen Geschoss hin.
        let strays = room.walls.filter { abs($0.height - room.height) > 0.5 }
        if !strays.isEmpty {
            notes.append("\(strays.count) Wandstück(e) weichen deutlich von der Raumhöhe ab.")
        }

        return notes
    }

    private static func note(specific v: Double, band: ClosedRange<Double>,
                             lowHint: String, highHint: String) -> String? {
        if v < band.lowerBound {
            return String(format: "%.0f W/m² ist ungewöhnlich niedrig (üblich %.0f–%.0f W/m²). %@",
                          v, band.lowerBound, band.upperBound, lowHint)
        }
        if v > band.upperBound {
            return String(format: "%.0f W/m² ist ungewöhnlich hoch (üblich %.0f–%.0f W/m²). %@",
                          v, band.lowerBound, band.upperBound, highHint)
        }
        return nil
    }
}
