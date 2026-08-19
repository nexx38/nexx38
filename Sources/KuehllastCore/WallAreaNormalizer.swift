import Foundation

/// Sorgt dafür, dass gescannte/importierte Wände als NETTO-opake Fläche in die
/// Berechnung eingehen.
///
/// RoomPlan (und der HeizlastScan-JSON-Export) liefern die volle Wandfläche
/// INKLUSIVE der Fenster-/Türöffnungen. Würde man diese Brutto-Fläche ansetzen und
/// zusätzlich Fenster und Türen einzeln rechnen, zählte die Öffnungsfläche doppelt –
/// einmal mit dem (kleinen) Wand-U-Wert und einmal mit dem (großen) Fenster-/Tür-U.
/// Das überschätzt Heiz- und Kühllast systematisch.
///
/// Manuell erfasste Wände sind bereits netto (genau so nutzt es die verifizierte
/// HeizlastProfi-Referenz): dort bleibt `openingDeductionArea` = 0 und nichts ändert
/// sich. Nur die Import-/Scan-Pfade rufen diese Normalisierung auf.
public enum WallAreaNormalizer {

    /// Verteilt die gesamte Öffnungsfläche (Fenster + außenliegende/verglaste Türen)
    /// proportional auf die Brutto-Flächen der Außenwände und schreibt sie als
    /// `openingDeductionArea` in die jeweilige Wand zurück. Innenwände bleiben
    /// unberührt. Abgezogen werden genau die Öffnungen, die auch als eigene
    /// Transmission gerechnet werden – so bleibt die Bilanz konsistent.
    public static func deductingOpenings(walls: [Wall], doors: [Door], windows: [Window]) -> [Wall] {
        let openingArea =
            windows.reduce(0.0) { $0 + $1.area } +
            doors.filter { $0.isExternal || $0.isGlazed }.reduce(0.0) { $0 + $1.area }
        guard openingArea > 0 else { return walls }

        let totalExternalGross = walls.filter { $0.isExternal }.reduce(0.0) { $0 + $1.area }
        guard totalExternalGross > 0 else { return walls }

        return walls.map { wall in
            var w = wall
            guard wall.isExternal else {
                // Innenwände tragen keine Öffnungslast – Abzug zurücksetzen,
                // damit er beim Umschalten nicht als Altlast hängen bleibt.
                w.openingDeductionArea = 0
                return w
            }
            let share = wall.area / totalExternalGross
            // Nie mehr abziehen, als die Wand groß ist (netArea bleibt ≥ 0).
            w.openingDeductionArea = min(wall.area, openingArea * share)
            return w
        }
    }

    /// Verteilt die Öffnungsflächen NEU, nachdem sich außen/innen geändert hat.
    ///
    /// Nötig, weil die erste Verteilung beim Scan stattfindet – dort stehen noch
    /// alle Wände auf „außen". Schaltet der Nutzer danach Innenwände ab (Grundriss,
    /// 3D-Ansicht oder Liste), läge der Abzug weiter auf Wänden, die gar nicht mehr
    /// rechnen: die verbleibende Außenwand wäre dann zu groß und die Last zu hoch.
    ///
    /// Wirkt nur auf Scan-/Import-Räume (erkennbar an einer vorhandenen
    /// Grundriss-Position oder einem bereits gesetzten Abzug). Manuell angelegte
    /// Räume bleiben unberührt – dort sind die Wandmaße bereits netto erfasst.
    public static func redistributeIfScanned(walls: [Wall], doors: [Door], windows: [Window]) -> [Wall] {
        let isScanned = walls.contains { $0.position != nil || $0.openingDeductionArea > 0 }
        guard isScanned else { return walls }
        return deductingOpenings(walls: walls, doors: doors, windows: windows)
    }
}
