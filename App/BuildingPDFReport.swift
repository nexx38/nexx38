import Foundation
import UIKit
import KuehllastCore

/// Gebäude-Gesamtbericht: alle Räume, Summen, WP- und Multisplit-Auslegung,
/// Heizkörper-Check und hydraulischer Abgleich in EINEM PDF (A4).
enum BuildingPDFReport {

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 48

    static func generate(rooms: [Room], settings: BuildingSettings) -> URL {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let wpAccent = UIColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1)
        let acAccent = UIColor(red: 0.33, green: 0.29, blue: 0.72, alpha: 1)

        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Gebaeudebericht.pdf")

        // Berechnungen vorab
        let heatingResults = rooms.map { HeatingLoadCalculator().calculate($0) }
        let coolingResults = rooms.map { room in
            CoolingLoadCalculator(region: ClimateRegion.region(id: room.climateRegionID))
                .calculate(room)
        }
        let heatingTotal = heatingResults.reduce(0.0) { $0 + $1.total }
        let coolingTotal = coolingResults.reduce(0.0) { $0 + $1.total }
        let areaTotal = rooms.reduce(0.0) { $0 + $1.floorArea }
        let heatPump = HeatPumpSizing.recommend(heatingLoadW: heatingTotal,
                                                dhwPersons: settings.dhwPersons,
                                                blockingHours: settings.blockingHours)
        let multiSplit = MultiSplitSizing.plan(
            rooms: rooms.enumerated().map { ($0.element.name, coolingResults[$0.offset].total) },
            simultaneity: settings.simultaneity)

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = margin

