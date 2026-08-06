import SwiftUI
import KuehllastCore

/// Bearbeitet einen Raum: Baujahr, Fenster + Ausrichtung, innere Lasten,
/// Klimastandort. Zeigt am Ende das Ergebnis und den Weg zum PDF-Bericht.
struct RoomEditView: View {
    @EnvironmentObject var store: RoomStore
    @Binding var room: Room

    private var region: ClimateRegion { ClimateRegion.region(id: room.climateRegionID) }
    private var result: CoolingLoadResult {
        CoolingLoadCalculator(region: region).calculate(room)
    }
    private var heatingResult: HeatingLoadResult {
        HeatingLoadCalculator().calculate(room)
    }

    var body: some View {
        Form {
            Section("Raum") {
                TextField("Name", text: $room.name)
                LabeledStepper(label: "Fläche", value: $room.floorArea, unit: "m²", step: 0.5, range: 1...500)
                LabeledStepper(label: "Höhe", value: $room.height, unit: "m", step: 0.05, range: 1.8...6)
            }

            Section {
                Picker("Baujahr-Klasse", selection: Binding(
                    get: { room.constructionEra ?? "" },
                    set: { raw in
                        if raw.isEmpty {
                            room.constructionEra = nil
                        } else if let era = BuildingEra(rawValue: raw) {
                            room = era.applied(to: room)
                        }
                    }
                )) {
                    Text("keine Vorgabe").tag("")
                    ForEach(BuildingEra.allCases, id: \.rawValue) { era in
                        Text(era.label).tag(era.rawValue)
                    }
                }
            } header: {
                Text("Gebäude")
            } footer: {
                Text("Setzt typische U-Werte für Wände, Fenster und Türen der Epoche (überschreibt vorhandene Werte). Die Annahme wird im PDF-Bericht ausgewiesen und ist vom Fachbetrieb zu prüfen.")
            }

            if let photos = room.photoFilenames, !photos.isEmpty {
                Section("Fotos vom Scan") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos, id: \.self) { name in
                                if let image = UIImage(contentsOfFile: store.photoURL(named: name).path) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 92, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                store.removePhotoFile(named: name)
                                                room.photoFilenames?.removeAll { $0 == name }
                                            } label: {
                                                Label("Foto löschen", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
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
                Text("Große Schiebefenster erkennt der Scan oft als Tür. Als 'verglast' markiert zählen sie wie ein Fenster (Sonneneintrag). Massive Haustüren als 'führt nach außen' markieren, damit sie in die Heizlast eingehen.")
            }

            Section {
                ForEach($room.walls) { $wall in
                    WallEditor(wall: $wall)
                }
            } header: {
                Text("Wände")
            } footer: {
                Text("Nur Außenwände tragen Transmissionslast. Der U-Wert bestimmt den Verlust – bei Altbau deutlich höher (Baujahr-Klasse setzt Vorgaben).")
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

            Section("Heizlast-Parameter (Winter)") {
                Picker("Standort", selection: Binding(
                    get: { room.heating?.climateName ?? "Berlin" },
                    set: { value in
                        if room.heating == nil { room.heating = HeatingParameters() }
                        room.heating?.climateName = value
                    }
                )) {
                    ForEach(HeatingClimate.all, id: \.name) { climate in
                        Text(climate.name).tag(climate.name)
                    }
                }
                LabeledStepper(label: "Raumtemp.", value: Binding(
                    get: { room.heating?.indoorTemperature ?? 20 },
                    set: { value in
                        if room.heating == nil { room.heating = HeatingParameters() }
                        room.heating?.indoorTemperature = value
                    }
                ), unit: "°C", step: 1, range: 15...25)
                LabeledStepper(label: "Wärmebrücken", value: Binding(
                    get: { room.heating?.thermalBridgePercent ?? 5 },
                    set: { value in
                        if room.heating == nil { room.heating = HeatingParameters() }
                        room.heating?.thermalBridgePercent = value
                    }
                ), unit: "%", step: 0.5, range: 0...20)
                LabeledStepper(label: "Wärmerückgew.", value: Binding(
                    get: { room.heating?.heatRecoveryPercent ?? 0 },
                    set: { value in
                        if room.heating == nil { room.heating = HeatingParameters() }
                        room.heating?.heatRecoveryPercent = value
                    }
                ), unit: "%", step: 5, range: 0...95)
                Group {
                    Text("Decke").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        CompactField(label: "U", value: Binding(
                            get: { room.heating?.ceilingUValue ?? 0 },
                            set: { value in
                                if room.heating == nil { room.heating = HeatingParameters() }
                                room.heating?.ceilingUValue = value > 0 ? value : nil
                            }
                        ), unit: "W/(m²K)")
                        CompactField(label: "T°", value: Binding(
                            get: { room.heating?.ceilingAdjacentTemp ?? 10 },
                            set: { value in
                                if room.heating == nil { room.heating = HeatingParameters() }
                                room.heating?.ceilingAdjacentTemp = value
                            }
                        ), unit: "°C")
                    }
                }
                Group {
                    Text("Boden").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        CompactField(label: "U", value: Binding(
                            get: { room.heating?.floorUValue ?? 0 },
                            set: { value in
                                if room.heating == nil { room.heating = HeatingParameters() }
                                room.heating?.floorUValue = value > 0 ? value : nil
                            }
                        ), unit: "W/(m²K)")
                        CompactField(label: "T°", value: Binding(
                            get: { room.heating?.floorAdjacentTemp ?? 10 },
                            set: { value in
                                if room.heating == nil { room.heating = HeatingParameters() }
                                room.heating?.floorAdjacentTemp = value
                            }
                        ), unit: "°C")
                    }
                }
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
                NavigationLink {
                    HeatingResultView(room: room)
                } label: {
                    HStack {
                        Text("Heizlast")
                        Spacer()
                        Text(String(format: "%.0f W", heatingResult.total.rounded()))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(red: 0.9, green: 0.4, blue: 0.1))
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
                CompactField(label: "U", value: $door.uValue, unit: "")
            }
            Toggle("Führt nach außen", isOn: $door.isExternal)
                .font(.subheadline)
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

private struct WallEditor: View {
    @Binding var wall: Wall

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $wall.isExternal) {
                Text(String(format: "Wand %.2f × %.2f m", wall.width, wall.height))
                    .font(.subheadline)
            }
            if wall.isExternal {
                HStack(spacing: 12) {
                    CompactField(label: "U", value: $wall.uValue, unit: "W/(m²K)")
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
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
