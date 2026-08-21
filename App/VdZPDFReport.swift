import Foundation
import UIKit
import KuehllastCore

/// Erzeugt die Unterlage zum VdZ-Formular „Bestätigung des Hydraulischen
/// Abgleichs (Einzelmaßnahmen BEG)", Verfahren B.
///
/// WICHTIG und bewusst so gebaut: Dieses PDF **ersetzt das VdZ-Formular
/// nicht**. Die BEG-Richtlinie verlangt ausdrücklich die Verwendung des
/// VdZ-Bestätigungsformulars. Was wir liefern, ist zweierlei:
/// 1. ein **Datenblatt** mit genau den Werten, die in die Formularfelder
///    einzutragen sind (damit nichts abgeschrieben werden muss), und
/// 2. die **Anlage** – raumweise Heizlast und Abgleichwerte je Heizfläche.
///    Die VdZ-Fachregel (Kap. 8) sieht ausdrücklich vor, dass diese
///    Dokumentation durch Software erstellt wird.
enum VdZPDFReport {

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 42

    static func generate(rooms: [Room],
                         settings: BuildingSettings,
                         project: Project?) -> URL {
        let report = VdZReportBuilder.build(rooms: rooms, settings: settings)
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let accent = UIColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)

        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hydraulischer-Abgleich-VerfahrenB.pdf")

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            y = draw("Hydraulischer Abgleich – Verfahren B",
                     at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 20, weight: .semibold), color: accent)
            y = drawWrapped("Datenblatt und Berechnungsanlage zum VdZ-Bestätigungsformular "
                            + "für Einzelmaßnahmen (BEG). Dieses Dokument ersetzt das "
                            + "VdZ-Formular nicht, sondern liefert dessen Werte und die "
                            + "nach VdZ-Fachregel Kap. 8 beizufügende Dokumentation.",
                            at: CGPoint(x: margin, y: y + 2), width: contentWidth,
                            font: .systemFont(ofSize: 9), color: .darkGray)
            y += 8

            if let project {
                y = row("Objekt", [project.name, project.customerName, project.address]
                            .filter { !$0.isEmpty }.joined(separator: " · "), y: y)
            }
            y = row("Erstellt am", dateString(), y: y)
            y = row("Verfahren", "B (raumweise Heizlastberechnung nach DIN EN 12831-1 / DIN/TS 12831-1)", y: y)
            y = row("Erfasste Fläche",
                    settings.vdz.totalLivingAreaSqm > 0
                        ? String(format: "%.1f m² von %.1f m² Wohnfläche",
                                 report.capturedAreaSqm, settings.vdz.totalLivingAreaSqm)
                        : String(format: "%.1f m² (Wohnfläche nicht angegeben)", report.capturedAreaSqm),
                    y: y)
            y += 10

            // ---- Formularwerte je Heizkreis ----
            y = draw("Werte für das VdZ-Formular", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 14, weight: .semibold), color: .black)
            y += 6
            for (index, circuit) in report.circuits.enumerated() {
                if y > pageHeight - 190 { ctx.beginPage(); y = margin }
                y = draw("Heizkreis \(index + 1): \(circuit.kind.label)",
                         at: CGPoint(x: margin, y: y),
                         font: .systemFont(ofSize: 12, weight: .semibold), color: accent)
                y += 2
                y = row("Auslegungsvorlauftemperatur",
                        String(format: "%.0f °C", circuit.flowTemp), y: y)
                y = row("Heizkreisrücklauftemperatur",
                        String(format: "%.0f °C", circuit.returnTemp), y: y)
                y = row("Ermittelter Gesamtdurchfluss",
                        String(format: "%.0f l/h", circuit.totalFlowLPerH), y: y)
                y = row("Ermittelte Pumpenförderhöhe (bei Gesamtdurchfluss)",
                        String(format: "%.1f m", circuit.pumpHeadM), y: y)
                y = row("Heizflächen im Kreis / Wärmeleistung",
                        String(format: "%d Stück · %.0f W", circuit.surfaceCount, circuit.loadW), y: y)
                y += 6
            }

            if y > pageHeight - 160 { ctx.beginPage(); y = margin }
            y = draw("Anlagendaten (Vor-Ort-Feststellung)", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 12, weight: .semibold), color: .black)
            y += 2
            let vdz = settings.vdz
            y = row("Ausdehnungsgefäß geprüft", vdz.expansionVesselChecked ? "ja" : "— offen —", y: y)
            y = row("Fülldruck", pressure(vdz.fillPressureBar), y: y)
            y = row("Vordruck / Enddruck AG",
                    pressure(vdz.vesselPrePressureBar) + " / " + pressure(vdz.vesselEndPressureBar), y: y)
            y = row("Differenzdruckregler vorhanden", vdz.differentialPressureController ? "ja" : "nein", y: y)
            y = row("Durchflussregler / Strangregulierventil", vdz.flowController ? "ja" : "nein", y: y)
            y = row("Eingestellte Leistung Wärmeerzeuger",
                    vdz.generatorSetPowerKW > 0
                        ? String(format: "%.1f kW", vdz.generatorSetPowerKW) : "— offen —", y: y)
            y = row("Einstellung der Regelung / Heizkurve",
                    vdz.heatingCurveNote.isEmpty ? "— offen —" : vdz.heatingCurveNote, y: y)
            if !vdz.remarks.isEmpty {
                y = row("Bemerkungen", vdz.remarks, y: y)
            }

            if !report.hints.isEmpty {
                y += 8
                y = draw("Noch zu ergänzen", at: CGPoint(x: margin, y: y),
                         font: .systemFont(ofSize: 12, weight: .semibold),
                         color: UIColor(red: 0.7, green: 0.45, blue: 0, alpha: 1))
                for hint in report.hints {
                    if y > pageHeight - 90 { ctx.beginPage(); y = margin }
                    y = drawWrapped("• " + hint, at: CGPoint(x: margin, y: y + 2),
                                    width: contentWidth,
                                    font: .systemFont(ofSize: 10),
                                    color: UIColor(red: 0.7, green: 0.45, blue: 0, alpha: 1))
                }
            }

            // ---- Anlage 1: raumweise Heizlast ----
            ctx.beginPage()
            y = margin
            y = draw("Anlage 1: Raumweise Heizlast", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y = draw("nach DIN EN 12831-1 / DIN/TS 12831-1, vereinfachtes Verfahren",
                     at: CGPoint(x: margin, y: y + 2),
                     font: .systemFont(ofSize: 9), color: .darkGray)
            y += 10
            y = tableRow(["Raum", "Etage", "Fläche", "θi", "Heizlast", "W/m²"], y: y, bold: true)
            for room in report.rooms {
                if y > pageHeight - 90 {
                    ctx.beginPage(); y = margin
                    y = tableRow(["Raum", "Etage", "Fläche", "θi", "Heizlast", "W/m²"], y: y, bold: true)
                }
                y = tableRow([room.name, room.storeyLabel,
                              String(format: "%.1f m²", room.areaSqm),
                              String(format: "%.0f °C", room.indoorTemp),
                              String(format: "%.0f W", room.loadW),
                              String(format: "%.0f", room.specificW)], y: y)
            }
            y += 4
            y = tableRow(["Gebäude gesamt", "", "", "",
                          String(format: "%.0f W", report.totalLoadW), ""], y: y, bold: true)

            // ---- Anlage 2: Abgleichwerte je Heizfläche ----
            ctx.beginPage()
            y = margin
            y = draw("Anlage 2: Abgleichwerte je Heizfläche", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y = draw("Volumenstrom, Ventil und Voreinstellwert je Heizfläche",
                     at: CGPoint(x: margin, y: y + 2),
                     font: .systemFont(ofSize: 9), color: .darkGray)
            y += 10
            let header = ["Raum", "Heizfläche", "Last", "Durchfluss", "Ventil", "Einstellung"]
            y = tableRow(header, y: y, bold: true)
            for surface in report.surfaces {
                if y > pageHeight - 90 {
                    ctx.beginPage(); y = margin
                    y = tableRow(header, y: y, bold: true)
                }
                y = tableRow([surface.roomName,
                              surface.surfaceLabel,
                              String(format: "%.0f W", surface.loadW),
                              String(format: "%.0f l/h", surface.flowLPerH),
                              surface.valveName ?? (surface.kind == .fussboden ? "Verteiler" : "—"),
                              surface.valveSetting ?? "—"], y: y)
            }

            // ---- Fußzeile mit den Grenzen, ehrlich benannt ----
            let footer = "Berechnung mit LastScan (vereinfachtes Verfahren, U-Werte nach Baujahr-Typologie). "
                + "Kein geprüfter oder zertifizierter Nachweis. Ventil-Voreinstellwerte nach "
                + "Herstellerangaben; Herstellertabelle bleibt maßgebend. Pumpenförderhöhe "
                + "überschlägig ermittelt, ersetzt keine Rohrnetzberechnung. Die Bestätigung "
                + "erfolgt durch den unterzeichnenden Fachbetrieb auf dem VdZ-Formular."
            _ = drawWrapped(footer, at: CGPoint(x: margin, y: pageHeight - margin - 26),
                            width: contentWidth,
                            font: .systemFont(ofSize: 7.5), color: .gray)
        }
        return url
    }

    // MARK: - Zeichen-Helfer

    private static var contentWidth: CGFloat { pageWidth - 2 * margin }

    private static func pressure(_ bar: Double) -> String {
        bar > 0 ? String(format: "%.1f bar", bar) : "— offen —"
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: Date())
    }

    @discardableResult
    private static func draw(_ text: String, at point: CGPoint,
                             font: UIFont, color: UIColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
        return point.y + font.lineHeight
    }

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

    private static func row(_ label: String, _ value: String, y: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 11)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.darkGray]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium),
                                                         .foregroundColor: UIColor.black]
        (label as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
        let size = (value as NSString).size(withAttributes: valueAttrs)
        (value as NSString).draw(at: CGPoint(x: pageWidth - margin - size.width, y: y),
                                 withAttributes: valueAttrs)
        return y + font.lineHeight + 3
    }

    /// Sechsspaltige Tabellenzeile.
    private static func tableRow(_ columns: [String], y: CGFloat, bold: Bool = false) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 9.5, weight: bold ? .semibold : .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        // Spaltenanteile: Raum, Heizfläche/Etage, Last, Durchfluss, Ventil, Einstellung
        let shares: [CGFloat] = [0, 0.20, 0.46, 0.58, 0.72, 0.88]
        for (index, text) in columns.enumerated() where index < shares.count {
            let x = margin + contentWidth * shares[index]
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }
        return y + font.lineHeight + 3
    }
}