            y = draw("Gebäudebericht", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 24, weight: .semibold), color: .black)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd.MM.yyyy"
            y = draw("Heizlast (DIN EN 12831) und Kühllast (VDI 2078, Kurzverfahren) · erstellt am "
                     + dateFormatter.string(from: Date()),
                     at: CGPoint(x: margin, y: y + 2),
                     font: .systemFont(ofSize: 12, weight: .regular), color: .darkGray)
            y += 14

            // Raumtabelle
            y = tableRow("Raum", "Fläche", "Heizlast", "Kühllast", y: y, bold: true)
            for (index, room) in rooms.enumerated() {
                if y > pageHeight - 140 {
                    ctx.beginPage()
                    y = margin
                    y = tableRow("Raum", "Fläche", "Heizlast", "Kühllast", y: y, bold: true)
                }
                y = tableRow(room.name,
                             String(format: "%.1f m²", room.floorArea),
                             String(format: "%.0f W", heatingResults[index].total.rounded()),
                             String(format: "%.0f W", coolingResults[index].total.rounded()),
                             y: y)
            }
            y += 2
            y = tableRow("Gesamt (\(rooms.count) Räume)",
                         String(format: "%.1f m²", areaTotal),
                         String(format: "%.0f W", heatingTotal.rounded()),
                         String(format: "%.0f W", coolingTotal.rounded()),
                         y: y, bold: true)
            y += 16

            // Wärmepumpe
            y = draw("Wärmepumpen-Auslegung (überschlägig nach VDI 4645)",
                     at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y += 4
            y = row("Heizlast Gebäude", String(format: "%.0f W", heatingTotal.rounded()), y: y)
            y = row(String(format: "Warmwasser (%d Personen)", settings.dhwPersons),
                    String(format: "+ %.0f W", heatPump.dhwW), y: y)
            y = row(String(format: "EVU-Sperrzeit %.0f h", settings.blockingHours),
                    String(format: "× %.2f", heatPump.blockingFactor), y: y)
            y = row("Erforderliche Heizleistung",
                    String(format: "%.1f kW", heatPump.requiredKW), y: y)
            y = row("Empfehlung", String(format: "%.0f-kW-Wärmepumpe", heatPump.suggestedKW),
                    y: y, bold: true, color: wpAccent)
            y += 12

            // Multisplit
            if y > pageHeight - 180 { ctx.beginPage(); y = margin }
            y = draw("Klima / Multisplit-Auslegung", at: CGPoint(x: margin, y: y),
                     font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
            y += 4
            for unit in multiSplit.indoorUnits {
                if y > pageHeight - 120 { ctx.beginPage(); y = margin }
                y = row(unit.roomName,
                        String(format: "%.0f W → Innengerät %.1f kW",
                               unit.coolingLoadW.rounded(), unit.unitKW), y: y)
            }
            y = row(String(format: "Gleichzeitigkeit %.2f", multiSplit.simultaneity),
                    String(format: "Summe %.1f kW", multiSplit.indoorTotalKW), y: y)
            y = row("Außengerät", String(format: "ab %.1f kW", multiSplit.outdoorRequiredKW),
                    y: y, bold: true, color: acAccent)

            // Heizkörper + Abgleich
            let radiatorRooms = rooms.filter { !($0.radiators ?? []).isEmpty }
            if !radiatorRooms.isEmpty {
                ctx.beginPage()
                y = margin
                y = draw(String(format: "Heizkörper-Check bei %.0f/%.0f °C + hydraulischer Abgleich",
                                settings.flowTemp, settings.returnTemp),
                         at: CGPoint(x: margin, y: y),
                         font: .systemFont(ofSize: 15, weight: .semibold), color: .black)
                y = draw("Verfahren B (vereinfacht): Raumlast anteilig je Heizkörper, generische Ventilstufen.",
                         at: CGPoint(x: margin, y: y + 2),
                         font: .systemFont(ofSize: 10, weight: .regular), color: .darkGray)
                y += 10

                for room in radiatorRooms {
                    let radiators = room.radiators ?? []
                    let roomTemp = room.heating?.indoorTemperature ?? 20
                    let demand = HeatingLoadCalculator().calculate(room).total
                    let capacity = radiators.reduce(0.0) {
                        $0 + $1.power(flow: settings.flowTemp, ret: settings.returnTemp,
                                      roomTemp: roomTemp)
                    }
                    let check = RadiatorCheckResult(capacity: capacity, demand: demand)
                    let normTotal = radiators.reduce(0.0) { $0 + $1.normPower }

                    if y > pageHeight - 140 { ctx.beginPage(); y = margin }
                    y = row(room.name,
                            String(format: "Deckung %.0f %% – %@",
                                   check.coverage * 100, check.verdict.label),
                            y: y, bold: true,
                            color: check.verdict == .zuKlein ? .red :
                                   check.verdict == .knapp ? .orange : UIColor(red: 0, green: 0.55, blue: 0.2, alpha: 1))
                    for (index, radiator) in radiators.enumerated() {
                        if y > pageHeight - 100 { ctx.beginPage(); y = margin }
                        let share = normTotal > 0 ? radiator.normPower / normTotal : 0
                        let preset = HydraulicBalancing.preset(loadW: demand * share,
                                                               spreadK: settings.spreadK)
                        y = row(String(format: "  HK %d · %@ · %.0f × %.0f cm",
                                       index + 1, radiator.type.label,
                                       radiator.widthM * 100, radiator.heightM * 100),
                                String(format: "%.0f W · %.0f kg/h · %@",
                                       radiator.power(flow: settings.flowTemp,
                                                      ret: settings.returnTemp,
                                                      roomTemp: roomTemp),
                                       preset.flowKgPerH, preset.presetLabel),
                                y: y)
                    }
                    y += 6
                }
            }

            let footer = "Kurzverfahren zur Auslegung – kein prüffähiger Nachweis. Heizkörper-Leistungen und Ventilstufen sind Anhaltswerte, Herstellertabellen maßgebend."
            _ = draw(footer, at: CGPoint(x: margin, y: pageHeight - margin - 10),
                     font: .systemFont(ofSize: 8, weight: .regular), color: .gray)
        }
        return url
    }

    // MARK: - Zeichen-Helfer

    @discardableResult
    private static func draw(_ text: String, at point: CGPoint,
                             font: UIFont, color: UIColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
        return point.y + font.lineHeight
    }

    private static func row(_ label: String, _ value: String, y: CGFloat,
                            bold: Bool = false, color: UIColor = .black) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 12, weight: bold ? .semibold : .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.darkGray]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (label as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)
        let size = (value as NSString).size(withAttributes: valueAttrs)
        (value as NSString).draw(at: CGPoint(x: pageWidth - margin - size.width, y: y),
                                 withAttributes: valueAttrs)
        return y + font.lineHeight + 3
    }

    /// Vierspaltige Tabellenzeile (Raum | Fläche | Heizlast | Kühllast).
    private static func tableRow(_ c1: String, _ c2: String, _ c3: String, _ c4: String,
                                 y: CGFloat, bold: Bool = false) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 11, weight: bold ? .semibold : .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let width = pageWidth - 2 * margin
        let col1 = margin
        let col2 = margin + width * 0.45
        let col3 = margin + width * 0.65
        let col4 = margin + width * 0.85
        (c1 as NSString).draw(at: CGPoint(x: col1, y: y), withAttributes: attrs)
        (c2 as NSString).draw(at: CGPoint(x: col2, y: y), withAttributes: attrs)
        (c3 as NSString).draw(at: CGPoint(x: col3, y: y), withAttributes: attrs)
        (c4 as NSString).draw(at: CGPoint(x: col4, y: y), withAttributes: attrs)
        return y + font.lineHeight + 3
    }
}
