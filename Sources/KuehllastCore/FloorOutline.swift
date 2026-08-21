import Foundation

/// Grundriss-Geometrie für die 3D-Ansicht.
///
/// Warum liegt das hier und nicht in der App: Auf einem Windows-Rechner läuft
/// kein Swift, und die CI führt nur `swift test` auf diesem Package aus. Alles,
/// was in `App/` steht, ist damit ungetestet. Diese Datei enthält deshalb genau
/// die Rechnungen, bei denen ein Fehler ein kaputtes Bild erzeugt – und sie ist
/// bewusst frei von SceneKit/UIKit (nur Foundation), damit sie testbar bleibt.

// MARK: - Punkt

/// Ein Punkt im Grundriss (Meter, Scan-Koordinaten x/z – y ist die Höhe).
public struct FloorPoint: Hashable, Sendable {
    public var x: Double
    public var z: Double

    public init(x: Double, z: Double) {
        self.x = x
        self.z = z
    }
}

// MARK: - Raumumriss

/// Baut aus den einzelnen Wandlinien den geschlossenen Raumumriss.
///
/// Ein LiDAR-Scan liefert selten einen sauberen Ring: im Feldtest waren es 21
/// Wandstücke, manche nur 13 cm lang, und die Endpunkte benachbarter Stücke
/// lagen bis zu 13 cm auseinander. Darum wird mit wachsender Fangweite mehrfach
/// probiert und das Ergebnis streng geprüft. Fällt die Prüfung durch, kommt
/// `nil` zurück – die Ansicht nimmt dann die schlichte Rechteckplatte.
/// Lieber schlicht als kaputt.
public enum FloorOutline {

    /// Fangweiten in Metern, in dieser Reihenfolge probiert. Klein anfangen,
    /// damit ein sauberer Scan nicht unnötig Punkte zusammenzieht.
    private static let tolerances: [Double] = [0.06, 0.12, 0.22, 0.35]

    /// Liefert den Raumumriss oder `nil`, wenn kein verlässlicher Ring entsteht.
    public static func polygon(from walls: [WallPosition]) -> [FloorPoint]? {
        // Millimeter-Schnipsel verwirren die Kette mehr als sie helfen.
        let usable = walls.filter { length(of: $0) > 0.02 }
        guard usable.count >= 3 else { return nil }

        var totalLength = 0.0
        for wall in usable { totalLength += length(of: wall) }
        guard totalLength > 0.5 else { return nil }

        let box = boundingBoxArea(of: usable)

        for tolerance in tolerances {
            if let ring = chain(usable,
                                tolerance: tolerance,
                                totalLength: totalLength,
                                boundingBoxArea: box) {
                return ring
            }
        }
        return nil
    }

    /// Fläche eines geschlossenen Polygons (Gaußsche Trapezformel), immer positiv.
    /// Die Umlaufrichtung spielt keine Rolle.
    public static func area(of ring: [FloorPoint]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var sum = 0.0
        for i in ring.indices {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            sum += a.x * b.z - b.x * a.z
        }
        return abs(sum) / 2
    }

    /// Überkreuzt sich der geschlossene Streckenzug selbst?
    ///
    /// Apple schreibt zu `SCNShape` ausdrücklich: „The result of extruding a
    /// self-intersecting path is undefined." Genau das passiert bei vielen
    /// kurzen Wandstücken schnell – die Kette läuft in die falsche Nische und
    /// kreuzt sich. Deshalb muss dieser Fall VOR dem Zeichnen auffallen.
    ///
    /// Geprüft werden alle nicht benachbarten Kantenpaare (O(n²) ist bei unter
    /// 50 Punkten belanglos). Benachbarte Kanten teilen sich per Definition
    /// einen Endpunkt und zählen nicht als Schnitt.
    public static func isSelfIntersecting(_ ring: [FloorPoint], tolerance: Double = 0.001) -> Bool {
        let n = ring.count
        guard n >= 4 else { return false }

        for i in 0..<n {
            let a1 = ring[i]
            let a2 = ring[(i + 1) % n]
            for j in (i + 1)..<n {
                if j == i + 1 { continue }                 // direkt benachbart
                if i == 0 && j == n - 1 { continue }        // über den Ringschluss benachbart
                let b1 = ring[j]
                let b2 = ring[(j + 1) % n]
                if segmentDistance(a1, a2, b1, b2) < tolerance { return true }
            }
        }
        return false
    }

