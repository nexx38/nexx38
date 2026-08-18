import SwiftUI

/// Bearbeitet die Stammdaten des aktiven Projekts (Kunde/Objekt).
/// Kunde und Adresse erscheinen auf allen PDF-Berichten.
struct ProjectEditView: View {
    @EnvironmentObject var store: RoomStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Project

    init(project: Project) {
        self._draft = State(initialValue: project)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Projekt") {
                    TextField("Name (z. B. EFH Müller)", text: $draft.name)
                }
                Section {
                    TextField("Kunde", text: $draft.customerName)
                    TextField("Adresse", text: $draft.address, axis: .vertical)
                        .lineLimit(2...3)
                } header: {
                    Text("Kundendaten")
                } footer: {
                    Text("Kunde und Adresse erscheinen auf allen PDF-Berichten dieses Projekts.")
                }
            }
            .navigationTitle("Projekt bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.updateProject(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}
