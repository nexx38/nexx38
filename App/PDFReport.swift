import Foundation
import UIKit
import KuehllastCore

/// Erzeugt einfache PDF-Berichte für Kühl- und Heizlastberechnungen (A4).
/// Optional mit Foto-Seiten (Baustellen-Doku aus dem Scan) und einem
/// Annahmen-Block, wenn eine Baujahr-Klasse gewählt wurde.
enum PDFReport {

    private static let pageWidth: CGFloat = 595   // A4 @ 72 dpi
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 48

    static func generate(room: Room, heatingResult: HeatingLoadResult,
                         photoURLs: [URL] = [], project: Project? = nil) -> URL {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let accent = UIColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)

        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Heizlast-\(safe(room.name)).pdf")

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            y = draw("Heizlastberechnung", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 24, weight: .semibold), color: accent)
            y = draw(room.name, at: CGPoint(x: margin, y: y + 4),
                     font: .systemFont(ofSize: 16, weight: .regular), color: .darkGray)
            y += 16

            let climate = HeatingClimate.named(room.heating?.climateName ?? "Berlin")
            y = projectRows(project, y: y)
            y = row("Erstellt am", dateString(), y: y)
            y = row("Standort", climate.name, y: y)
            y = row("Auslegung außen / innen",
                    String(format: "%.0f °C / %.0f °C",
                           climate.designOutdoorTemperature, room.heating?.indoorTemperature ?? 20),
                    y: y)
            y = row("Fläche / Höhe",
                    String(format: "%.2f m² / %.2f m", room.floorArea, room.height),
                    y: y)
            y = row("Wärmebrückenzuschlag",
                    String(format: "%.1f %%", room.heating?.thermalBridgePercent ?? 5),
                    y: y)
            y = componentsBlock(for: room, y: y)
            y += 10

            y = draw("Aufschlüsselung", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y += 6
            let posten: [(String, Double)] = [
                ("Transmission (Außenbauteile)", heatingResult.transmission),
                ("Wärmebrückenzuschlag", heatingResult.thermalBridges),
                ("Lüftung", heatingResult.ventilation)
            ]
            for (name, value) in posten {
                y = row(name, String(format: "%.0f W", value.rounded()), y: y)
            }
            y += 4
            y = row("Gesamtheizlast", String(format: "%.0f W", heatingResult.total.rounded()),
                    y: y, bold: true, color: accent)
            let specific = heatingResult.specific(for: room.floorArea)
            y = row("Spezifisch", String(format: "%.0f W/m²", specific), y: y)

            y = plausibilityBlock(note: Plausibility.heatingNote(specific: specific),
                                  band: Plausibility.heatingBand, y: y)
            y = assumptionsBlock(for: room, y: y)

            let footer = "Vereinfachtes Verfahren nach DIN EN 12831. Kein prüffähiger Nachweis."
            _ = draw(footer, at: CGPoint(x: margin, y: pageHeight - margin - 12),
                     font: .systemFont(ofSize: 9, weight: .regular), color: .gray)

            drawPhotoPages(ctx: ctx, roomName: room.name, photoURLs: photoURLs)
        }
        return url
    }

    static func generate(room: Room,
                         result: CoolingLoadResult,
                         recommendation: DeviceRecommendation,
                         region: ClimateRegion,
                         photoURLs: [URL] = [], project: Project? = nil) -> URL {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let accent = UIColor(red: 0.33, green: 0.29, blue: 0.72, alpha: 1)

        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kuehllast-\(safe(room.name)).pdf")

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            y = draw("Kühllastberechnung", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 24, weight: .semibold), color: accent)
            y = draw(room.name, at: CGPoint(x: margin, y: y + 4),
                     font: .systemFont(ofSize: 16, weight: .regular), color: .darkGray)
            y += 16

            y = projectRows(project, y: y)
            y = row("Erstellt am", dateString(), y: y)
            y = row("Standort", region.name, y: y)
            y = row("Auslegung außen / innen",
                    String(format: "%.0f °C / %.0f °C",
                           region.designOutdoorTemperature, room.indoorTemperature),
                    y: y)
            y = row("Fläche / Höhe",
                    String(format: "%.2f m² / %.2f m", room.floorArea, room.height),
                    y: y)
            y = componentsBlock(for: room, y: y)
            y += 10

            y = draw("Aufschlüsselung", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y += 6
            var posten: [(String, Double)] = [
                ("Solare Last (Fenster)", result.solar),
                ("Transmission (Außenbauteile)", result.transmission)
            ]
            if result.roof > 0 {
                posten.append(("Dach (besonnt)", result.roof))
            }
            posten.append(contentsOf: [
                ("Personen", result.persons),
                ("Geräte", result.equipment),
                ("Beleuchtung", result.lighting),
                ("Lüftung", result.ventilation)
            ])
            for (name, value) in posten {
                y = row(name, String(format: "%.0f W", value.rounded()), y: y)
            }
            y += 4
            y = row("Gesamtkühllast", String(format: "%.0f W", result.total.rounded()),
                    y: y, bold: true, color: accent)
            let specific = result.specific(for: room.floorArea)
            y = row("Spezifisch", String(format: "%.0f W/m²", specific), y: y)

            y = plausibilityBlock(note: Plausibility.coolingNote(specific: specific),
                                  band: Plausibility.coolingBand, y: y)
            y = assumptionsBlock(for: room, y: y)
            y += 12

            y = draw("Empfehlung", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y += 4
            _ = draw(recommendation.label + String(format: "  (Auslastung %.0f %%)",
                                                   recommendation.utilization * 100),
                     at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 14, weight: .medium), color: accent)

            let footer = "Kurzverfahren nach VDI 2078 zur Geräteauslegung. Kein prüffähiger Nachweis."
            _ = draw(footer, at: CGPoint(x: margin, y: pageHeight - margin - 12),
                     font: .systemFont(ofSize: 9, weight: .regular), color: .gray)

            drawPhotoPages(ctx: ctx, roomName: room.name, photoURLs: photoURLs)
        }
        return url
    }

    // MARK: - Bausteine

    /// Plausibilitätszeile: Warnung außerhalb, sonst kurze Bestätigung.
    private static func plausibilityBlock(note: String?, band: ClosedRange<Double>,
                                          y startY: CGFloat) -> CGFloat {
        var y = startY + 4
        if let note {
            y = drawWrapped("⚠ Plausibilität: " + note,
                            at: CGPoint(x: margin, y: y),
                            width: pageWidth - 2 * margin,
                            font: .systemFont(ofSize: 10, weight: .medium),
                            color: UIColor(red: 0.7, green: 0.45, blue: 0.0, alpha: 1))
        } else {
            y = draw(String(format: "Plausibilität: im üblichen Bereich (%.0f–%.0f W/m²).",
                            band.lowerBound, band.upperBound),
                     at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 10, weight: .regular), color: .gray)
        }
        return y
    }

    /// Kompakte Bauteil-Übersicht (eine Zeile) für die Raum-Berichte.
    private static func componentsBlock(for room: Room, y startY: CGFloat) -> CGFloat {
        let externalWallNet = room.walls.filter { $0.isExternal }.reduce(0.0) { $0 + $1.netArea }
        let windowArea = room.windows.reduce(0.0) { $0 + $1.area }
        let glazedDoors = room.doors.filter { $0.isGlazed }
        var text = String(format: "Bauteile: Außenwand netto %.1f m² · %d Fenster %.1f m²",
                          externalWallNet, room.windows.count, windowArea)
        if !glazedDoors.isEmpty {
            let area = glazedDoors.reduce(0.0) { $0 + $1.area }
            text += String(format: " · %d verglaste Tür(en) %.1f m²", glazedDoors.count, area)
        }
        return drawWrapped(text, at: CGPoint(x: margin, y: startY + 2),
                           width: pageWidth - 2 * margin,
                           font: .systemFont(ofSize: 10, weight: .regular), color: .darkGray)
    }

    /// Projekt-/Kundenzeilen im Berichtskopf (nur wenn vorhanden).
    private static func projectRows(_ project: Project?, y startY: CGFloat) -> CGFloat {
        guard let project else { return startY }
        var y = row("Projekt", project.name, y: startY)
        if !project.customerName.isEmpty {
            y = row("Kunde", project.customerName, y: y)
        }
        if !project.address.isEmpty {
            y = row("Adresse", project.address, y: y)
        }
        return y
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: Date())
    }

    /// Annahmen-Block, wenn eine Baujahr-Klasse die U-Werte vorgegeben hat.
    private static func assumptionsBlock(for room: Room, y startY: CGFloat) -> CGFloat {
        guard let raw = room.constructionEra,
              let era = BuildingEra(rawValue: raw) else { return startY }
        var y = startY + 4
        let text = String(format: "Annahmen: U-Werte nach Baujahr-Klasse %@ angesetzt "
                          + "(Wand %.2f / Fenster %.1f / Tür %.1f W/(m²K)). "
                          + "Richtwerte für unsanierte Gebäude - vom Fachbetrieb zu prüfen.",
                          era.label, era.wallU, era.windowU, era.doorU)
        y = drawWrapped(text, at: CGPoint(x: margin, y: y),
                        width: pageWidth - 2 * margin,
                        font: .systemFont(ofSize: 10, weight: .regular), color: .darkGray)
        return y
    }

    /// Hängt pro Foto eine Seite „Fotodokumentation" an.
    private static func drawPhotoPages(ctx: UIGraphicsPDFRendererContext,
                                       roomName: String, photoURLs: [URL]) {
        for (index, url) in photoURLs.enumerated() {
            guard let image = UIImage(contentsOfFile: url.path) else { continue }
            ctx.beginPage()
            var y: CGFloat = margin
            y = draw("Fotodokumentation – \(roomName) (\(index + 1)/\(photoURLs.count))",
                     at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 16, weight: .semibold), color: .black)
            y += 12

            let maxRect = CGRect(x: margin, y: y,
                                 width: pageWidth - 2 * margin,
                                 height: pageHeight - y - margin)
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { continue }
            let scale = min(maxRect.width / imageSize.width,
                            maxRect.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale,
                                  height: imageSize.height * scale)
            let drawRect = CGRect(x: maxRect.midX - drawSize.width / 2,
                                  y: maxRect.minY,
                                  width: drawSize.width, height: drawSize.height)
            image.draw(in: drawRect)
        }
    }

    @discardableResult
    private static func draw(_ text: String, at point: CGPoint,
                             font: UIFont, color: UIColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
        return point.y + font.lineHeight
    }

    /// Zeichnet mehrzeiligen Text im gegebenen Breitenrahmen und gibt die
    /// y-Position unter dem Text zurück.
    private static func drawWrapped(_ text: String, at point: CGPoint, width: CGFloat,
                                    font: UIFont, color: UIColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        (text as NSString).draw(
            with: CGRect(x: point.x, y: point.y, width: width, height: ceil(bounding.height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        return point.y + ceil(bounding.height) + 2
    }

    private static func row(_ label: String, _ value: String, y: CGFloat,
                            bold: Bool = false, color: UIColor = .black) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 13, weight: bold ? .semibold : .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.darkGray]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (label as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
        let valueSize = (value as NSString).size(withAttributes: valueAttrs)
        (value as NSString).draw(at: CGPoint(x: pageWidth - margin - valueSize.width, y: y),
                                 withAttributes: valueAttrs)
        return y + font.lineHeight + 4
    }

    private static func safe(_ s: String) -> String {
        s.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
    }
}
