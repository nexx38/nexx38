import Foundation

/// Erkennt automatisch, welche Wände an einen anderen erfassten Raum grenzen –
/// und damit Innenwände sind.
///
/// Warum das die wichtigste Automatik der App ist: Der Scan liefert jede Wand
/// als „außen". Im Feldtest standen bei einem Wohnzimmer 21 Wandstücke auf
/// außen, die Kühllast lag dadurch bei 6261 W statt realistischen ~2400 W.
/// Wer die Räume einer Etage in EINER Sitzung scannt, liefert alle Wände im
/// selben Koordinatensystem – dann lässt sich rein geometrisch bestimmen,
/// welche Wand einer anderen gegenübersteht.
///
/// Bewusst konservativ: Im Zweifel bleibt eine Wand außen. Eine fälschlich
/// als innen markierte Wand macht die Heizlast zu klein – das ist der
/// gefährlichere Fehler (unterdimensionierte Anlage, Kunde friert).
public enum RoomAdjacency {

    /// Größter Abstand zweier Wandmitten, bei dem sie noch als dieselbe
    /// Trennwand gelten. Übliche Innenwände sind 10–25 cm dick; 40 cm lässt
    /// Luft für Scan-Ungenauigkeit, ohne gegenüberliegende Zimmerwände zu
    /// verbinden (Räume sind mindestens ~1,5 m tief).
    public static let maxWallDistanceM: Double = 0.40

    /// Größte Richtungsabweichung zweier Wände in Grad, damit sie als
    /// parallel gelten.
    public static let maxAngleDeg: Double = 12

    /// Mindestanteil der kürzeren Wand, der sich mit der anderen überlappen
    /// muss. Eine Wand, die nur mit der Ecke anstößt, ist keine Trennwand.
    public static let minOverlapRatio: Double = 0.30

    /// Ergebnis je Raum: Indizes der Wände, die an einen Nachbarraum grenzen.
    public struct Result: Sendable {
        /// roomID → Indizes in `room.walls`, die als Innenwand erkannt wurden.
        public var interiorWallIndices: [UUID: [Int]]
        /// Anzahl der erkannten Wandpaare (für die Rückmeldung an den Nutzer).
        public var pairCount: Int
    }

    /// Sucht in einer Gruppe gemeinsam gescannter Räume alle Wandpaare, die
    /// dieselbe Trennwand von beiden Seiten zeigen.
    ///
    /// Voraussetzung: Alle Räume stammen aus derselben Scan-Sitzung, ihre
    /// `WallPosition` liegen also im selben Koordinatensystem. Räume ohne
    /// Positionen werden übersprungen.
    public static func detect(in rooms: [Room]) -> Result {
        var interior: [UUID: [Int]] = [:]
        var pairs = 0

        // Alle Wände mit Position einsammeln, samt Herkunft.
        var entries: [(roomID: UUID, index: Int, wall: Wall, position: WallPosition)] = []
        for room in rooms {
            for (index, wall) in room.walls.enumerated() {
                if let position = wall.position {
                    entries.append((room.id, index, wall, position))
                }
            }
        }
        guard entries.count >= 2 else { return Result(interiorWallIndices: [:], pairCount: 0) }

        for i in 0..<entries.count {
            for j in (i + 1)..<entries.count {
                let a = entries[i]
                let b = entries[j]
                // Wände desselben Raums bilden keine Trennwand zueinander.
                guard a.roomID != b.roomID else { continue }
                guard areFacing(a.position, b.position) else { continue }

                interior[a.roomID, default: []].append(a.index)
                interior[b.roomID, default: []].append(b.index)
                pairs += 1
            }
        }

        // Doppelte Treffer bereinigen (eine Wand kann an zwei Räume grenzen).
        for (roomID, indices) in interior {
            interior[roomID] = Array(Set(indices)).sorted()
        }
        return Result(interiorWallIndices: interior, pairCount: pairs)
    }

    /// Wendet das Ergebnis an: markierte Wände werden zu Innenwänden.
    /// Wände, die der Nutzer bereits selbst auf innen gestellt hat, bleiben
    /// unberührt – die Automatik überschreibt keine Handarbeit.
    public static func applied(to rooms: [Room]) -> [Room] {
        let result = detect(in: rooms)
        return rooms.map { room in
            guard let indices = result.interiorWallIndices[room.id] else { return room }
            var updated = room
            for index in indices where updated.walls.indices.contains(index) {
                updated.walls[index].isExternal = false
            }
            return updated
        }
    }

    // MARK: - Geometrie

    /// Stehen sich zwei Wandlinien als dieselbe Trennwand gegenüber?
    /// Drei Bedingungen: nahezu parallel, dicht beieinander, und sie
    /// überlappen sich der Länge nach ausreichend.
    public static func areFacing(_ a: WallPosition, _ b: WallPosition) -> Bool {
        let aDX = a.x2 - a.x1, aDZ = a.z2 - a.z1
        let bDX = b.x2 - b.x1, bDZ = b.z2 - b.z1
        let aLen = (aDX * aDX + aDZ * aDZ).squareRoot()
        let bLen = (bDX * bDX + bDZ * bDZ).squareRoot()
        // Sehr kurze Stücke (Nischen, Scan-Schnipsel) nicht verketten.
        guard aLen > 0.3, bLen > 0.3 else { return false }

        // 1) Parallelität über den Winkel zwischen den Richtungen.
        //    |cos| statt cos, weil die Gegenwand entgegengesetzt läuft.
        let cosAngle = abs((aDX * bDX + aDZ * bDZ) / (aLen * bLen))
        let limit = cos(maxAngleDeg * .pi / 180)
        guard cosAngle >= limit else { return false }

        // 2) Abstand: senkrechter Abstand der Mitte von b zur Geraden durch a.
        let bMidX = (b.x1 + b.x2) / 2, bMidZ = (b.z1 + b.z2) / 2
        let distance = abs((bMidX - a.x1) * aDZ - (bMidZ - a.z1) * aDX) / aLen
        guard distance <= maxWallDistanceM else { return false }

        // 3) Überlappung entlang der Wandrichtung: b auf die Achse von a
        //    projizieren und den gemeinsamen Abschnitt messen.
        let ux = aDX / aLen, uz = aDZ / aLen
        func project(_ x: Double, _ z: Double) -> Double {
            (x - a.x1) * ux + (z - a.z1) * uz
        }
        let b1 = project(b.x1, b.z1)
        let b2 = project(b.x2, b.z2)
        let bLow = min(b1, b2), bHigh = max(b1, b2)
        let overlap = min(aLen, bHigh) - max(0, bLow)
        guard overlap > 0 else { return false }

        return overlap >= min(aLen, bLen) * minOverlapRatio
    }
}
