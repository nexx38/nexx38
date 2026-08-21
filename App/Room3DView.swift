import SwiftUI
import SceneKit
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

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct Room3DView: UIViewRepresentable {
    @Binding var room: Room

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
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
            guard let node = hits.first?.node,
                  let name = node.name, name.hasPrefix("wall-"),
                  let index = Int(name.dropFirst(5)),
                  room.wrappedValue.walls.indices.contains(index) else { return }
            room.wrappedValue.walls[index].isExternal.toggle()
            node.geometry?.firstMaterial?.diffuse.contents =
                Room3DView.wallColor(for: room.wrappedValue.walls[index])
        }
    }

    // MARK: - Szene bauen

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

    static func buildScene(room: Room) -> SCNScene {
        let scene = SCNScene()

        let positioned = room.walls.enumerated().compactMap { index, wall in
            wall.position.map { (index: index, wall: wall, pos: $0) }
        }
        guard !positioned.isEmpty else { return scene }

        // Ausdehnung für Boden und Kamera
        var minX = Double.infinity, maxX = -Double.infinity
        var minZ = Double.infinity, maxZ = -Double.infinity
        for item in positioned {
            minX = min(minX, item.pos.x1, item.pos.x2)
            maxX = max(maxX, item.pos.x1, item.pos.x2)
            minZ = min(minZ, item.pos.z1, item.pos.z2)
            maxZ = max(maxZ, item.pos.z1, item.pos.z2)
        }
        let centerX = (minX + maxX) / 2, centerZ = (minZ + maxZ) / 2
        let spanX = maxX - minX, spanZ = maxZ - minZ

        // Bodenplatte
        let floor = SCNBox(width: CGFloat(spanX + 0.3), height: 0.05,
                           length: CGFloat(spanZ + 0.3), chamferRadius: 0)
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.93, green: 0.90, blue: 0.85, alpha: 1)
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(centerX, -0.025, centerZ)
        scene.rootNode.addChildNode(floorNode)

        // Wände
        for item in positioned {
            let p = item.pos
            let length = max(0.05, (pow(p.x2 - p.x1, 2) + pow(p.z2 - p.z1, 2)).squareRoot())
            let box = SCNBox(width: CGFloat(length), height: CGFloat(item.wall.height),
                             length: 0.08, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = wallColor(for: item.wall)
            let node = SCNNode(geometry: box)
            node.name = "wall-\(item.index)"
            node.position = SCNVector3((p.x1 + p.x2) / 2, item.wall.height / 2, (p.z1 + p.z2) / 2)
            node.eulerAngles.y = -Float(atan2(p.z2 - p.z1, p.x2 - p.x1))
            scene.rootNode.addChildNode(node)
        }

        // Fenster (blau, leicht dicker als die Wand → sichtbar)
        for window in room.windows {
            guard let p = window.position else { continue }
            let sill = window.sillHeight ?? 0.9
            let box = SCNBox(width: CGFloat(window.width), height: CGFloat(window.height),
                             length: 0.12, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.7)
            let node = SCNNode(geometry: box)
            node.position = SCNVector3((p.x1 + p.x2) / 2, sill + window.height / 2, (p.z1 + p.z2) / 2)
            node.eulerAngles.y = -Float(atan2(p.z2 - p.z1, p.x2 - p.x1))
            scene.rootNode.addChildNode(node)
        }

        // Türen (braun; verglaste Türen blaugrün)
        for door in room.doors {
            guard let p = door.position else { continue }
            let box = SCNBox(width: CGFloat(door.width), height: CGFloat(door.height),
                             length: 0.12, chamferRadius: 0)
            box.firstMaterial?.diffuse.contents = door.isGlazed
                ? UIColor.systemTeal.withAlphaComponent(0.7)
                : UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1)
            let node = SCNNode(geometry: box)
            node.position = SCNVector3((p.x1 + p.x2) / 2, door.height / 2, (p.z1 + p.z2) / 2)
            node.eulerAngles.y = -Float(atan2(p.z2 - p.z1, p.x2 - p.x1))
            scene.rootNode.addChildNode(node)
        }

        // Kamera schräg von oben auf die Raummitte
        let camera = SCNNode()
        camera.camera = SCNCamera()
        let distance = max(spanX, spanZ) * 1.4 + 2.0
        camera.position = SCNVector3(centerX, 3.2, centerZ + distance)
        camera.look(at: SCNVector3(centerX, 0.6, centerZ))
        scene.rootNode.addChildNode(camera)

        return scene
    }
}
