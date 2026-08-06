import SwiftUI
import KuehllastCore

struct ResultView: View {
    @EnvironmentObject var store: RoomStore
    let room: Room
    @State private var pdfURL: URL?

    private var accent: Color { Color(red: 0.33, green: 0.29, blue: 0.72) }
    private var region: ClimateRegion { ClimateRegion.region(id: room.climateRegionID) }
    private var calc: CoolingLoadCalculator { CoolingLoadCalculator(region: region) }
    private var result: CoolingLoadResult { calc.calculate(room) }
    private var recommendation: DeviceRecommendation { calc.recommendDevice(for: result.total) }
    private var plausibilityNote: String? {
        Plausibility.coolingNote(specific: result.specific(for: room.floorArea))
    }

    private var items: [(String, Double, Color)] {
        [
            ("Solar (Fenster)", result.solar, accent),
            ("Transmission", result.transmission, .blue),
            ("Personen", result.persons, .orange),
            ("Geräte", result.equipment, .teal),
            ("Beleuchtung", result.lighting, .yellow),
            ("Lüftung", result.ventilation, .gray)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                totalCard
                if let note = plausibilityNote {
                    PlausibilityCard(note: note)
                }
                breakdown
                recommendationCard
                disclaimer
            }
            .padding()
        }
        .navigationTitle("Ergebnis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            // Einmal erzeugen statt bei jedem Render – mit Fotos wäre das teuer.
            let photoURLs = (room.photoFilenames ?? []).map { store.photoURL(named: $0) }
            pdfURL = PDFReport.generate(room: room, result: result,
                                        recommendation: recommendation, region: region,
                                        photoURLs: photoURLs)
        }
    }

    private var totalCard: some View {
        VStack(spacing: 6) {
            Text("Kühllast nach VDI 2078 (Kurzverfahren)")
                .font(.caption)
                .foregroundStyle(accent)
            Text(String(format: "%.0f W", result.total.rounded()))
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(accent)
            Text(String(format: "%.0f W/m²", result.specific(for: room.floorArea)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aufschlüsselung").font(.headline)
            ForEach(items, id: \.0) { name, value, color in
                let fraction = result.total > 0 ? value / result.total : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name).font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f W", value.rounded()))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: max(2, geo.size.width * fraction), height: 6)
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var recommendationCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "air.conditioner.horizontal")
                .font(.system(size: 28))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Empfehlung").font(.caption).foregroundStyle(.secondary)
                Text(recommendation.label).font(.body.weight(.medium))
                Text(String(format: "Auslastung %.0f %%", recommendation.utilization * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var disclaimer: some View {
        Text("Kurzverfahren zur Geräteauslegung. Für den prüffähigen Nachweis ist das vollständige Stundenverfahren nach VDI 2078 erforderlich.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Gelbe Hinweis-Karte, wenn die spezifische Last außerhalb des üblichen
/// Bereichs liegt (Plausibilitätsprüfung) – in beiden Ergebnis-Ansichten genutzt.
struct PlausibilityCard: View {
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(note)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
