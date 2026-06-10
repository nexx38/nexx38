const HLB_CALC = {
  // Transmission heat loss for one component [W]
  // ΦT = A × U × Δθ (with temperature correction for internal boundaries)
  calcComponent(comp, indoorTemp, outdoorTemp) {
    const dt = comp.type === 'internal' && comp.adjacentTemp != null
      ? indoorTemp - comp.adjacentTemp
      : indoorTemp - outdoorTemp;
    return Math.max(0, comp.area * comp.uValue * dt);
  },

  // Transmission heat loss for a room [W]
  calcTransmission(room, outdoorTemp) {
    let total = 0;
    const detail = room.components.map(c => {
      const loss = this.calcComponent(c, room.indoorTemp, outdoorTemp);
      total += loss;
      return { ...c, loss };
    });
    return { total, detail };
  },

  // Ventilation heat loss for a room [W]
  // ΦV = 0.34 Wh/(m³K) × n [1/h] × V [m³] × Δθ [K]
  calcVentilation(room, outdoorTemp) {
    const volume = room.area * room.height;
    const dt = Math.max(0, room.indoorTemp - outdoorTemp);
    const eff = room.vent.hasHeatRecovery
      ? room.vent.airChange * (1 - room.vent.recoveryEff / 100)
      : room.vent.airChange;
    const loss = 0.34 * eff * volume * dt;
    return { loss, volume, effectiveAirChange: eff, dt };
  },

  // Full room heating load
  calcRoom(room, project) {
    const trans = this.calcTransmission(room, project.outdoorTemp);
    const vent  = this.calcVentilation(room, project.outdoorTemp);
    const tbFactor = project.thermalBridges / 100;
    const tbSupplement = trans.total * tbFactor;
    const total = trans.total + tbSupplement + vent.loss;
    return {
      id: room.id,
      name: room.name,
      area: room.area,
      transmission: trans.total,
      thermalBridges: tbSupplement,
      ventilation: vent.loss,
      total,
      specificLoad: room.area > 0 ? total / room.area : 0,
      componentDetail: trans.detail,
      ventDetail: vent,
    };
  },

  // Full project calculation
  calcProject(state) {
    if (!state.rooms.length) return null;
    const roomResults = state.rooms.map(r => this.calcRoom(r, state.project));
    const totalTrans  = roomResults.reduce((s, r) => s + r.transmission, 0);
    const totalTB     = roomResults.reduce((s, r) => s + r.thermalBridges, 0);
    const totalVent   = roomResults.reduce((s, r) => s + r.ventilation, 0);
    const totalLoad   = roomResults.reduce((s, r) => s + r.total, 0);
    const totalArea   = state.rooms.reduce((s, r) => s + (r.area || 0), 0);
    return {
      rooms: roomResults,
      totalTransmission: totalTrans,
      totalThermalBridges: totalTB,
      totalVentilation: totalVent,
      totalLoad,
      totalArea,
      specificLoad: totalArea > 0 ? totalLoad / totalArea : 0,
    };
  },

  fmt(watts) {
    if (watts >= 1000) return (watts / 1000).toFixed(2) + ' kW';
    return Math.round(watts) + ' W';
  },

  fmtW(watts) {
    return Math.round(watts) + ' W';
  },
};
