import Foundation
import UIKit
import KuehllastCore

/// Erzeugt einen einfachen PDF-Bericht der Kühllastberechnung (A4).
enum PDFReport {

    static func generate(room: Room,
                         result: CoolingLoadResult,
                         recommendation: DeviceRecommendation,
                         region: ClimateRegion) -> URL {
        let pageWidth: CGFloat = 595   // A4 @ 72 dpi
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 48
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

            y = row("Standort", region.name, y: y, margin: margin, width: pageWidth)
            y = row("Auslegung außen / innen",
                    String(format: "%.0f °C / %.0f °C",
                           region.designOutdoorTemperature, room.indoorTemperature),
                    y: y, margin: margin, width: pageWidth)
            y = row("Fläche / Höhe",
                    String(format: "%.2f m² / %.2f m", room.floorArea, room.height),
                    y: y, margin: margin, width: pageWidth)
            y += 12

            y = draw("Aufschlüsselung", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y += 6
            let posten: [(String, Double)] = [
                ("Solare Last (Fenster)", result.solar),
                ("Transmission (Außenbauteile)", result.transmission),
                ("Personen", result.persons),
                ("Geräte", result.equipment),
                ("Beleuchtung", result.lighting),
                ("Lüftung", result.ventilation)
            ]
            for (name, value) in posten {
                y = row(name, String(format: "%.0f W", value.rounded()),
                        y: y, margin: margin, width: pageWidth)
            }
            y += 4
            y = row("Gesamtkühllast", String(format: "%.0f W", result.total.rounded()),
                    y: y, margin: margin, width: pageWidth, bold: true, color: accent)
            y = row("Spezifisch", String(format: "%.0f W/m²", result.specific(for: room.floorArea)),
                    y: y, margin: margin, width: pageWidth)
            y += 16

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
        }
        return url
    }

    @discardableResult
    private static func draw(_ text: String, at point: CGPoint,
                             font: UIFont, color: UIColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
        return point.y + font.lineHeight
    }

    private static func row(_ label: String, _ value: String, y: CGFloat,
                            margin: CGFloat, width: CGFloat,
                            bold: Bool = false, color: UIColor = .black) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 13, weight: bold ? .semibold : .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.darkGray]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (label as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
        let valueSize = (value as NSString).size(withAttributes: valueAttrs)
        (value as NSString).draw(at: CGPoint(x: width - margin - valueSize.width, y: y),
                                 withAttributes: valueAttrs)
        return y + font.lineHeight + 4
    }

    private static func safe(_ s: String) -> String {
        s.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
    }
}