    // MARK: - Kette bauen

    /// Hängt die Wandstücke Ende an Ende, bis der Ring wieder am Start ankommt.
    private static func chain(_ walls: [WallPosition],
                              tolerance: Double,
                              totalLength: Double,
                              boundingBoxArea: Double) -> [FloorPoint]? {
        // Beim längsten Stück anfangen: das gehört garantiert zur Außenkontur,
        // ein 13-cm-Schnipsel dagegen kann auch eine Nische sein.
        var startIndex = 0
        for i in walls.indices {
            if length(of: walls[i]) > length(of: walls[startIndex]) { startIndex = i }
        }

        var used = [Bool](repeating: false, count: walls.count)
        used[startIndex] = true
        var points: [FloorPoint] = [
            FloorPoint(x: walls[startIndex].x1, z: walls[startIndex].z1),
            FloorPoint(x: walls[startIndex].x2, z: walls[startIndex].z2)
        ]
        var usedLength = length(of: walls[startIndex])
        var closed = false

        // Jeder Durchlauf verbraucht höchstens ein Stück – die Schleife endet sicher.
        for _ in walls.indices {
            let head = points[points.count - 1]
            var bestIndex = -1
            var bestDistance = tolerance
            var bestFlipped = false

            for i in walls.indices where !used[i] {
                let wall = walls[i]
                let toStart = distance(wall.x1, wall.z1, head.x, head.z)
                if toStart <= bestDistance {
                    bestDistance = toStart
                    bestIndex = i
                    bestFlipped = false
                }
                let toEnd = distance(wall.x2, wall.z2, head.x, head.z)
                if toEnd < bestDistance {
                    bestDistance = toEnd
                    bestIndex = i
                    bestFlipped = true
                }
            }

            guard bestIndex >= 0 else { break }
            used[bestIndex] = true
            let wall = walls[bestIndex]
            usedLength += length(of: wall)
            // Umgedreht angehängt heißt: wir sind bei x2/z2 eingestiegen, der
            // neue Kettenkopf ist x1/z1.
            points.append(bestFlipped
                          ? FloorPoint(x: wall.x1, z: wall.z1)
                          : FloorPoint(x: wall.x2, z: wall.z2))

            let tail = points[points.count - 1]
            let start = points[0]
            if points.count >= 4, distance(tail.x, tail.z, start.x, start.z) <= tolerance {
                closed = true
                break
            }
        }

        guard closed else { return nil }

        var ring = points
        ring.removeLast()                       // Schlusspunkt ist wieder der Start
        ring = dedupe(ring, minDistance: 0.03)
        ring = removeCollinear(ring, toleranceDegrees: 4)
        guard ring.count >= 3 else { return nil }

        // Plausibilität: ein halbwegs richtiger Umriss verbraucht den Großteil
        // der Wandlänge und füllt einen ordentlichen Teil der Bounding-Box.
        // Ein L-Raum kommt auf 60–80 %, ein Fehlgriff auf wenige Prozent.
        let polygonArea = area(of: ring)
        guard usedLength >= totalLength * 0.5,
              polygonArea >= 0.5,
              boundingBoxArea > 0.01,
              polygonArea >= boundingBoxArea * 0.25 else { return nil }

        // Zum Schluss der wichtigste Test: ein überkreuzter Ring wird von
        // SceneKit undefiniert extrudiert. Dann lieber gar kein Polygon.
        guard !isSelfIntersecting(ring) else { return nil }

        return ring
    }

    // MARK: - Punktbereinigung

    /// Punkte zusammenfassen, die praktisch aufeinander liegen.
    static func dedupe(_ ring: [FloorPoint], minDistance: Double) -> [FloorPoint] {
        var result: [FloorPoint] = []
        for point in ring {
            if let last = result.last,
               distance(point.x, point.z, last.x, last.z) < minDistance {
                continue
            }
            result.append(point)
        }
        while result.count > 3 {
            let first = result[0]
            let last = result[result.count - 1]
            if distance(first.x, first.z, last.x, last.z) < minDistance {
                result.removeLast()
            } else {
                break
            }
        }
        return result
    }

