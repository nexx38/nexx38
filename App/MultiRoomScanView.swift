import SwiftUI
import RoomPlan
import ARKit
import UIKit
import KuehllastCore

// MARK: - Warum es diesen zweiten Scan-Ablauf gibt
//
// Der Scan stuft JEDE Wand als Außenwand ein. Im Feldtest standen bei einem
// Wohnzimmer 21 Wandstücke auf „außen", die Kühllast lag dadurch bei 6261 W
// statt realistischen ~2400 W. `RoomAdjacency` (Core) kann das rein
// geometrisch reparieren: es sucht Wandpaare, die dieselbe Trennwand von
// beiden Seiten zeigen. Voraussetzung ist, dass alle Räume im SELBEN
// Koordinatensystem liegen – und das gilt nur, wenn sie in EINER
// AR-Sitzung ohne Unterbrechung erfasst wurden. Genau das leistet diese
// Ansicht.
//
// Umsetzung (Apple, WWDC23 „Explore enhancements to RoomPlan", Ansatz 1
// „Continuous ARSession", und Doku „Scanning the rooms of a single
// structure"): EINE `RoomCaptureView` bleibt über den ganzen Ablauf am
// Leben. Ihre `captureSession` wird pro Raum mit `run(configuration:)`
// gestartet und mit `stop(pauseARSession: false)` beendet – das `false` ist
// der Kern: die darunterliegende ARSession läuft weiter und behält ihren
// Weltursprung. Für den nächsten Raum wird `run(configuration:)` auf
// DERSELBEN Session erneut aufgerufen.
//
// Bewusst KEINE eigene ARSession über `RoomCaptureView(frame:arSession:)`:
// Apple schreibt zu diesem Initialisierer „RoomPlan preserves all of the AR
// session's settings" – eine selbst gebaute `ARWorldTrackingConfiguration`
// würde also die von RoomPlan gewählten Scan-Einstellungen ersetzen und
// könnte die Scanqualität verschlechtern. Solange eine einzige Session
// durchläuft, brauchen wir sie auch nicht. (Eigene ARSession wäre erst für
// den Relokalisierungs-Weg nötig: Räume an verschiedenen Tagen scannen und
// über eine gespeicherte `ARWorldMap` wieder zusammenführen.)
//
// Der Einzelraum-Scan (`RoomScanView.swift`) bleibt davon völlig unberührt.

/// Ablauf-Zustand des Mehrraum-Scans.
enum MultiRoomPhase: Equatable {
    /// Ein Raum wird gerade abgegangen.
    case scanning
    /// RoomPlan rechnet den eben beendeten Raum aus (dauert einige Sekunden).
    case processing
    /// Der Raum liegt vor – weiter mit dem nächsten oder abschließen?
    case roomDone
    /// Räume werden umgerechnet, Innenwände erkannt und gespeichert.
    case saving
    /// Alles gespeichert, Ergebnis wird angezeigt.
    case finished
}

/// Beobachtbarer Zustand des Mehrraum-Scans.
/// Alle Änderungen laufen über den Main-Thread (die Rückrufe dispatchen dorthin).
final class MultiRoomScanModel: ObservableObject {

    @Published var phase: MultiRoomPhase = .scanning
    @Published var statusMessage: String?
    /// Zusätzlicher Warnhinweis (z. B. AR-Ortung wackelig) – blockiert nicht.
    @Published var hintMessage: String?
    /// Fehlermeldung des zuletzt beendeten Raums. Wirft die bereits erfassten
    /// Räume NICHT weg: der Nutzer kann den Raum wiederholen oder abschließen.
    @Published var roomErrorText: String?
    @Published var canFinishRoom = false
    @Published var photoCount = 0
    /// Anzahl fertig verarbeiteter Räume (nur für die Anzeige).
    @Published var finishedRoomCount = 0
    /// Abschlusstext („X Räume erfasst, Y Trennwände …").
    @Published var summaryText: String?

    /// Fertige Räume dieser Sitzung – alle im selben Koordinatensystem.
    private(set) var capturedRooms: [CapturedRoom] = []
    /// Fotos je fertigem Raum, gleiche Reihenfolge wie `capturedRooms`.
    private(set) var photosPerRoom: [[Data]] = []
    /// Fotos des Raums, der gerade gescannt wird.
    private var currentPhotos: [Data] = []

    /// Läuft gerade eine Capture-Session? Verhindert `stop` ohne `run`
    /// (und umgekehrt) – RoomPlan reagiert auf so etwas unwirsch.
    var isSessionRunning = false
    /// Abbruch angefordert: RoomPlan soll nichts mehr nachrechnen.
    var isCancelling = false
    /// Ansicht ist beendet – späte Rückrufe laufen ins Leere statt in einen
    /// halb abgebauten Zustand.
    var isTornDown = false

