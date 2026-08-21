import SwiftUI
import UIKit
import KuehllastCore

/// Gebäude-/Anlagen-Bildschirm: Wärmepumpen-Auslegung, Multisplit-Klima,
/// Heizkörper-Check und hydraulischer Abgleich über alle Räume – plus der
/// Gesamtbericht als EIN PDF.
struct BuildingView: View {
    @EnvironmentObject var store: RoomStore
    @State private var pdfURL: URL?

    private var wpAccent: Color { Color(red: 0.9, green: 0.4, blue: 0.1) }
    private var acAccent: Color { Color(red: 0.33, green: 0.29, blue: 0.72) }

    private var heatingTotal: Double {
        store.currentRooms.reduce(0.0) { $0 + HeatingLoadCalculator().calculate($1).total }
    }
    private var coolingLoads: [(name: String, coolingLoadW: Double)] {
        store.currentRooms.map { room in
            let region = ClimateRegion.region(id: room.climateRegionID)
            return (room.name, CoolingLoadCalculator(region: region).calculate(room).total)
        }
    }
    private var heatPump: HeatPumpRecommendation {
        HeatPumpSizing.recommend(heatingLoadW: heatingTotal,
                                 dhwPersons: store.building.dhwPersons,
                                 blockingHours: store.building.blockingHours)
    }
    private var multiSplit: MultiSplitPlan {
        MultiSplitSizing.plan(rooms: coolingLoads,
                              simultaneity: store.building.simultaneity)
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: $store.building.dhwPersons, in: 0...12) {
                    Text("Personen (Warmwasser): \(store.building.dhwPersons)")
                }
                SettingStepper(label: "EVU-Sperrzeit", value: $store.building.blockingHours,
                               unit: "h", step: 1, range: 0...6, decimals: 0)
                SettingStepper(label: "Vorlauf Heizkörper", value: $store.building.flowTemp,
                               unit: "°C", step: 5, range: 30...75, decimals: 0)
                SettingStepper(label: "Rücklauf Heizkörper", value: $store.building.returnTemp,
                               unit: "°C", step: 5, range: 25...65, decimals: 0)
                SettingStepper(label: "Vorlauf Fußboden", value: $store.building.underfloorFlowTemp,
                               unit: "°C", step: 1, range: 25...50, decimals: 0)
                SettingStepper(label: "Rücklauf Fußboden", value: $store.building.underfloorReturnTemp,
                               unit: "°C", step: 1, range: 20...45, decimals: 0)
                SettingStepper(label: "Spreizung Abgleich", value: $store.building.spreadK,
                               unit: "K", step: 1, range: 5...20, decimals: 0)
                SettingStepper(label: "Gleichzeitigkeit Klima", value: $store.building.simultaneity,
                               unit: "", step: 0.05, range: 0.5...1.0, decimals: 2)
            } header: {
                Text("Anlagen-Einstellungen")
            } footer: {
                Text("Heizkörper und Fußbodenheizung laufen in derselben Anlage mit unterschiedlichen Temperaturen – deshalb zwei Paare.")
            }

            componentsSection

            Section {
                row("Heizlast Gebäude", String(format: "%.0f W", heatingTotal.rounded()))
                row("Warmwasser-Zuschlag", String(format: "+ %.0f W", heatPump.dhwW))
                row("Sperrzeit-Faktor", String(format: "× %.2f", heatPump.blockingFactor))
                row("Erforderlich", String(format: "%.1f kW", heatPump.requiredKW))
                HStack {
                    Image(systemName: "heat.waves")
                        .foregroundStyle(wpAccent)
                    Text("Empfehlung")
                    Spacer()
                    Text(String(format: "%.0f-kW-Wärmepumpe", heatPump.suggestedKW))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(wpAccent)
                }
            } header: {
                Text("Wärmepumpen-Auslegung")
            } footer: {
                Text("Überschlägig nach VDI 4645 (Heizlast + Warmwasser, hochgerechnet um die Sperrzeit). Bivalenzpunkt und Modulation klärt die Fachplanung.")
            }

            Section {
                ForEach(multiSplit.indoorUnits, id: \.roomName) { unit in
                    HStack {
                        Text(unit.roomName)
                        Spacer()
                        Text(String(format: "%.0f W → %.1f kW", unit.coolingLoadW.rounded(), unit.unitKW))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Image(systemName: "air.conditioner.horizontal")
                        .foregroundStyle(acAccent)
                    Text("Außengerät")
                    Spacer()
                    Text(String(format: "ab %.1f kW", multiSplit.outdoorRequiredKW))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(acAccent)
                }
            } header: {
                Text("Klima / Multisplit")
            } footer: {
                Text(String(format: "Innengeräte-Summe %.1f kW × Gleichzeitigkeit %.2f. Bei nur einem Raum gilt die Einzelgerät-Empfehlung.",
                            multiSplit.indoorTotalKW, multiSplit.simultaneity))
            }

            radiatorSection

            Section {
                if roomsWithRadiators.isEmpty {
                    Text("Heizkörper in den Räumen erfassen, dann erscheinen hier Volumenstrom und Ventil-Voreinstellung je Heizkörper.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(roomsWithRadiators, id: \.room.id) { entry in
                        ForEach(Array(entry.presets.enumerated()), id: \.offset) { index, item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.room.name) · HK \(index + 1)")
                                        .font(.subheadline)
                                    Text(item.radiator.type.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.preset.presetLabel)
                                        .font(.subheadline.weight(.medium))
                                    Text(String(format: "%.0f kg/h", item.preset.flowKgPerH))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Hydraulischer Abgleich (Verfahren B)")
            } footer: {
                Text("Vereinfachtes Verfahren B: Raumlast anteilig je Heizkörper, generische Ventilstufen. Die Hersteller-Ventiltabelle bleibt maßgebend.")
            }
        }
        .navigationTitle("Gebäude / Anlage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            // Die Dezimal-Tastatur hat keinen eigenen Schließen-Knopf.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
        .task {
            pdfURL = BuildingPDFReport.generate(rooms: store.currentRooms, settings: store.building,
                                                project: store.currentProject)
        }
        .onChange(of: store.building) { _, _ in
            // Rücklauf muss unter dem Vorlauf bleiben (sonst Unsinnswerte).
            if store.building.returnTemp >= store.building.flowTemp {
                store.building.returnTemp = max(25, store.building.flowTemp - 10)
            }
            pdfURL = BuildingPDFReport.generate(rooms: store.currentRooms, settings: store.building,
                                                project: store.currentProject)
        }
    }

    // MARK: - Zentrale Bauteilwerte ("Bauteilbibliothek")

    /// Einmal fürs Gebäude festlegen statt in jedem Raum – im Feldtest war
    /// das Nachtragen je Raum die lästigste und fehleranfälligste Stelle.
    @ViewBuilder
    private var componentsSection: some View {
        Section {
            Picker("Baujahr-Klasse", selection: Binding(
                get: { store.building.components.era ?? "" },
                set: { raw in
                    if let era = BuildingEra(rawValue: raw) {
                        store.building.components = BuildingComponents.fromEra(era)
                    }
                }
            )) {
                Text("eigene Werte").tag("")
                ForEach(BuildingEra.allCases, id: \.rawValue) { era in
                    Text(era.label).tag(era.rawValue)
                }
            }

            ComponentField(label: "Außenwand", value: $store.building.components.wallU, unit: "W/(m²K)")
            ComponentField(label: "Fenster", value: $store.building.components.windowU, unit: "W/(m²K)")
            ComponentField(label: "Fenster g-Wert", value: $store.building.components.windowG, unit: "")
            ComponentField(label: "Außentür", value: $store.building.components.doorU, unit: "W/(m²K)")
            ComponentField(label: "Dach / Decke", value: $store.building.components.roofU, unit: "W/(m²K)")
            ComponentField(label: "Boden", value: $store.building.components.floorU, unit: "W/(m²K)")

            Button {
                let components = store.building.components
                for index in store.rooms.indices
                where store.rooms[index].projectID == store.currentProjectID {
                    store.rooms[index] = components.applied(to: store.rooms[index])
                }
            } label: {
                Label("Auf alle \(store.currentRooms.count) Räume übertragen",
                      systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(store.currentRooms.isEmpty)
        } header: {
            Text("Bauteilwerte (Gebäude)")
        } footer: {
            Text("Baujahr-Klasse wählen oder Werte selbst eintragen, dann übertragen. Einzelne Räume dürfen danach abweichen (neuer Anbau, erneuerte Fenster). Decke und Boden werden nur dort gesetzt, wo sie im Raum schon angesetzt sind.")
        }
    }

    // MARK: - Heizkörper-Check

    private struct RadiatorRoomEntry {
        let room: Room
        let check: RadiatorCheckResult
        let presets: [(radiator: Radiator, preset: ValvePreset)]
    }

    private var roomsWithRadiators: [RadiatorRoomEntry] {
        store.currentRooms.compactMap { room in
            guard let radiators = room.radiators, !radiators.isEmpty else { return nil }
            let roomTemp = room.heating?.indoorTemperature ?? 20
            let demand = HeatingLoadCalculator().calculate(room).total
            let capacity = radiators.reduce(0.0) {
                $0 + $1.power(flow: store.building.flowTemp,
                              ret: store.building.returnTemp, roomTemp: roomTemp)
            }
            // Raumlast anteilig nach Norm-Leistung auf die Heizkörper verteilen.
            let normTotal = radiators.reduce(0.0) { $0 + $1.normPower }
            let presets = radiators.map { radiator in
                let share = normTotal > 0 ? radiator.normPower / normTotal : 0
                return (radiator,
                        HydraulicBalancing.preset(loadW: demand * share,
                                                  spreadK: store.building.spreadK))
            }
            return RadiatorRoomEntry(room: room,
                                     check: RadiatorCheckResult(capacity: capacity, demand: demand),
                                     presets: presets)
        }
    }

    @ViewBuilder
    private var radiatorSection: some View {
        Section {
            if roomsWithRadiators.isEmpty {
                Text("Noch keine Heizkörper erfasst – im Raum-Editor unter 'Heizkörper (Bestand)' hinzufügen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(roomsWithRadiators, id: \.room.id) { entry in
                    HStack {
                        Text(entry.room.name)
                        Spacer()
                        Text(String(format: "%.0f %% – %@",
                                    entry.check.coverage * 100, entry.check.verdict.label))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(entry.check.verdict == .zuKlein ? .red :
                                             entry.check.verdict == .knapp ? .orange : .green)
                    }
                }
            }
        } header: {
            Text(String(format: "Heizkörper-Check bei %.0f/%.0f °C",
                        store.building.flowTemp, store.building.returnTemp))
        } footer: {
            Text("Grün = Bestand reicht für Wärmepumpe, Orange = knapp (Einzelfall prüfen), Rot = Heizkörper vergrößern oder Vorlauf anheben.")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Zahlenfeld für einen zentralen Bauteilwert.
private struct ComponentField: View {
    let label: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
            if !unit.isEmpty {
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingStepper: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let step: Double
    let range: ClosedRange<Double>
    let decimals: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.\(decimals)f %@", value, unit))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}