    /// Zwischenpunkte auf einer geraden Wand entfernen – sonst hat der Boden
    /// zwanzig Stützpunkte auf einer Kante und die Kanten wirken unruhig.
    static func removeCollinear(_ ring: [FloorPoint], toleranceDegrees: Double) -> [FloorPoint] {
        guard ring.count > 3 else { return ring }
        let limit = cos(toleranceDegrees * Double.pi / 180)
        var result: [FloorPoint] = []

        for i in ring.indices {
            let previous = ring[(i - 1 + ring.count) % ring.count]
            let current = ring[i]
            let next = ring[(i + 1) % ring.count]
            let ax = current.x - previous.x
            let az = current.z - previous.z
            let bx = next.x - current.x
            let bz = next.z - current.z
            let la = (ax * ax + az * az).squareRoot()
            let lb = (bx * bx + bz * bz).squareRoot()
            if la < 0.000001 || lb < 0.000001 { continue }
            let cosine = (ax * bx + az * bz) / (la * lb)
            if cosine < limit { result.append(current) }    // echte Ecke
        }
        return result.count >= 3 ? result : ring
    }

    // MARK: - Elementare Geometrie

    static func length(of wall: WallPosition) -> Double {
        let dx = wall.x2 - wall.x1
        let dz = wall.z2 - wall.z1
        return (dx * dx + dz * dz).squareRoot()
    }

    static func boundingBoxArea(of walls: [WallPosition]) -> Double {
        guard !walls.isEmpty else { return 0 }
        var minX = Double.infinity, maxX = -Double.infinity
        var minZ = Double.infinity, maxZ = -Double.infinity
        for wall in walls {
            minX = min(minX, wall.x1, wall.x2)
            maxX = max(maxX, wall.x1, wall.x2)
            minZ = min(minZ, wall.z1, wall.z2)
            maxZ = max(maxZ, wall.z1, wall.z2)
        }
        guard minX.isFinite, maxX.isFinite, minZ.isFinite, maxZ.isFinite else { return 0 }
        return max(0, maxX - minX) * max(0, maxZ - minZ)
    }