    // Von der UIKit-Brücke gesetzt (siehe MultiRoomScanRepresentable).
    var onStartRoom: (() -> Void)?
    var onStopRoom: (() -> Void)?
    var onCapturePhoto: (() -> Void)?
    var onTeardown: (() -> Void)?
    /// Liefert einen Warntext, wenn die AR-Ortung wackelt. Wird bewusst als
    /// Closure gereicht: `RoomCaptureView` ist Main-Actor-gebunden, der
    /// Delegate-Rückruf dagegen nicht – so bleibt der Zugriff dort, wo er
    /// erlaubt ist (angelegt in `makeUIView`).
    var trackingWarning: (() -> String?)?

    init() {
        statusMessage = Self.scanHint(roomNumber: 1)
    }

    static func scanHint(roomNumber: Int) -> String {
        "Raum \(roomNumber) langsam abgehen – Wände, Türen und Fenster werden erfasst"
    }

    // MARK: Ablaufsteuerung

    /// Startet den nächsten Raum. Die AR-Sitzung läuft dabei weiter, deshalb
    /// bleibt der Weltursprung erhalten und die Räume passen später zusammen.
    func startNextRoom() {
        guard !isTornDown else { return }
        roomErrorText = nil
        hintMessage = nil
        canFinishRoom = false
        photoCount = 0
        currentPhotos.removeAll()
        phase = .scanning
        statusMessage = Self.scanHint(roomNumber: finishedRoomCount + 1)
        onStartRoom?()
    }

    /// Beendet den aktuellen Raum und stößt die Nachbearbeitung an.
    func finishCurrentRoom() {
        guard !isTornDown, phase == .scanning else { return }
        phase = .processing
        hintMessage = nil
        statusMessage = "Raum wird ausgewertet …"
        onStopRoom?()
    }

    func capturePhoto() {
        guard phase == .scanning else { return }
        onCapturePhoto?()
    }

    func addPhoto(_ data: Data) {
        currentPhotos.append(data)
        photoCount = currentPhotos.count
    }

    /// Ein Raum ist fertig verarbeitet und wird eingesammelt.
    func appendRoom(_ room: CapturedRoom, warning: String?) {
        guard !isTornDown, !isCancelling else { return }
        capturedRooms.append(room)
        photosPerRoom.append(currentPhotos)
        currentPhotos.removeAll()
        photoCount = 0
        finishedRoomCount = capturedRooms.count
        roomErrorText = nil
        hintMessage = warning
        phase = .roomDone
        statusMessage = "Weiter zum nächsten Raum – oder abschließen."
    }

    /// Ein Raum ließ sich nicht auswerten. Bewusst kein Abbruch der ganzen
    /// Sitzung: bereits erfasste Räume bleiben erhalten, der Nutzer kommt
    /// über „Raum wiederholen" oder „Alle Räume fertig" immer weiter.
    func failCurrentRoom(_ message: String) {
        guard !isTornDown, !isCancelling else { return }
        currentPhotos.removeAll()
        photoCount = 0
        hintMessage = nil
        roomErrorText = message
        phase = .roomDone
        statusMessage = capturedRooms.isEmpty
            ? "Bitte den Raum noch einmal scannen."
            : "Raum wiederholen – oder mit den bereits erfassten Räumen abschließen."
    }

    func beginSaving() {
        phase = .saving
        statusMessage = nil
        hintMessage = nil
        roomErrorText = nil
    }

    func finishSaving(summary: String) {
        summaryText = summary
        phase = .finished
    }

    /// Gibt Kamera und LiDAR frei. Mehrfach aufrufbar (idempotent), damit
    /// Abbrechen, Abschließen und `onDisappear` sich nicht in die Quere kommen.
    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        isCancelling = true
        onTeardown?()
        onStartRoom = nil
        onStopRoom = nil
        onCapturePhoto = nil
        onTeardown = nil
        trackingWarning = nil
    }
}

// MARK: - Ansicht

