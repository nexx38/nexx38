import SwiftUI
import KuehllastCore

/// Bearbeitet einen Raum: Fenster + Ausrichtung, innere Lasten, Klimastandort.
/// Zeigt am Ende das Ergebnis und den Weg zum PDF-Bericht.
struct RoomEditView: View {
    @Binding var room: Room

    private var region: ClimateRegion { ClimateRegion.region(id: room.climateRegionID) }
    private var result: CoolingLoadResult {
        CoolingLoadCalculator(region: region).calculate(room)
    }

    var body: some View {
        Form {
            Section("Raum") {
                TextField("Name", text: $room.name)
                LabeledStepper(label: "Fläche", value: $room.floorArea, unit: "m²", step: 0.5, range: 1...500)
                LabeledStepper(label: "Höhe", value: $room.height, unit: "m", step: 0.05, range: 1.8...6)
            }

            Section("Klimastandort") {
                Picker("Region", selection: $room.climateRegionID) {
                    ForEach(ClimateRegion.all) { r in
                        Text(r.name).tag(r.id)
                    }
                }
                HStack {
                    Text("Auslegung außen")
                    Spacer()
                    Text(String(format: "%.0f °C", region.designOutdoorTemperature))
                        .foregroundStyle(.secondary)
                }
                LabeledStepper(label: "Raumtemperatur", value: $room.indoorTemperature,
                               unit: "°C", step: 1, range: 20...28)
            }

            Section {
                ForEach($room.windows) { $window in
                    WindowEditor(window: $window)
                }
                .onDelete { room.windows.remove(atOffsets: $0) }
                Button {
                    room.windows.append(Window(width: 1.2, height: 1.4))
                } label: {
                    Label("Fenster hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Fenster · Ausrichtung")
            } footer: {
                Text("Die Himmelsrichtung bestimmt den solaren Eintrag – bei der Kühllast der größte Posten.")
            }

            Section {
                ForEach($room.doors) { $door in
                    DoorEditor(door: $door)
                }
                .onDelete { room.doors.remove(atOffsets: $0) }
                Button {
                    room.doors.append(Door(width: 2.4, height: 2.2, isExternal: true,
                                           isGlazed: true))
                } label: {
                    Label("Tür / Schiebefenster hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Türen")
            } footer: {
                Text("Große Schiebefenster erkennt der Scan oft als Tür. Als 'verglast' markiert zählen sie wie ein Fenster (Sonneneintrag).")
            }

            Section("Außenwände") {
                ForEach($room.walls) { $wall in
                    Toggle(isOn: $wall.isExternal) {
                        Text(String(format: "Wand %.2f × %.2f m", wall.width, wall.height))
                            .font(.subheadline)
                    }
                }
            }

            Section("Innere Lasten") {
                Stepper(value: $room.internalLoads.persons, in: 0...50) {
                    Text("Personen: \(room.internalLoads.persons)")
                }
                LabeledStepper(label: "Geräte", value: $room.internalLoads.equipmentWatt,
                               unit: "W", step: 50, range: 0...5000)
                LabeledStepper(label: "Beleuchtung", value: $room.internalLoads.lightingWattPerSqm,
                               unit: "W/m²", step: 1, range: 0...30)
                LabeledStepper(label: "Luftwechsel", value: $room.airChangeRate,
                               unit: "1/h", step: 0.1, range: 0...5)
            }

            Section {
                NavigationLink {
                    ResultView(room: room)
                } label: {
                    HStack {
                        Text("Kühllast")
                        Spacer()
                        Text(String(format: "%.0f W", result.total.rounded()))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(red: 0.33, green: 0.29, blue: 0.72))
                    }
                }
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: RoomJSONExport.fileURL(for: room)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}

private struct WindowEditor: View {
    @Binding var window: Window

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "%.2f m²", window.area))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("", selection: $window.orientation) {
                    ForEach(Orientation.allCases, id: \.self) { o in
                        Text(o.label).tag(o)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            HStack(spacing: 12) {
                CompactField(label: "B", value: $window.width, unit: "m")
                CompactField(label: "H", value: $window.height, unit: "m")
                CompactField(label: "g", value: $window.gValue, unit: "")
            }
            HStack {
                Text("Verschattung")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $window.shading, in: 0.2...1.0)
                Text(String(format: "%.0f %%", window.shading * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DoorEditor: View {
    @Binding var door: Door

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "%.2f m²", door.area))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(door.isGlazed ? "verglast" : "massiv")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                CompactField(label: "B", value: $door.width, unit: "m")
                CompactField(label: "H", value: $door.height, unit: "m")
            }
            Toggle("Verglast (zählt wie Fenster)", isOn: $door.isGlazed)
                .font(.subheadline)
            if door.isGlazed {
                HStack {
                    Text("Ausrichtung").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $door.orientation) {
                        ForEach(Orientation.allCases, id: \.self) { o in
                            Text(o.label).tag(o)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                HStack(spacing: 12) {
                    CompactField(label: "g", value: $door.gValue, unit: "")
                    Text("Verschattung").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $door.shading, in: 0.2...1.0)
                    Text(String(format: "%.0f %%", door.shading * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CompactField: View {
    let label: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
            if !unit.isEmpty {
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LabeledStepper: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let step: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: unit == "°C" || unit == "W" || unit == "W/m²" ? "%.0f %@" : "%.2f %@",
                        value, unit))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}
