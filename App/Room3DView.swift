import SwiftUI
import SceneKit
import UIKit
import KuehllastCore

/// Eigene, farbige 3D-Ansicht des gescannten Raums (statt Apples weißem
/// CAD-Export): Wände nach Typ eingefärbt, Fenster blau, Türen braun.
/// WÄNDE SIND ANTIPPBAR – Tippen schaltet Außenwand ↔ innen um, wie im
/// 2D-Grundriss, nur räumlich.
struct Room3DScreen: View {
    @Binding var room: Room

    var body: some View {
        VStack(spacing: 8) {
            Room3DView(room: $room)
                // Raumname/Fläche als SwiftUI-Schild statt als SCNText: Material
                // und .primary passen sich hell/dunkel automatisch an und bleiben
                // aus jedem Blickwinkel lesbar – 3D-Text kippt beim Drehen weg.
                .overlay(alignment: .topLeading) { roomBadge }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal)

            Text("Ziehen dreht · Kneifen zoomt · Wand antippen = Außenwand ↔ innen")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                legend(.orange, "außen")
                legend(Color(.systemGray3), "innen")
                legend(.brown, "Erdreich/unbeh.")
                legend(.blue, "Fenster")
            }
            .font(.caption2)
            .padding(.bottom, 8)
        }
        .navigationTitle("3D-Ansicht")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roomBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(room.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(badgeSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(12)
        // Das Schild darf keine Tipper abfangen – darunter liegen die Wände.
        .allowsHitTesting(false)
    }

    private var badgeSubtitle: String {
        let area = String(format: "%.1f", room.floorArea)
        let height = String(format: "%.2f", room.height)
        return "\(area) m² · lichte Höhe \(height) m"
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Grundriss-Hilfstypen

/// Ein Punkt im Grundriss (Meter, Scan-Koordinaten x/z).
private struct PlanPoint {
    var x: Double
    var z: Double
}

/// Ein Wandstück mit fertig ausgerechneter Lage im Grundriss. Der `index` zeigt
/// auf `room.walls` und wird für den Node-Namen `wall-<index>` gebraucht.
private struct WallSegment3D {
    let index: Int
    let wall: Wall
    let x1: Double
    let z1: Double
    let x2: Double
    let z2: Double

    var dx: Double { x2 - x1 }
    var dz: Double { z2 - z1 }
    var length: Double { (dx * dx + dz * dz).squareRoot() }
    var midX: Double { (x1 + x2) / 2 }
    var midZ: Double { (z1 + z2) / 2 }
}

/// Eine Öffnung (Fenster/Tür) in Wandkoordinaten: `offset` = Abstand vom
/// Wandmittelpunkt entlang der Wand, `bottom` = Unterkante über dem Boden.
private struct WallOpening {
    var offset: Double
    var width: Double
    var bottom: Double
    var height: Double
}

private func planDistance(_ ax: Double, _ az: Double, _ bx: Double, _ bz: Double) -> Double {
    let dx = ax - bx
    let dz = az - bz
    return (dx * dx + dz * dz).squareRoot()
}

// MARK: - Raumumriss aus den Wandstücken

/// Baut aus den Wandlinien den echten Raumumriss.
///
/// Warum so umständlich: ein LiDAR-Scan liefert selten einen sauberen Ring.
/// Im echten Datensatz waren es 18–25 Wandstücke, manche nur 13 cm lang, und
/// die Endpunkte benachbarter Stücke lagen Zentimeter auseinander. Darum wird
/// mit wachsender Fangweite mehrfach probiert und das Ergebnis streng geprüft.
/// Fällt die Prüfung durch, meldet die Funktion `nil` – die Ansicht nimmt dann
/// die alte Rechteckplatte. Lieber ein zu einfacher Boden als ein zerfranster.
private enum FloorOutline {

    static func polygon(for segments: [WallSegment3D], boundingBoxArea: Double) -> [PlanPoint]? {
        // Millimeter-Schnipsel verwirren die Kette mehr als sie helfen.
        let usable = segments.filter { $0.length > 0.02 }
        guard usable.count >= 3 else { return nil }

        var totalLength = 0.0
        for segment in usable { totalLength += segment.length }
        guard totalLength > 0.5 else { return nil }

        for tolerance in [0.06, 0.12, 0.22, 0.35] {
            if let ring = chain(usable,
                                tolerance: tolerance,
                                totalLength: totalLength,
                                boundingBoxArea: boundingBoxArea) {
                return ring
            }
        }
        return nil
    }

    /// Hängt die Wandstücke Ende an Ende, bis der Ring wieder am Start ankommt.
    private static func chain(_ segments: [WallSegment3D],
                              tolerance: Double,
                              totalLength: Double,
                              boundingBoxArea: Double) -> [PlanPoint]? {
        // Beim längsten Stück anfangen: das gehört garantiert zur Außenkontur,
        // ein 13-cm-Schnipsel dagegen kann auch eine Nische sein.
        var startIndex = 0
        for i in segments.indices {
            if segments[i].length > segments[startIndex].length { startIndex = i }
        }

        var used = [Bool](repeating: false, count: segments.count)
        used[startIndex] = true
        var points: [PlanPoint] = [
            PlanPoint(x: segments[startIndex].x1, z: segments[startIndex].z1),
            PlanPoint(x: segments[startIndex].x2, z: segments[startIndex].z2)
        ]
        var usedLength = segments[startIndex].length
        var closed = false

        // Jeder Durchlauf verbraucht genau ein Stück – die Schleife endet sicher.
        for _ in segments.indices {
            let head = points[points.count - 1]
            var bestIndex = -1
            var bestDistance = tolerance
            var bestFlipped = false

            for i in segments.indices where !used[i] {
                let segment = segments[i]
                let d1 = planDistance(segment.x1, segment.z1, head.x, head.z)
                if d1 <= bestDistance {
                    bestDistance = d1
                    bestIndex = i
                    bestFlipped = false
                }
                let d2 = planDistance(segment.x2, segment.z2, head.x, head.z)
                if d2 < bestDistance {
                    bestDistance = d2
                    bestIndex = i
                    bestFlipped = true
                }
            }

            guard bestIndex >= 0 else { break }
            used[bestIndex] = true
            let segment = segments[bestIndex]
            usedLength += segment.length
            points.append(bestFlipped
                          ? PlanPoint(x: segment.x1, z: segment.z1)
                          : PlanPoint(x: segment.x2, z: segment.z2))

            let tail = points[points.count - 1]
            let start = points[0]
            if points.count >= 4,
               planDistance(tail.x, tail.z, start.x, start.z) <= tolerance {
                closed = true
                break
            }
        }

        guard closed else { return nil }

        var ring = points
        ring.removeLast()                      // Schlusspunkt ist wieder der Start
        ring = dedupe(ring, minDistance: 0.03)
        ring = removeCollinear(ring, toleranceDegrees: 4)
        guard ring.count >= 3 else { return nil }

        let area = abs(signedArea(ring))
        // Plausibilität: ein halbwegs richtiger Umriss verbraucht den Großteil
        // der Wandlänge und füllt einen ordentlichen Teil der Bounding-Box.
        // Ein L-Raum kommt auf 60–75 %, ein Fehlgriff auf wenige Prozent.
        guard usedLength >= totalLength * 0.5,
              area >= 0.5,
              boundingBoxArea > 0.01,
              area >= boundingBoxArea * 0.25 else { return nil }

        return ring
    }

    /// Punkte zusammenfassen, die praktisch aufeinander liegen.
    private static func dedupe(_ ring: [PlanPoint], minDistance: Double) -> [PlanPoint] {
        var result: [PlanPoint] = []
        for point in ring {
            if let last = result.last,
               planDistance(point.x, point.z, last.x, last.z) < minDistance {
                continue
            }
            result.append(point)
        }
        while result.count > 3 {
            let first = result[0]
            let last = result[result.count - 1]
            if planDistance(first.x, first.z, last.x, last.z) < minDistance {
                result.removeLast()
            } else {
                break
            }
        }
        return result
    }

    /// Zwischenpunkte auf einer geraden Wand entfernen – sonst hat der Boden
    /// zwanzig Stützpunkte auf einer Kante und die Kanten wirken unruhig.
    private static func removeCollinear(_ ring: [PlanPoint], toleranceDegrees: Double) -> [PlanPoint] {
        guard ring.count > 3 else { return ring }
        let limit = cos(toleranceDegrees * Double.pi / 180)
        var result: [PlanPoint] = []

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
            if cosine < limit { result.append(current) }
        }
        return result.count >= 3 ? result : ring
    }

    static func signedArea(_ ring: [PlanPoint]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var sum = 0.0
        for i in ring.indices {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            sum += a.x * b.z - b.x * a.z
        }
        return sum / 2
    }
}

// MARK: - SceneKit-Ansicht

struct Room3DView: UIViewRepresentable {
    @Binding var room: Room

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        // Eigene Lichter statt Apples Standardlicht – das leuchtet alles flach
        // an und lässt den Raum wie Spielzeugklötze aussehen.
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = Self.backdropColor

        let scene = Self.buildScene(room: room)
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName: "kamera", recursively: true)

        // Drehen wie auf einer Drehscheibe und nicht unter den Boden kippen.
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.minimumVerticalAngle = -5
        view.defaultCameraController.maximumVerticalAngle = 89

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.room = $room
        Self.applyWallColors(scene: view.scene, room: room)
    }

    func makeCoordinator() -> Coordinator { Coordinator(room: $room) }

    final class Coordinator: NSObject {
        var room: Binding<Room>
        weak var view: SCNView?

        init(room: Binding<Room>) { self.room = room }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: nil)

            // Alle Treffer durchgehen und am Knoten hochlaufen: so schaltet auch
            // ein Tipp auf eine Fensterscheibe die Wand dahinter um, statt ins
            // Leere zu greifen.
            for hit in hits {
                var candidate: SCNNode? = hit.node
                while let node = candidate {
                    if let name = node.name, name.hasPrefix("wall-"),
                       let index = Int(name.dropFirst(5)),
                       room.wrappedValue.walls.indices.contains(index) {
                        room.wrappedValue.walls[index].isExternal.toggle()
                        node.geometry?.firstMaterial?.diffuse.contents =
                            Room3DView.wallColor(for: room.wrappedValue.walls[index])
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        return
                    }
                    candidate = node.parent
                }
            }
        }
    }

    // MARK: - Farben und Materialien

    static func wallColor(for wall: Wall) -> UIColor {
        if !wall.isExternal { return UIColor.systemGray3 }
        if wall.adjacentTemp != nil { return UIColor.brown }
        return UIColor.systemOrange
    }

    /// Hintergrund der Szene – als dynamische UIColor, damit der Wechsel auf
    /// Dunkelmodus ohne Neuaufbau der Szene funktioniert.
    static var backdropColor: UIColor {
        return UIColor(dynamicProvider: { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
            }
            return UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)
        })
    }

    /// Bewusst KEINE dynamische Farbe: SceneKit-Materialien hängen nicht an der
    /// UIKit-Trait-Kette und würden im Dunkelmodus nicht sicher umschalten. Ein
    /// heller Estrichton funktioniert vor beiden Hintergründen.
    private static let floorColor = UIColor(red: 0.89, green: 0.87, blue: 0.83, alpha: 1)

    private static let wallThickness = 0.10
    private static let floorThickness = 0.06
    /// Scheiben/Türblätter minimal größer als die Aussparung: so verschwinden
    /// ihre Kanten im Mauerwerk und es gibt kein Z-Flimmern an der Laibung.
    private static let paneOversize = 0.02

    /// Jede Wand bekommt ihre EIGENE Material-Instanz – sonst würde das Umfärben
    /// beim Antippen alle Wände auf einmal treffen.
    private static func makeWallMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = color
        // Sehr matt: eine Wand soll wie Putz wirken, nicht wie lackierter Kunststoff.
        material.specular.contents = UIColor(white: 0.14, alpha: 1)
        material.shininess = 0.08
        material.isDoubleSided = true
        return material
    }

    private static func makeGlassMaterial(color: UIColor, transparency: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = color
        material.specular.contents = UIColor(white: 0.85, alpha: 1)
        material.shininess = 0.85
        material.transparency = transparency
        material.isDoubleSided = true
        return material
    }

    private static func makeFloorMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = floorColor
        material.specular.contents = UIColor(white: 0.08, alpha: 1)
        material.shininess = 0.04
        material.isDoubleSided = true
        return material
    }

    /// Alle drei Komponenten müssen denselben Typ haben – SceneKit bietet je eine
    /// Init für Float, Double und CGFloat, gemischt findet der Compiler keine.
    private static func vector(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
        SCNVector3(Float(x), Float(y), Float(z))
    }

    static func applyWallColors(scene: SCNScene?, room: Room) {
        guard let scene else { return }
        for (index, wall) in room.walls.enumerated() {
            if let node = scene.rootNode.childNode(withName: "wall-\(index)", recursively: true) {
                node.geometry?.firstMaterial?.diffuse.contents = wallColor(for: wall)
            }
        }
    }

    // MARK: - Szene bauen

    static func buildScene(room: Room) -> SCNScene {
        let scene = SCNScene()

        var segments: [WallSegment3D] = []
        for (index, wall) in room.walls.enumerated() {
            guard let position = wall.position else { continue }
            segments.append(WallSegment3D(index: index, wall: wall,
                                          x1: position.x1, z1: position.z1,
                                          x2: position.x2, z2: position.z2))
        }

        let roomHeight = room.height > 0.5 ? room.height : 2.5

        // Ohne Grundriss-Koordinaten lässt sich nichts zeichnen – dann wenigstens
        // Licht und Kamera setzen, damit kein schwarzes Loch stehen bleibt.
        guard !segments.isEmpty else {
            addLights(to: scene, center: PlanPoint(x: 0, z: 0), reach: 4)
            addCamera(to: scene, center: PlanPoint(x: 0, z: 0), reach: 4, roomHeight: roomHeight)
            return scene
        }

        var minX = Double.infinity, maxX = -Double.infinity
        var minZ = Double.infinity, maxZ = -Double.infinity
        for segment in segments {
            minX = min(minX, segment.x1, segment.x2)
            maxX = max(maxX, segment.x1, segment.x2)
            minZ = min(minZ, segment.z1, segment.z2)
            maxZ = max(maxZ, segment.z1, segment.z2)
        }
        let spanX = max(maxX - minX, 0.5)
        let spanZ = max(maxZ - minZ, 0.5)
        let center = PlanPoint(x: (minX + maxX) / 2, z: (minZ + maxZ) / 2)

        // Boden: echter Raumumriss, sonst die alte Rechteckplatte.
        let outline = FloorOutline.polygon(for: segments, boundingBoxArea: spanX * spanZ)
        scene.rootNode.addChildNode(makeFloorNode(outline: outline,
                                                  minX: minX, maxX: maxX,
                                                  minZ: minZ, maxZ: maxZ))

        // Fenster und Türen den Wänden zuordnen, in denen sie stecken.
        let openings = collectOpenings(room: room, segments: segments)

        for segment in segments {
            let node = makeWallNode(segment: segment,
                                    roomHeight: roomHeight,
                                    openings: openings[segment.index] ?? [])
            scene.rootNode.addChildNode(node)
        }

        for window in room.windows {
            guard let position = window.position else { continue }
            // Gleiche Untergrenze wie bei der Aussparung, sonst klafft oben eine Fuge.
            let sill = max(0.05, window.sillHeight ?? 0.9)
            let node = makePaneNode(position: position,
                                    width: window.width,
                                    height: window.height,
                                    bottom: sill,
                                    depth: 0.045,
                                    material: makeGlassMaterial(color: UIColor.systemBlue,
                                                                transparency: 0.55))
            node.castsShadow = false
            node.renderingOrder = 10
            scene.rootNode.addChildNode(node)
        }

        for door in room.doors {
            guard let position = door.position else { continue }
            let material = door.isGlazed
                ? makeGlassMaterial(color: UIColor.systemTeal, transparency: 0.6)
                : makeWallMaterial(color: UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1))
            let node = makePaneNode(position: position,
                                    width: door.width,
                                    height: door.height,
                                    bottom: 0,
                                    depth: 0.055,
                                    material: material)
            node.castsShadow = !door.isGlazed
            if door.isGlazed { node.renderingOrder = 10 }
            scene.rootNode.addChildNode(node)
        }

        addLights(to: scene, center: center, reach: max(spanX, spanZ))
        addCamera(to: scene, center: center, reach: max(spanX, spanZ), roomHeight: roomHeight)

        return scene
    }

    // MARK: - Boden

    private static func makeFloorNode(outline: [PlanPoint]?,
                                      minX: Double, maxX: Double,
                                      minZ: Double, maxZ: Double) -> SCNNode {
        let material = makeFloorMaterial()

        if let ring = outline, ring.count >= 3 {
            let path = UIBezierPath()
            // Der Boden wird gleich um -90° um X gekippt; dabei wird aus der
            // Pfad-Y-Achse die negative Grundriss-Z-Achse. Darum hier -z.
            path.move(to: CGPoint(x: ring[0].x, y: -ring[0].z))
            for i in 1..<ring.count {
                path.addLine(to: CGPoint(x: ring[i].x, y: -ring[i].z))
            }
            path.close()
            path.flatness = 0.005

            let shape = SCNShape(path: path, extrusionDepth: CGFloat(floorThickness))
            // Vorder-, Rück- und Mantelfläche bekommen dasselbe Material.
            shape.materials = [material, material, material]

            let node = SCNNode(geometry: shape)
            node.eulerAngles.x = -Float.pi / 2
            // Der Pfad trägt die Weltkoordinaten schon in sich, der Knoten muss
            // nur noch so tief sitzen, dass die Oberkante genau auf y = 0 liegt.
            node.position = vector(0, -floorThickness / 2, 0)
            node.castsShadow = false
            return node
        }

        // Rückfallebene: die bewährte Rechteckplatte über der Bounding-Box.
        let box = SCNBox(width: CGFloat(maxX - minX + 0.3),
                         height: CGFloat(floorThickness),
                         length: CGFloat(maxZ - minZ + 0.3),
                         chamferRadius: 0)
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.position = vector((minX + maxX) / 2, -floorThickness / 2, (minZ + maxZ) / 2)
        node.castsShadow = false
        return node
    }

    // MARK: - Wände

    private static func makeWallNode(segment: WallSegment3D,
                                     roomHeight: Double,
                                     openings: [WallOpening]) -> SCNNode {
        // Kleine Scan-Schwankungen glätten: 2,48 m neben 2,51 m sieht von außen
        // ausgefranst aus. Echte Abweichungen (halbhohe Brüstung) bleiben stehen.
        let rawHeight = segment.wall.height > 0.3 ? segment.wall.height : roomHeight
        let height = abs(rawHeight - roomHeight) < 0.4 ? roomHeight : rawHeight

        // Beide Enden um die halbe Wanddicke verlängern, damit sich benachbarte
        // Wände in der Ecke überlappen statt eine Fuge stehen zu lassen.
        let length = max(0.05, segment.length) + wallThickness

        let material = makeWallMaterial(color: wallColor(for: segment.wall))

        // Nur eindeutig platzierbare Öffnungen ausschneiden. Eine Aussparung,
        // die den Wandrand berührt, bringt die Triangulierung durcheinander –
        // deshalb überall ein paar Zentimeter Sicherheitsabstand verlangen.
        let cutouts = openings.filter { opening in
            opening.width > 0.15
                && opening.height > 0.15
                && opening.bottom > 0.02
                && opening.bottom + opening.height < height - 0.05
                && abs(opening.offset) + opening.width / 2 < length / 2 - 0.06
        }

        let geometry: SCNGeometry
        let yOffset: Double

        if cutouts.isEmpty {
            let box = SCNBox(width: CGFloat(length),
                             height: CGFloat(height),
                             length: CGFloat(wallThickness),
                             chamferRadius: 0)
            box.materials = [material]
            geometry = box
            yOffset = height / 2          // SCNBox sitzt um seinen Mittelpunkt
        } else {
            // Even-Odd-Regel: die inneren Rechtecke werden zu echten Löchern.
            let path = UIBezierPath(rect: CGRect(x: -length / 2, y: 0,
                                                 width: length, height: height))
            for opening in cutouts {
                path.append(UIBezierPath(rect: CGRect(x: opening.offset - opening.width / 2,
                                                      y: opening.bottom,
                                                      width: opening.width,
                                                      height: opening.height)))
            }
            path.usesEvenOddFillRule = true
            path.flatness = 0.005

            let shape = SCNShape(path: path, extrusionDepth: CGFloat(wallThickness))
            shape.materials = [material, material, material]
            geometry = shape
            yOffset = 0                   // SCNShape-Pfad beginnt schon bei y = 0
        }

        let node = SCNNode(geometry: geometry)
        node.name = "wall-\(segment.index)"
        node.position = vector(segment.midX, yOffset, segment.midZ)
        node.eulerAngles.y = -Float(atan2(segment.dz, segment.dx))
        node.castsShadow = true
        return node
    }

    // MARK: - Fenster und Türen

    /// Sammelt Fenster und Türen und rechnet sie in Wandkoordinaten um.
    private static func collectOpenings(room: Room,
                                        segments: [WallSegment3D]) -> [Int: [WallOpening]] {
        var result: [Int: [WallOpening]] = [:]

        for window in room.windows {
            guard let position = window.position else { continue }
            // Fensterbank etwas anheben, falls sie im Scan bei 0 landet – sonst
            // stößt die Aussparung an die Wandunterkante.
            let sill = max(0.05, window.sillHeight ?? 0.9)
            if let hit = assign(position: position,
                                width: window.width,
                                bottom: sill,
                                height: window.height,
                                segments: segments) {
                result[hit.wallIndex, default: []].append(hit.opening)
            }
        }

        for door in room.doors {
            guard let position = door.position else { continue }
            // Türen stehen auf dem Boden; die Aussparung bekommt trotzdem eine
            // 3-cm-Schwelle, damit sie den Wandrand nicht berührt.
            if let hit = assign(position: position,
                                width: door.width,
                                bottom: 0.03,
                                height: max(0.2, door.height - 0.03),
                                segments: segments) {
                result[hit.wallIndex, default: []].append(hit.opening)
            }
        }

        return result
    }

    /// Sucht die Wand, in der die Öffnung liegt. Verlangt wird: parallel zur
    /// Wand, dicht an der Wandlinie und komplett innerhalb des Wandstücks.
    /// Bei allem anderen lieber kein Loch als eins an der falschen Stelle –
    /// die Scheibe wird ja ohnehin zusätzlich gezeichnet.
    private static func assign(position: WallPosition,
                               width: Double,
                               bottom: Double,
                               height: Double,
                               segments: [WallSegment3D]) -> (wallIndex: Int, opening: WallOpening)? {
        let dx = position.x2 - position.x1
        let dz = position.z2 - position.z1
        let ownLength = (dx * dx + dz * dz).squareRoot()
        guard ownLength > 0.05 else { return nil }
        let axisX = dx / ownLength
        let axisZ = dz / ownLength

        let centerX = (position.x1 + position.x2) / 2
        let centerZ = (position.z1 + position.z2) / 2

        var bestIndex = -1
        var bestDistance = Double.infinity
        var bestOffset = 0.0

        for segment in segments {
            let length = segment.length
            // Ein 13-cm-Schnipsel trägt kein Fenster – solche Stücke überspringen.
            guard length > 0.4 else { continue }
            let ux = segment.dx / length
            let uz = segment.dz / length

            // Öffnung muss in der Wandebene liegen (parallel, ±30°).
            guard abs(ux * axisX + uz * axisZ) > 0.85 else { continue }

            let along = (centerX - segment.x1) * ux + (centerZ - segment.z1) * uz
            guard along > 0, along < length else { continue }

            let perpendicular = abs((centerX - segment.x1) * (-uz) + (centerZ - segment.z1) * ux)
            guard perpendicular < 0.4 else { continue }

            if perpendicular < bestDistance {
                bestDistance = perpendicular
                bestIndex = segment.index
                bestOffset = along - length / 2
            }
        }

        guard bestIndex >= 0 else { return nil }
        return (bestIndex, WallOpening(offset: bestOffset, width: width,
                                       bottom: bottom, height: height))
    }

    /// Scheibe bzw. Türblatt: dünner als die Wand und mittig darin – dadurch
    /// entsteht auf beiden Seiten eine Laibung und es wirkt wie eingesetzt.
    private static func makePaneNode(position: WallPosition,
                                     width: Double,
                                     height: Double,
                                     bottom: Double,
                                     depth: Double,
                                     material: SCNMaterial) -> SCNNode {
        let box = SCNBox(width: CGFloat(max(0.05, width + paneOversize)),
                         height: CGFloat(max(0.05, height + paneOversize)),
                         length: CGFloat(depth),
                         chamferRadius: 0)
        box.materials = [material]

        let node = SCNNode(geometry: box)
        node.position = vector((position.x1 + position.x2) / 2,
                               bottom + height / 2,
                               (position.z1 + position.z2) / 2)
        node.eulerAngles.y = -Float(atan2(position.z2 - position.z1,
                                          position.x2 - position.x1))
        return node
    }

    // MARK: - Licht und Kamera

    private static func addLights(to scene: SCNScene, center: PlanPoint, reach: Double) {
        // Grundlicht, damit die abgewandten Seiten nicht absaufen.
        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 1.0, alpha: 1.0)
        ambient.intensity = 430
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Hauptlicht schräg von oben. Der weiche Schlagschatten ist der eigentliche
        // Grund, warum das Bild räumlich wirkt statt wie ein flacher Klötzchenhaufen.
        let keyNode = SCNNode()
        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(white: 1.0, alpha: 1.0)
        key.intensity = 780
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowColor = UIColor(white: 0.0, alpha: 0.30)
        key.shadowRadius = 6
        key.shadowSampleCount = 16
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.automaticallyAdjustsShadowProjection = true
        keyNode.light = key
        keyNode.position = vector(center.x, reach * 2 + 6, center.z)
        keyNode.eulerAngles = vector(-Double.pi / 3.1, Double.pi / 5, 0)
        scene.rootNode.addChildNode(keyNode)

        // Aufheller von der Gegenseite, ohne Schatten – nimmt den harten Kontrast.
        let fillNode = SCNNode()
        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(white: 1.0, alpha: 1.0)
        fill.intensity = 250
        fill.castsShadow = false
        fillNode.light = fill
        fillNode.eulerAngles = vector(-Double.pi / 7, -Double.pi * 0.7, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    private static func addCamera(to scene: SCNScene, center: PlanPoint,
                                  reach: Double, roomHeight: Double) {
        let camera = SCNCamera()
        camera.fieldOfView = 52
        camera.zNear = 0.05
        camera.zFar = 400

        let node = SCNNode()
        node.name = "kamera"
        node.camera = camera
        // Leicht seitlich statt frontal: die 3/4-Ansicht zeigt Ecken und
        // Tiefenstaffelung, eine frontale Sicht zeigt nur flache Wandflächen.
        let distance = reach * 1.15 + 2.4
        node.position = vector(center.x + distance * 0.45,
                               reach * 0.7 + roomHeight + 1.2,
                               center.z + distance * 0.85)
        node.look(at: vector(center.x, roomHeight * 0.35, center.z))
        scene.rootNode.addChildNode(node)
    }
}