    private static func distance(_ ax: Double, _ az: Double, _ bx: Double, _ bz: Double) -> Double {
        let dx = ax - bx
        let dz = az - bz
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Kreuzprodukt (b−a) × (c−a): Vorzeichen sagt, auf welcher Seite von a→b
    /// der Punkt c liegt.
    private static func cross(_ a: FloorPoint, _ b: FloorPoint, _ c: FloorPoint) -> Double {
        (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
    }

    /// Echter Überkreuzungstest (ohne Berührungen – die fängt der Endpunkt-
    /// Abstand darunter ab).
    private static func properlyCross(_ p1: FloorPoint, _ p2: FloorPoint,
                                      _ q1: FloorPoint, _ q2: FloorPoint) -> Bool {
        let d1 = cross(q1, q2, p1)
        let d2 = cross(q1, q2, p2)
        let d3 = cross(p1, p2, q1)
        let d4 = cross(p1, p2, q2)
        let pSplit = (d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)
        let qSplit = (d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)
        return pSplit && qSplit
    }

    /// Kleinster Abstand zwischen zwei Strecken. Kreuzen sie sich, ist er null;
    /// sonst wird er immer an einem der vier Endpunkte angenommen.
    private static func segmentDistance(_ p1: FloorPoint, _ p2: FloorPoint,
                                        _ q1: FloorPoint, _ q2: FloorPoint) -> Double {
        if properlyCross(p1, p2, q1, q2) { return 0 }
        var best = pointSegmentDistance(p1, q1, q2)
        best = min(best, pointSegmentDistance(p2, q1, q2))
        best = min(best, pointSegmentDistance(q1, p1, p2))
        best = min(best, pointSegmentDistance(q2, p1, p2))
        return best
    }

    private static func pointSegmentDistance(_ p: FloorPoint,
                                             _ a: FloorPoint,
                                             _ b: FloorPoint) -> Double {
        let abx = b.x - a.x
        let abz = b.z - a.z
        let lengthSquared = abx * abx + abz * abz
        guard lengthSquared > 0.000000001 else {
            return distance(p.x, p.z, a.x, a.z)
        }
        var t = ((p.x - a.x) * abx + (p.z - a.z) * abz) / lengthSquared
        t = max(0, min(1, t))
        return distance(p.x, p.z, a.x + t * abx, a.z + t * abz)
    }
}

// MARK: - Öffnung einer Wand zuordnen

/// Findet heraus, in welchem Wandstück ein gescanntes Fenster bzw. eine Tür steckt.
public enum WallOpeningLocator {

    /// Liefert den Index des Wandstücks und den Abstand der Öffnungsmitte vom
    /// Wandmittelpunkt (entlang der Wand, mit Vorzeichen).
    ///
    /// Verlangt wird: die Öffnung liegt annähernd parallel zur Wand, dicht an
    /// der Wandlinie und mit ihrer Mitte innerhalb des Stücks. Bei allem
    /// anderen lieber `nil` als ein Loch an der falschen Stelle – die Scheibe
    /// wird ja ohnehin zusätzlich gezeichnet.
    public static func locate(opening: WallPosition,
                              in walls: [WallPosition],
                              maxDistance: Double = 0.4,
                              minWallLength: Double = 0.4,
                              minParallelism: Double = 0.85) -> (index: Int, offset: Double)? {
        let dx = opening.x2 - opening.x1
        let dz = opening.z2 - opening.z1
        let ownLength = (dx * dx + dz * dz).squareRoot()
        guard ownLength > 0.05 else { return nil }
        let axisX = dx / ownLength
        let axisZ = dz / ownLength

        let centerX = (opening.x1 + opening.x2) / 2
        let centerZ = (opening.z1 + opening.z2) / 2

        var bestIndex = -1
        var bestDistance = Double.infinity
        var bestOffset = 0.0

        for i in walls.indices {
            let wall = walls[i]
            let wallLength = FloorOutline.length(of: wall)
            // Ein 13-cm-Schnipsel trägt kein Fenster.
            guard wallLength >= minWallLength else { continue }
            let ux = (wall.x2 - wall.x1) / wallLength
            let uz = (wall.z2 - wall.z1) / wallLength

            guard abs(ux * axisX + uz * axisZ) > minParallelism else { continue }

            let along = (centerX - wall.x1) * ux + (centerZ - wall.z1) * uz
            guard along > 0, along < wallLength else { continue }

            let perpendicular = abs((centerX - wall.x1) * (-uz) + (centerZ - wall.z1) * ux)
            guard perpendicular < maxDistance else { continue }

            if perpendicular < bestDistance {
                bestDistance = perpendicular
                bestIndex = i
                bestOffset = along - wallLength / 2
            }
        }

        guard bestIndex >= 0 else { return nil }
        return (bestIndex, bestOffset)
    }
}

// MARK: - Aussparungen in einer Wand

/// Eine Aussparung in Wandkoordinaten: `offset` = Abstand von der Wandmitte
/// entlang der Wand, `bottom` = Unterkante über dem Fußboden. Alles in Metern.
public struct WallCutout: Hashable, Sendable {
    public var offset: Double
    public var width: Double
    public var bottom: Double
    public var height: Double

    public init(offset: Double, width: Double, bottom: Double, height: Double) {
        self.offset = offset
        self.width = width
        self.bottom = bottom
        self.height = height
    }

    public var area: Double { width * height }
}

/// Entscheidet, welche Aussparungen sich sauber aus einer Wand schneiden lassen.
///
/// Gleiche Ursache wie beim Selbstschnitt des Bodens: Ein Loch, das den Wandrand
/// berührt oder in ein zweites Loch hineinläuft, ergibt einen entarteten Pfad.
/// SceneKit zeichnet dann Unsinn. Was hier durchfällt, wird als geschlossene
/// Wand gezeichnet – unschön, aber nie kaputt.
public enum WallCutoutPlanner {

    public static func usable(_ cutouts: [WallCutout],
                              wallLength: Double,
                              wallHeight: Double,
                              margin: Double = 0.06) -> [WallCutout] {
        guard wallLength > 0, wallHeight > 0 else { return [] }

        // 1. Zu klein oder zu dicht am Wandrand.
        let inside = cutouts.filter { cutout in
            cutout.width > 0.15
                && cutout.height > 0.15
                && cutout.bottom >= margin
                && cutout.bottom + cutout.height <= wallHeight - margin
                && abs(cutout.offset) + cutout.width / 2 <= wallLength / 2 - margin
        }

        // 2. Überschneidungen. Das größere Loch gewinnt – ein Fenster verschwindet
        //    eher als eine Terrassentür.
        let ordered = inside.sorted { lhs, rhs in
            if lhs.area != rhs.area { return lhs.area > rhs.area }
            return lhs.offset < rhs.offset          // stabile Reihenfolge
        }

        var kept: [WallCutout] = []
        for candidate in ordered {
            let conflict = kept.contains { !separated(candidate, $0, margin: margin) }
            if !conflict { kept.append(candidate) }
        }
        return kept.sorted { $0.offset < $1.offset }
    }

    /// Zwei Aussparungen sind sauber getrennt, wenn zwischen ihnen waagerecht
    /// ODER senkrecht mindestens `margin` Mauerwerk stehen bleibt.
    static func separated(_ a: WallCutout, _ b: WallCutout, margin: Double) -> Bool {
        let horizontalGap = abs(a.offset - b.offset) - (a.width + b.width) / 2
        let aCenter = a.bottom + a.height / 2
        let bCenter = b.bottom + b.height / 2
        let verticalGap = abs(aCenter - bCenter) - (a.height + b.height) / 2
        return horizontalGap >= margin || verticalGap >= margin
    }
}

// MARK: - Wandecken

/// Entscheidet, an welchen Enden ein Wandstück verlängert werden darf, damit
/// die Ecke sauber zustößt.
///
/// Verlängert man jede Wand an beiden Enden um die Wanddicke, sieht eine
/// rechtwinklige Ecke gut aus – bei einem spitzen Winkel schieben sich die
/// Wände aber sichtbar ineinander. Deshalb wird nur dort verlängert, wo die
/// Nachbarwand annähernd rechtwinklig anschließt.
public enum WallJoint {

    /// `start` gilt für x1/z1, `end` für x2/z2 des Wandstücks `index`.
    public static func squareEnds(of index: Int,
                                  in walls: [WallPosition],
                                  snapDistance: Double = 0.25,
                                  minAngleDegrees: Double = 65) -> (start: Bool, end: Bool) {
        guard walls.indices.contains(index) else { return (false, false) }
        let wall = walls[index]
        let ownLength = FloorOutline.length(of: wall)
        guard ownLength > 0.000001 else { return (false, false) }
        let ux = (wall.x2 - wall.x1) / ownLength
        let uz = (wall.z2 - wall.z1) / ownLength

        // Rechtwinklig genug heißt: der Winkel liegt zwischen minAngle und
        // 180° − minAngle, das Skalarprodukt der Richtungen also nahe null.
        let limit = abs(cos(minAngleDegrees * Double.pi / 180))

        var start = false
        var end = false

        for other in walls.indices where other != index {
            let neighbour = walls[other]
            let neighbourLength = FloorOutline.length(of: neighbour)
            guard neighbourLength > 0.000001 else { continue }
            let vx = (neighbour.x2 - neighbour.x1) / neighbourLength
            let vz = (neighbour.z2 - neighbour.z1) / neighbourLength
            guard abs(ux * vx + uz * vz) <= limit else { continue }

            if touches(wall.x1, wall.z1, neighbour, within: snapDistance) { start = true }
            if touches(wall.x2, wall.z2, neighbour, within: snapDistance) { end = true }
        }

        return (start, end)
    }

    private static func touches(_ x: Double, _ z: Double,
                                _ wall: WallPosition, within snapDistance: Double) -> Bool {
        let d1 = ((wall.x1 - x) * (wall.x1 - x) + (wall.z1 - z) * (wall.z1 - z)).squareRoot()
        if d1 <= snapDistance { return true }
        let d2 = ((wall.x2 - x) * (wall.x2 - x) + (wall.z2 - z) * (wall.z2 - z)).squareRoot()
        return d2 <= snapDistance
    }
}
