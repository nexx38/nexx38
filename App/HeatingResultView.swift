import SwiftUI
import KuehllastCore

struct HeatingResultView: View {
    @EnvironmentObject var store: RoomStore
    let room: Room
    @State private var pdfURL: URL?

    private var accent: Color { Color(red: 0.9, green: 0.4, blue: 0.1) }
    private var calc: HeatingLoadCalculator { HeatingLoadCalculator() }
    private var result: HeatingLoadResult { calc.calculate(room) }
    private var plausibilityNote: String? {
        Plausibility.heatingNote(specific: result.specific(for: room.floorArea))
    }

    private var items: [(String, Double, Color)] {
        [
            ("Transmission", result.transmission, .blue),
            ("Wärmebrücken", result.thermalBridges, .orange),
            ("Lüftung", result.ventilation, .teal)
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
                deltaTCard
                disclaimer
            }
            .padding()
        }
        .navigationTitle("Heizlast")
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
            let photoURLs = (room.photoFilenames ?? []).map { store.photoURL(named: $0) }
            pdfURL = PDFReport.generate(room: room, heatingResult: result,
                                        photoURLs: photoURLs)
        }
    }

    private var totalCard: some View {
        VStack(spacing: 6) {
            Text("Heizlast nach DIN EN 12831")
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

    private var deltaTCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "thermometer")
                .font(.system(size: 28))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Temperaturdifferenz").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "%.0f K", result.deltaT))
                    .font(.body.weight(.medium))
            }
            Spacer()
        }
        .padding()
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var disclaimer: some View {
        Text("Vereinfachtes Verfahren nach DIN EN 12831. Für Bestandsgebäude und komplexe Geometrien wird das vollständige Verfahren empfohlen.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