/// Mehrere Räume nacheinander in EINER Sitzung scannen und am Ende
/// gemeinsam auswerten (Trennwand-Erkennung).
struct MultiRoomScanView: View {
    @EnvironmentObject var store: RoomStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MultiRoomScanModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            // ⚠️ Diese Ansicht NIE in ein `if` packen und nie mit `.id(…)`
            // versehen: SwiftUI würde die RoomCaptureView neu aufbauen, die
            // AR-Sitzung risse ab und die Räume lägen anschließend in
            // verschiedenen Koordinatensystemen – die Trennwand-Erkennung
            // fände dann nichts mehr. Ein-/Ausblenden nur per Overlay.
            MultiRoomScanRepresentable(model: model)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                banner
                controls
            }
            .padding(.bottom, 44)
        }
        .overlay {
            if model.phase == .saving || model.phase == .finished {
                resultOverlay
            }
        }
        // Sicherheitsnetz: wird die Ansicht auf anderem Weg geschlossen,
        // muss die Kamera trotzdem freigegeben werden.
        .onDisappear { model.teardown() }
        .statusBarHidden()
    }

    // MARK: Hinweise über den Knöpfen

    private var capturedCountText: String {
        model.finishedRoomCount == 1
            ? "1 Raum erfasst"
            : "\(model.finishedRoomCount) Räume erfasst"
    }

    private var banner: some View {
        VStack(spacing: 8) {
            if model.finishedRoomCount > 0 {
                Text(capturedCountText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            if let error = model.roomErrorText {
                bubble("Dieser Raum ließ sich nicht auswerten: \(error)")
            }
            if let hint = model.hintMessage {
                bubble("⚠️ " + hint)
            }
            if let message = model.statusMessage {
                bubble(message)
            }
            if model.phase == .roomDone {
                bubble("Beim Wechseln die Kamera weiter auf die Umgebung richten "
                       + "und nicht abdecken – sonst verliert das iPhone die "
                       + "gemeinsame Orientierung und die Räume passen nicht zusammen.")
            }
        }
        .padding(.horizontal, 20)
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Bedienung

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .scanning:
            HStack(spacing: 16) {
                Button("Abbrechen", role: .cancel) { cancel() }
                    .buttonStyle(.bordered)

                // Foto zur Dokumentation, ohne den Scan zu unterbrechen –
                // gehört zum Raum, der gerade abgegangen wird.
                Button {
                    model.capturePhoto()
                } label: {
                    Label(model.photoCount > 0 ? "\(model.photoCount)" : "Foto",
                          systemImage: "camera.fill")
                }
                .buttonStyle(.bordered)

                Button("Raum fertig") { model.finishCurrentRoom() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canFinishRoom)
            }

        case .processing:
            HStack(spacing: 16) {
                ProgressView()
                Button("Abbrechen", role: .cancel) { cancel() }
                    .buttonStyle(.bordered)
            }

        case .roomDone:
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    Button {
                        model.startNextRoom()
                    } label: {
                        Label(model.roomErrorText == nil ? "Nächster Raum" : "Raum wiederholen",
                              systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Alle Räume fertig") { finishAll() }
                        .buttonStyle(.bordered)
                        .disabled(model.finishedRoomCount == 0)
                }
                Button("Abbrechen", role: .cancel) { cancel() }
                    .buttonStyle(.bordered)
                    .font(.footnote)
            }

        case .saving, .finished:
            EmptyView()
        }
    }

    /// Speichern-/Ergebnisschirm. Bewusst als Overlay mit eigenem „Fertig"-
    /// Knopf statt als Alert: so gibt es garantiert immer einen Ausweg.
    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 18) {
                if model.phase == .saving {
                    ProgressView()
                        .tint(.white)
                    Text("Räume werden gespeichert …")
                        .font(.headline)
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(.green)
                    Text(model.summaryText ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Button("Fertig") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: Aktionen

    private func cancel() {
        model.teardown()
        dismiss()
    }

    private func finishAll() {
        guard model.phase == .roomDone else { return }
        let captured = model.capturedRooms
        let photos = model.photosPerRoom
        model.beginSaving()
        // Kamera und LiDAR sofort freigeben – ab hier wird nur noch gerechnet.
        model.teardown()

        guard !captured.isEmpty else {
            dismiss()
            return
        }
        // Bewusst synchron auf dem Main-Thread: der USDZ-Export blockiert
        // kurz (wie beim Einzelraum-Scan auch), dafür bleibt der ganze Ablauf
        // in einem Zustandsraum – kein halb gespeichertes Ergebnis möglich.
        persist(captured: captured, photos: photos)
    }

    /// Wandelt die erfassten Räume um, erkennt Trennwände und legt sie ab.
    private func persist(captured: [CapturedRoom], photos: [[Data]]) {
        var taken = Set(store.currentRooms.map(\.name))
        var rooms: [Room] = []

        for (offset, capturedRoom) in captured.enumerated() {
            let name = Self.freeName(preferred: offset + 1, taken: &taken)
            var room = RoomPlanConverter.room(from: capturedRoom, name: name)

            let roomPhotos = photos.indices.contains(offset) ? photos[offset] : []
            let photoNames = roomPhotos.compactMap { store.savePhotoData($0) }
            if !photoNames.isEmpty { room.photoFilenames = photoNames }

            // 3D-Modell je Raum sichern (wie beim Einzelraum-Scan). Schlägt
            // der Export fehl, bleibt der Raum trotzdem erhalten.
            let modelName = UUID().uuidString + ".usdz"
            if (try? capturedRoom.export(to: store.modelURL(named: modelName))) != nil {
                room.modelFilename = modelName
            }
            rooms.append(room)
        }

        // Kernstück: Wände, die einer Wand eines Nachbarraums gegenüberstehen,
        // werden zu Innenwänden. Bewusst NUR innerhalb dieser Scan-Sitzung –
        // Räume aus früheren Sitzungen haben ein eigenes Koordinatensystem,
        // ein Vergleich mit ihnen würde zufällige Treffer liefern und die
        // Heizlast gefährlich zu klein rechnen.
        let pairCount = RoomAdjacency.detect(in: rooms).pairCount
        var adjusted = RoomAdjacency.applied(to: rooms)

        // Die Öffnungsabzüge (Fenster/Türen) hängen anteilig an den
        // AUSSENwänden. Da eben Wände auf innen umgestellt wurden, muss der
        // Abzug neu verteilt werden – sonst bliebe er auf Wänden liegen, die
        // gar nicht mehr in die Transmission eingehen, und die verbleibende
        // Außenwand wäre zu groß. (Gleiche Normalisierung wie im Raum-Editor.)
        for index in adjusted.indices {
            adjusted[index].walls = WallAreaNormalizer.redistributeIfScanned(
                walls: adjusted[index].walls,
                doors: adjusted[index].doors,
                windows: adjusted[index].windows)
        }

        for room in adjusted { store.add(room) }
        model.finishSaving(summary: Self.summaryText(roomCount: adjusted.count,
                                                     pairCount: pairCount))
    }

    /// Vergibt fortlaufende, im Projekt noch freie Raumnamen („Raum 1", „Raum 2" …).
    private static func freeName(preferred: Int, taken: inout Set<String>) -> String {
        var number = max(1, preferred)
        while taken.contains("Raum \(number)") { number += 1 }
        let name = "Raum \(number)"
        taken.insert(name)
        return name
    }

    private static func summaryText(roomCount: Int, pairCount: Int) -> String {
        let rooms = roomCount == 1 ? "1 Raum erfasst" : "\(roomCount) Räume erfasst"
        let walls = pairCount == 1
            ? "1 Trennwand automatisch als Innenwand erkannt"
            : "\(pairCount) Trennwände automatisch als Innenwand erkannt"
        var text = "\(rooms), \(walls)."

        if roomCount == 1 {
            text += "\n\nMit nur einem Raum lässt sich keine Trennwand erkennen – "
                  + "dafür müssen mindestens zwei aneinandergrenzende Räume in "
                  + "derselben Sitzung gescannt werden."
        } else if pairCount == 0 {
            text += "\n\nEs wurde keine gemeinsame Wand gefunden. Entweder grenzen "
                  + "die Räume nicht aneinander, oder die Ortung ist zwischen den "
                  + "Räumen abgerissen. Bitte Innen- und Außenwände je Raum im "
                  + "Grundriss prüfen."
        } else {
            text += "\n\nBitte trotzdem stichprobenartig prüfen: im Zweifel bleibt "
                  + "eine Wand außen, das ist die sichere Seite."
        }
        return text
    }
}

// MARK: - Brücke zu RoomPlan

/// Bindeglied zwischen SwiftUI und Apples `RoomCaptureView` (UIKit).
/// Es gibt genau EINE Instanz pro Mehrraum-Sitzung; ihre `captureSession`
/// wird pro Raum neu gestartet, ohne die AR-Sitzung abreißen zu lassen.
struct MultiRoomScanRepresentable: UIViewRepresentable {
    @ObservedObject var model: MultiRoomScanModel

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        view.delegate = context.coordinator

        model.onStartRoom = { [weak view, weak model] in
            guard let view, let model, !model.isSessionRunning else { return }
            model.isSessionRunning = true
            view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        }

        model.onStopRoom = { [weak view, weak model] in
            guard let view, let model, model.isSessionRunning else { return }
            model.isSessionRunning = false
            // `pauseARSession: false` ist der Kern des Mehrraum-Scans: die
            // AR-Sitzung läuft weiter und behält ihren Weltursprung, damit
            // der nächste Raum im selben Koordinatensystem landet.
            view.captureSession.stop(pauseARSession: false)
        }

        model.onCapturePhoto = { [weak view, weak model] in
            guard let view, let model,
                  let frame = view.captureSession.arSession.currentFrame,
                  let data = ScanPhotoConverter.jpegData(from: frame) else { return }
            model.addPhoto(data)
        }

        // Zustand der AR-Ortung. Reißt sie zwischen zwei Räumen ab, liegen die
        // Räume hinterher NICHT mehr im selben Koordinatensystem – die
        // Trennwand-Erkennung findet dann nichts, und der Nutzer merkt es sonst
        // erst ganz am Ende. Deshalb sofort nach jedem Raum prüfen und warnen.
        model.trackingWarning = { [weak view] in
            guard let camera = view?.captureSession.arSession.currentFrame?.camera else {
                return nil
            }
            switch camera.trackingState {
            case .normal:
                return nil
            case .notAvailable:
                return "Die Ortung ist abgerissen. Bitte langsam in den zuletzt "
                     + "gescannten Bereich zurückgehen, bevor der nächste Raum startet."
            case .limited(let reason):
                switch reason {
                case .relocalizing:
                    return "Das iPhone sucht seine Orientierung. Bitte in den zuletzt "
                         + "gescannten Raum zurückgehen, bis das Bild wieder ruhig läuft."
                case .excessiveMotion:
                    return "Zu schnelle Bewegung – das Gerät ruhiger führen, sonst "
                         + "passen die Räume nicht zusammen."
                case .insufficientFeatures:
                    return "Zu dunkel oder zu kahl – Licht einschalten, sonst passen "
                         + "die Räume nicht zusammen."
                case .initializing:
                    return nil
                @unknown default:
                    return nil
                }
            @unknown default:
                return nil
            }
        }

        model.onTeardown = { [weak view, weak model] in
            guard let view, let model else { return }
            if model.isSessionRunning {
                model.isSessionRunning = false
                // Hier MIT Pause: der Scan wird verworfen, Kamera frei.
                view.captureSession.stop(pauseARSession: true)
            } else {
                // Capture-Session steht bereits (nach `stop(pauseARSession: false)`),
                // nur die AR-Sitzung läuft noch – die hier anhalten, sonst
                // bleiben Kamera und LiDAR aktiv.
                view.captureSession.arSession.pause()
            }
        }

        // Erster Raum startet automatisch, sobald die Ansicht steht.
        DispatchQueue.main.async { model.startNextRoom() }
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    func makeCoordinator() -> MultiRoomScanCoordinator {
        MultiRoomScanCoordinator(model: model)
    }
}

/// Top-level (nicht verschachtelt), damit diese NSObject-Unterklasse einen
/// stabilen Objective-C-Laufzeitnamen bekommt – eine verschachtelte
/// NSObject-Unterklasse scheitert beim Archivieren im Release-Build.
/// (Gleiche Falle wie beim Einzelraum-Scan.)
final class MultiRoomScanCoordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    let model: MultiRoomScanModel

    init(model: MultiRoomScanModel) { self.model = model }

    // RoomCaptureViewDelegate erbt NSCoding, weil RoomCaptureView seinen
    // Delegate intern zur Laufzeit archiviert. `nil` würde RoomPlan abstürzen
    // lassen – daher eine echte, aber inaktive Instanz. Die Rückrufe erreichen
    // weiter den in makeUIView zugewiesenen, lebenden Coordinator.
    required init?(coder: NSCoder) {
        self.model = MultiRoomScanModel()
        super.init()
    }
    func encode(with coder: NSCoder) {}

    // MARK: RoomCaptureSessionDelegate

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        DispatchQueue.main.async {
            // Nur während des Abgehens relevant – sonst würde ein später
            // Rückruf den „Raum fertig"-Knopf im falschen Zustand freigeben.
            guard self.model.phase == .scanning else { return }
            self.model.canFinishRoom = !room.walls.isEmpty
        }
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        // Beim Abbrechen darf RoomPlan nichts mehr nachrechnen: sonst käme
        // ein `didPresent` für einen Raum, den niemand mehr haben will.
        !model.isCancelling
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        // Zustand der AR-Ortung noch abgreifen, solange die Sitzung frisch ist.
        let warning = model.trackingWarning?()
        if let error = error {
            DispatchQueue.main.async {
                self.model.failCurrentRoom(error.localizedDescription)
            }
            return
        }
        DispatchQueue.main.async {
            self.model.appendRoom(processedResult, warning: warning)
        }
    }
}
