import SwiftUI
import SceneKit
import UIKit
import KuehllastCore

/// Eigene, farbige 3D-Ansicht des gescannten Raums (statt Apples weißem
/// CAD-Export): Wände nach Typ eingefärbt, Fenster blau, Türen braun.
/// WÄNDE SIND ANTIPPBAR – Tippen schaltet Außenwand ↔ innen um, wie im
/// 2D-Grundriss, nur räumlich.
///
/// Die Geometrie (Raumumriss, Zuordnung der Öffnungen, Aussparungen, Ecken)
/// liegt bewusst NICHT hier, sondern in `KuehllastCore/FloorOutline.swift` –
/// nur dort ist sie von der CI testbar. Diese Datei zeichnet nur noch.
struct Room3DScreen: View {
    @Binding var room: Room

    var body: some View {
        VStack(spacing: 8) {
            Room3DView(room: $room)
                // Raumname/Fläche als SwiftUI-Schild statt als SCNText: Material
                // und .primary passen sich hell/dunkel automatisch an und bleiben
                // aus jedem Blickwinkel lesbar – 3D-Text kippt beim Drehen weg.
                .overlay(alignment: .topLeading) { roomBadge }
                .clipShape(RoundedRectangle(cornerRadius: 16))
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

// MARK: - Zeichen-Hilfstypen

/// Ein Wandstück mit Grundriss-Lage. `index` zeigt auf `room.walls` und wird
/// für den Node-Namen `wall-<index>` gebraucht.
private struct PositionedWall {
    let index: Int
    let wall: Wall
    let position: WallPosition
}

/// Fertig ausgerechnete Zeichenvorgaben für ein Wandstück.
private struct WallPlan {
    let index: Int
    /// Länge inklusive der Verlängerung in rechtwinklige Ecken.
    let length: Double
    let height: Double
    let centerX: Double
    let centerZ: Double
    let angle: Double
    /// Um so viel ist die Mitte gegenüber der Segmentmitte gewandert.
    let shift: Double
}

// MARK: - SceneKit-Ansicht

struct Room3DView: UIViewRepresentable {
    @Binding var room: Room

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        // Apples Standardbeleuchtung bleibt die Grundlage – die ist erprobt.
        view.autoenablesDefaultLighting = true
        // Reine Kantenglättung, ändert nichts an Farben oder Licht.
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = UIColor.secondarySystemBackground
        view.scene = Self.buildScene(room: room)

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

    static func applyWallColors(scene: SCNScene?, room: Room) {
        guard let scene else { return }
        for (index, wall) in room.walls.enumerated() {
            if let node = scene.rootNode.childNode(withName: "wall-\(index)", recursively: true) {
                node.geometry?.firstMaterial?.diffuse.contents = wallColor(for: wall)
            }
        }
    }

    /// Wanddicke wie bisher (8 cm) – enge Ecken vertragen nicht mehr.
    private static let wallThickness = 0.08
    private static let floorThickness = 0.05
    private static let floorColor = UIColor(red: 0.93, green: 0.90, blue: 0.85, alpha: 1)

    /// Ein eigenes gerichtetes Licht würde weiche Schlagschatten bringen. ABER:
    /// SceneKit setzt sein Standardlicht laut Doku nur, solange die Szene gar
    /// keine oder nur Ambient-Lichter enthält – ein gerichtetes Licht schaltet
    /// die bewährte Beleuchtung also ab. Ob das besser aussieht, lässt sich nur
    /// am Gerät entscheiden, deshalb steht der Schalter aus. Zum Vergleichen
    /// einfach auf `true` setzen.
    private static let usesOwnShadowLight = false

    /// Schlichtes Material wie in der bewährten Fassung: nur die Farbe wird
    /// gesetzt, alles andere bleibt SceneKit-Standard. Jede Wand braucht eine
    /// EIGENE Instanz, sonst färbt ein Tipp alle Wände gleichzeitig um.
    private static func makeMaterial(_ color: UIColor, doubleSided: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.isDoubleSided = doubleSided
        return material
    }

    /// Alle drei Komponenten müssen denselben Typ haben – SceneKit bietet je eine
    /// Init für Float, Double und CGFloat, gemischt findet der Compiler keine.
    private static func vector(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
        SCNVector3(Float(x), Float(y), Float(z))
    }

    // MARK: - Szene bauen

    static func buildScene(room: Room) -> SCNScene {
        let scene = SCNScene()

        // Nur gescannte Wände haben Grundriss-Koordinaten.
        var positioned: [PositionedWall] = []
        for (index, wall) in room.walls.enumerated() {
            guard let position = wall.position else { continue }
            positioned.append(PositionedWall(index: index, wall: wall, position: position))
        }
        guard !positioned.isEmpty else { return scene }

        let positions = positioned.map { $0.position }
        let roomHeight = room.height > 0.5 ? room.height : 2.5

        // Ausdehnung für Boden-Rückfallebene und Kamera.
        var minX = Double.infinity, maxX = -Double.infinity
        var minZ = Double.infinity, maxZ = -Double.infinity
        for position in positions {
            minX = min(minX, position.x1, position.x2)
            maxX = max(maxX, position.x1, position.x2)
            minZ = min(minZ, position.z1, position.z2)
            maxZ = max(maxZ, position.z1, position.z2)
        }
        let centerX = (minX + maxX) / 2, centerZ = (minZ + maxZ) / 2
        let spanX = maxX - minX, spanZ = maxZ - minZ

        // --- Boden ---
        // `polygon` liefert nur einen Ring, der geschlossen, plausibel groß UND
        // überschneidungsfrei ist. Sonst kommt nil und es bleibt bei der Platte.
        let outline = FloorOutline.polygon(from: positions)
        scene.rootNode.addChildNode(makeFloorNode(outline: outline,
                                                  minX: minX, maxX: maxX,
                                                  minZ: minZ, maxZ: maxZ))

        // --- Wandvorgaben ---
        var plans: [WallPlan] = []
        for arrayIndex in positioned.indices {
            plans.append(makeWallPlan(positioned[arrayIndex],
                                      arrayIndex: arrayIndex,
                                      positions: positions,
                                      roomHeight: roomHeight))
        }

        // --- Öffnungen den Wänden zuordnen ---
        var rawCutouts: [Int: [(id: UUID, cutout: WallCutout)]] = [:]

        for window in room.windows {
            guard let position = window.position else { continue }
            guard let hit = WallOpeningLocator.locate(opening: position, in: positions) else { continue }
            let plan = plans[hit.index]
            let cutout = WallCutout(offset: hit.offset - plan.shift,
                                    width: window.width,
                                    bottom: sillHeight(window.sillHeight),
                                    height: window.height)
            rawCutouts[hit.index, default: []].append((id: window.id, cutout: cutout))
        }

        for door in room.doors {
            guard let position = door.position else { continue }
            guard let hit = WallOpeningLocator.locate(opening: position, in: positions) else { continue }
            let plan = plans[hit.index]
            // Türen stehen auf dem Boden. Die Aussparung bekommt trotzdem eine
            // Schwelle, sonst berührt sie die Wandunterkante und der Pfad entartet.
            let cutout = WallCutout(offset: hit.offset - plan.shift,
                                    width: door.width,
                                    bottom: doorSill,
                                    height: max(0.2, door.height - doorSill))
            rawCutouts[hit.index, default: []].append((id: door.id, cutout: cutout))
        }

        // --- Aussparungen prüfen ---
        // Was hier durchfällt (überlappend, über den Rand hinaus), wird NICHT
        // geschnitten; die Wand bleibt dann geschlossen und die Scheibe wird wie
        // früher als sichtbare Platte davorgesetzt.
        var plannedCutouts: [Int: [WallCutout]] = [:]
        var openingsWithHole: Set<UUID> = []

        for (planIndex, entries) in rawCutouts {
            let plan = plans[planIndex]
            let accepted = WallCutoutPlanner.usable(entries.map { $0.cutout },
                                                   wallLength: plan.length,
                                                   wallHeight: plan.height)
            guard !accepted.isEmpty else { continue }
            plannedCutouts[planIndex] = accepted
            let acceptedSet = Set(accepted)
            for entry in entries where acceptedSet.contains(entry.cutout) {
                openingsWithHole.insert(entry.id)
            }
        }

        // --- Wände ---
        for planIndex in plans.indices {
            let node = makeWallNode(plan: plans[planIndex],
                                    wall: positioned[planIndex].wall,
                                    cutouts: plannedCutouts[planIndex] ?? [])
            scene.rootNode.addChildNode(node)
        }

        // --- Fenster ---
        for window in room.windows {
            guard let position = window.position else { continue }
            let recessed = openingsWithHole.contains(window.id)
            let node = makePaneNode(position: position,
                                    width: window.width,
                                    height: window.height,
                                    bottom: sillHeight(window.sillHeight),
                                    recessed: recessed,
                                    material: makeMaterial(
                                        UIColor.systemBlue.withAlphaComponent(0.7)))
            node.renderingOrder = 10
            scene.rootNode.addChildNode(node)
        }

        // --- Türen ---
        for door in room.doors {
            guard let position = door.position else { continue }
            let color = door.isGlazed
                ? UIColor.systemTeal.withAlphaComponent(0.7)
                : UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1)
            let recessed = openingsWithHole.contains(door.id)
            let node = makePaneNode(position: position,
                                    width: door.width,
                                    height: door.height,
                                    bottom: 0,
                                    recessed: recessed,
                                    material: makeMaterial(color))
            if door.isGlazed { node.renderingOrder = 10 }
            scene.rootNode.addChildNode(node)
        }

        if usesOwnShadowLight {
            addShadowLight(to: scene, centerX: centerX, centerZ: centerZ,
                           reach: max(spanX, spanZ))
        }

        // Kamera schräg von oben auf die Raummitte – unverändert die Einstellung,
        // die sich in der Praxis bewährt hat.
        let camera = SCNNode()
        camera.camera = SCNCamera()
        let distance = max(spanX, spanZ) * 1.4 + 2.0
        camera.position = vector(centerX, 3.2, centerZ + distance)
        camera.look(at: vector(centerX, 0.6, centerZ))
        scene.rootNode.addChildNode(camera)

        return scene
    }

    // MARK: - Öffnungsmaße

    /// Schwelle unter der Türaussparung. Muss über dem Sicherheitsabstand von
    /// `WallCutoutPlanner` liegen, sonst wird die Aussparung verworfen.
    private static let doorSill = 0.08

    /// Brüstungshöhe, mindestens so hoch, dass die Aussparung die Wandunterkante
    /// nicht berührt. Nimmt bewusst den Rohwert statt den Fenstertyp entgegen –
    /// `Window` ist auch ein SwiftUI-Symbol, das wollen wir hier nicht anfassen.
    private static func sillHeight(_ scanned: Double?) -> Double {
        max(doorSill, scanned ?? 0.9)
    }

    // MARK: - Boden

    private static func makeFloorNode(outline: [FloorPoint]?,
                                      minX: Double, maxX: Double,
                                      minZ: Double, maxZ: Double) -> SCNNode {
        if let ring = outline, ring.count >= 3 {
            let material = makeMaterial(floorColor, doubleSided: true)
            let path = UIBezierPath()
            // Der Boden wird gleich um −90° um X gekippt; dabei wird aus der
            // Pfad-Y-Achse die negative Grundriss-Z-Achse. Darum hier −z.
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
            // Der Pfad trägt die Weltkoordinaten schon in sich; der Knoten muss
            // nur noch so tief sitzen, dass die Oberkante auf y = 0 liegt.
            node.position = vector(0, -floorThickness / 2, 0)
            return node
        }

        // Rückfallebene: die bewährte Rechteckplatte über der Bounding-Box.
        let box = SCNBox(width: CGFloat(maxX - minX + 0.3),
                         height: CGFloat(floorThickness),
                         length: CGFloat(maxZ - minZ + 0.3),
                         chamferRadius: 0)
        box.materials = [makeMaterial(floorColor)]
        let node = SCNNode(geometry: box)
        node.position = vector((minX + maxX) / 2, -floorThickness / 2, (minZ + maxZ) / 2)
        return node
    }

    // MARK: - Wände

    private static func makeWallPlan(_ item: PositionedWall,
                                     arrayIndex: Int,
                                     positions: [WallPosition],
                                     roomHeight: Double) -> WallPlan {
        let position = item.position
        let dx = position.x2 - position.x1
        let dz = position.z2 - position.z1
        let rawLength = max(0.0001, (dx * dx + dz * dz).squareRoot())
        let ux = dx / rawLength
        let uz = dz / rawLength

        // Nur in annähernd rechtwinklige Ecken hineinwachsen. Bei spitzen Winkeln
        // oder an einer geraden Nahtstelle würden sich die Wandstücke sonst
        // sichtbar ineinanderschieben.
        let ends = WallJoint.squareEnds(of: arrayIndex, in: positions)
        let startExtra = ends.start ? wallThickness / 2 : 0
        let endExtra = ends.end ? wallThickness / 2 : 0
        let length = max(0.05, rawLength) + startExtra + endExtra
        // Wird nur ein Ende verlängert, wandert die Mitte um die halbe Differenz.
        let shift = (endExtra - startExtra) / 2

        // Kleine Scan-Schwankungen glätten: 2,48 m neben 2,51 m sieht von außen
        // ausgefranst aus. Echte Abweichungen (halbhohe Brüstung) bleiben stehen.
        let rawHeight = item.wall.height > 0.3 ? item.wall.height : roomHeight
        let height = abs(rawHeight - roomHeight) < 0.4 ? roomHeight : rawHeight

        return WallPlan(index: item.index,
                        length: length,
                        height: height,
                        centerX: (position.x1 + position.x2) / 2 + ux * shift,
                        centerZ: (position.z1 + position.z2) / 2 + uz * shift,
                        angle: atan2(dz, dx),
                        shift: shift)
    }

    private static func makeWallNode(plan: WallPlan, wall: Wall, cutouts: [WallCutout]) -> SCNNode {
        let geometry: SCNGeometry
        let yOffset: Double

        if cutouts.isEmpty {
            // Der bewährte Fall: schlichter Quader.
            let box = SCNBox(width: CGFloat(plan.length),
                             height: CGFloat(plan.height),
                             length: CGFloat(wallThickness),
                             chamferRadius: 0)
            box.materials = [makeMaterial(wallColor(for: wall))]
            geometry = box
            yOffset = plan.height / 2          // SCNBox sitzt um seinen Mittelpunkt
        } else {
            // Even-Odd-Regel: die inneren Rechtecke werden zu echten Löchern.
            // Dass sie den Wandrand nicht berühren und einander nicht überlappen,
            // hat `WallCutoutPlanner` bereits sichergestellt.
            let material = makeMaterial(wallColor(for: wall), doubleSided: true)
            let path = UIBezierPath(rect: CGRect(x: -plan.length / 2, y: 0,
                                                 width: plan.length, height: plan.height))
            for cutout in cutouts {
                path.append(UIBezierPath(rect: CGRect(x: cutout.offset - cutout.width / 2,
                                                      y: cutout.bottom,
                                                      width: cutout.width,
                                                      height: cutout.height)))
            }
            path.usesEvenOddFillRule = true
            path.flatness = 0.005

            let shape = SCNShape(path: path, extrusionDepth: CGFloat(wallThickness))
            shape.materials = [material, material, material]
            geometry = shape
            yOffset = 0                        // SCNShape-Pfad beginnt schon bei y = 0
        }

        let node = SCNNode(geometry: geometry)
        node.name = "wall-\(plan.index)"
        node.position = vector(plan.centerX, yOffset, plan.centerZ)
        node.eulerAngles.y = -Float(plan.angle)
        return node
    }

    // MARK: - Fenster und Türen

    /// Scheibe bzw. Türblatt.
    ///
    /// `recessed` = in der Wand sitzt eine echte Aussparung: dann darf die
    /// Scheibe dünner als die Wand sein, die Laibung entsteht von selbst, und
    /// sie wird 2 cm größer gezeichnet, damit ihre Kanten im Mauerwerk
    /// verschwinden (sonst flimmert es an der Laibung).
    /// Ohne Aussparung bleibt es bei der alten, dickeren Platte vor der Wand –
    /// sonst wäre das Fenster gar nicht mehr zu sehen.
    private static func makePaneNode(position: WallPosition,
                                     width: Double,
                                     height: Double,
                                     bottom: Double,
                                     recessed: Bool,
                                     material: SCNMaterial) -> SCNNode {
        let oversize = recessed ? 0.02 : 0.0
        let depth = recessed ? 0.05 : 0.12

        let box = SCNBox(width: CGFloat(max(0.05, width + oversize)),
                         height: CGFloat(max(0.05, height + oversize)),
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

    // MARK: - Optionales Zusatzlicht

    /// Nur aktiv, wenn `usesOwnShadowLight` gesetzt ist. Weil ein gerichtetes
    /// Licht Apples Standardbeleuchtung abschaltet, muss hier auch das Grundlicht
    /// mitgeliefert werden.
    private static func addShadowLight(to scene: SCNScene,
                                       centerX: Double, centerZ: Double, reach: Double) {
        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 1.0, alpha: 1.0)
        ambient.intensity = 600
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let keyNode = SCNNode()
        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(white: 1.0, alpha: 1.0)
        key.intensity = 700
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowColor = UIColor(white: 0.0, alpha: 0.22)
        key.shadowRadius = 5
        key.shadowSampleCount = 8
        key.automaticallyAdjustsShadowProjection = true
        keyNode.light = key
        keyNode.position = vector(centerX, reach * 2 + 6, centerZ)
        keyNode.eulerAngles = vector(-Double.pi / 3, Double.pi / 5, 0)
        scene.rootNode.addChildNode(keyNode)
    }
}
