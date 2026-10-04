/**
 * ============================================================================
 * SHAPNEST MULTI-NODE DISTANCE MONITOR — APPLICATION LOGIC
 * Architecture:
 *   - Dual-Engine: Web Serial (Central Hub) + Web Bluetooth (Direct Node Scan)
 *   - 3 Modes: Hub-Only, Local BLE-Only, Dual-Comparison
 *   - Dynamic Distance Unit: Meters ('m') <-> Centimeters ('cm')
 *   - Physical Clamping: 0.15 m floor, > 8.0 m ceiling (OUT_OF_RANGE)
 *   - In-App Virtual Simulator with prominent DEMO / SIMULATION warning
 * ============================================================================
 */

(() => {
  'use strict';

  /* -------------------------------------------------------------------------- */
  /* CONSTANTS & CONFIGURATION                                                  */
  /* -------------------------------------------------------------------------- */
  const PROTOCOL_ID = 0x534E; // 'SN'
  const FRAME_TYPE_NODE_BEACON = 0x01;
  const FRAME_TYPE_WRISTBAND_TEL = 0x02;

  const DISTANCE_MIN_M = 0.15;
  const DISTANCE_MAX_M = 8.00;

  /* -------------------------------------------------------------------------- */
  /* APPLICATION STATE STORE                                                    */
  /* -------------------------------------------------------------------------- */
  const state = {
    // Distance Display Unit: 'm' (meters) or 'cm' (centimeters)
    distanceUnit: 'm',

    // Simulation / Demo Mode State
    isSimulating: false,
    simTimer: null,
    simAngle: 0,

    // Environmental Exponent (n) Override for local validation
    nOverrideEnabled: false,
    nOverrideValue: 2.2,

    // Web Serial Engine State (Central Hub Link)
    serial: {
      port: null,
      reader: null,
      isConnected: false,
      lastRxTime: 0,
      watchdogTimer: null,
      stats: { seq: 0, validFrames: 0, corruptedLines: 0, lastHzTime: Date.now(), hzCount: 0, currentHz: 0.0 }
    },

    // Web Bluetooth Engine State (Direct Node Validation Scan)
    bluetooth: {
      scan: null,
      isScanning: false,
      nodesSeen: new Set()
    },

    // Multi-Node Internal Telemetry Data Table (Nodes 1..3: Fan, Iron, Door)
    nodes: {
      1: { wb: { dist_m: null, rssi: null, state: 'OFFLINE', refA: null, n: null, lastSeen: 0 },
           ble: { dist_m: null, rssi: null, pkts: 0, refA: -59, n: 2.2, lastSeen: 0 } },
      2: { wb: { dist_m: null, rssi: null, state: 'OFFLINE', refA: null, n: null, lastSeen: 0 },
           ble: { dist_m: null, rssi: null, pkts: 0, refA: -59, n: 2.2, lastSeen: 0 } },
      3: { wb: { dist_m: null, rssi: null, state: 'OFFLINE', refA: null, n: null, lastSeen: 0 },
           ble: { dist_m: null, rssi: null, pkts: 0, refA: -59, n: 2.2, lastSeen: 0 } }
    },

    wristband: {
      id: 1,
      status: 'OFFLINE',
      age_ms: 0,
      seq: 0
    }
  };

  /* -------------------------------------------------------------------------- */
  /* DOM ELEMENT REFERENCES                                                     */
  /* -------------------------------------------------------------------------- */
  const dom = {
    // Unit Buttons
    btnUnitM: document.getElementById('unit-btn-m'),
    btnUnitCm: document.getElementById('unit-btn-cm'),

    // Global Actions
    btnConnectHub: document.getElementById('btn-connect-hub'),
    btnScanBle: document.getElementById('btn-scan-ble'),
    btnToggleSim: document.getElementById('btn-toggle-sim'),
    btnExitSim: document.getElementById('btn-exit-sim'),
    simBanner: document.getElementById('simulation-banner'),

    // Status Ribbon
    valHubStatus: document.getElementById('val-hub-status'),
    tagHubPort: document.getElementById('tag-hub-port'),
    dotHub: document.querySelector('#status-hub .status-indicator-dot'),

    valWbStatus: document.getElementById('val-wb-status'),
    tagWbAge: document.getElementById('tag-wb-age'),
    dotWb: document.querySelector('#status-wristband .status-indicator-dot'),

    valBleStatus: document.getElementById('val-ble-status'),
    tagBleCount: document.getElementById('tag-ble-count'),
    dotBle: document.querySelector('#status-local-ble .status-indicator-dot'),

    valTelemetryStats: document.getElementById('val-telemetry-stats'),
    footerStatus: document.getElementById('footer-status-text'),

    // Tuning Controls
    chkOverrideN: document.getElementById('chk-override-n'),
    sliderOverrideN: document.getElementById('slider-override-n'),
    sliderNDisplay: document.getElementById('slider-n-display'),
    valNOverride: document.getElementById('val-n-override'),

    // Terminal Panel
    terminalPanel: document.getElementById('terminal-panel'),
    terminalOutput: document.getElementById('terminal-output'),
    btnToggleTerminal: document.getElementById('btn-toggle-terminal'),
    btnClearTerminal: document.getElementById('btn-clear-terminal'),
    btnCloseTerminal: document.getElementById('btn-close-terminal')
  };

  /* -------------------------------------------------------------------------- */
  /* INITIALIZATION & EVENT LISTENERS                                           */
  /* -------------------------------------------------------------------------- */
  function init() {
    setupUnitToggle();
    setupSerialEvents();
    setupBluetoothEvents();
    setupSimulationEvents();
    setupTuningEvents();
    setupTerminalEvents();

    // Start background UI refresh loop for freshness tickers & watchdog
    setInterval(updateFreshnessUI, 500);
    appendTerminal('# [LOG] Application core loaded. Select an action above to start.', 'term-dim');
  }

  /* -------------------------------------------------------------------------- */
  /* 1. DYNAMIC DISTANCE DISPLAY UNIT (m <-> cm)                                */
  /* -------------------------------------------------------------------------- */
  function setupUnitToggle() {
    dom.btnUnitM.addEventListener('click', () => setDistanceUnit('m'));
    dom.btnUnitCm.addEventListener('click', () => setDistanceUnit('cm'));
  }

  function setDistanceUnit(unit) {
    if (state.distanceUnit === unit) return;
    state.distanceUnit = unit;

    dom.btnUnitM.classList.toggle('active', unit === 'm');
    dom.btnUnitCm.classList.toggle('active', unit === 'cm');

    appendTerminal(`# [LOG] Display distance unit changed to: [${unit.toUpperCase()}]`, 'term-log');

    // Dynamically re-render all node cards immediately with current data
    for (let id = 1; id <= 5; id++) {
      renderNodeCard(id);
    }
  }

  /**
   * Converts and formats a distance in meters to the user-selected display unit.
   * Handles clamping (<0.15m floor and >8.0m ceiling).
   */
  function formatDistanceValue(dist_m) {
    if (dist_m === null || dist_m === undefined || isNaN(dist_m) || dist_m < 0) {
      return { text: '---', unit: state.distanceUnit, isOutOfRange: false };
    }

    // Operational Bounds Clamping: >= 8.00 m is OUT_OF_RANGE
    if (dist_m >= DISTANCE_MAX_M) {
      const maxText = state.distanceUnit === 'm' ? '> 8.0' : '> 800';
      return { text: maxText, unit: state.distanceUnit, isOutOfRange: true };
    }

    const clamped_m = Math.max(DISTANCE_MIN_M, dist_m);

    if (state.distanceUnit === 'cm') {
      const cmVal = Math.round(clamped_m * 100);
      return { text: cmVal.toString(), unit: 'cm', isOutOfRange: false };
    } else {
      return { text: clamped_m.toFixed(2), unit: 'm', isOutOfRange: false };
    }
  }

  /* -------------------------------------------------------------------------- */
  /* 2. WEB SERIAL ENGINE (CENTRAL HUB LINK)                                    */
  /* -------------------------------------------------------------------------- */
  function setupSerialEvents() {
    if (!('serial' in navigator)) {
      appendTerminal('# [WARN] Web Serial API is NOT supported in this browser. Please use Chrome or Edge.', 'term-warn');
      dom.btnConnectHub.disabled = true;
      dom.btnConnectHub.title = 'Web Serial API unsupported in this browser';
      return;
    }

    dom.btnConnectHub.addEventListener('click', toggleSerialConnection);
    navigator.serial.addEventListener('disconnect', handleSerialHardwareDisconnect);
  }

  async function toggleSerialConnection() {
    if (state.serial.isConnected) {
      await disconnectSerial();
    } else {
      await connectSerial();
    }
  }

  async function connectSerial() {
    if (state.isSimulating) {
      exitSimulationMode();
    }

    try {
      appendTerminal('# [LOG] Requesting USB Serial Port (115,200 baud)...', 'term-log');
      const port = await navigator.serial.requestPort();
      await port.open({ baudRate: 115200 });

      state.serial.port = port;
      state.serial.isConnected = true;
      state.serial.lastRxTime = Date.now();

      dom.btnConnectHub.classList.add('connected');
      dom.btnConnectHub.querySelector('.btn-text').textContent = 'Disconnect Hub';
      dom.valHubStatus.textContent = 'CONNECTED (ONLINE)';
      dom.dotHub.className = 'status-indicator-dot dot-online';
      dom.tagHubPort.textContent = 'USB COM PORT';
      dom.footerStatus.textContent = 'Streaming live telemetry from Central Hub over USB Serial';

      appendTerminal('# [LOG] USB Serial Port opened successfully @ 115,200 baud.', 'term-log');

      // Start Watchdog
      startSerialWatchdog();

      // Start Stream Reader with custom LineBreakTransformer
      readSerialStream(port);
    } catch (err) {
      appendTerminal(`# [ERROR] Failed to open USB Serial Port: ${err.message}`, 'term-error');
      await disconnectSerial();
    }
  }

  async function disconnectSerial() {
    state.serial.isConnected = false;
    clearInterval(state.serial.watchdogTimer);

    if (state.serial.reader) {
      try {
        await state.serial.reader.cancel();
      } catch (_) {}
      state.serial.reader = null;
    }

    if (state.serial.port) {
      try {
        await state.serial.port.close();
      } catch (_) {}
      state.serial.port = null;
    }

    dom.btnConnectHub.classList.remove('connected');
    dom.btnConnectHub.querySelector('.btn-text').textContent = 'Connect Hub (USB Serial)';
    dom.valHubStatus.textContent = 'DISCONNECTED';
    dom.dotHub.className = 'status-indicator-dot dot-offline';
    dom.tagHubPort.textContent = 'NO PORT';
    dom.valWbStatus.textContent = 'WAITING FOR HUB';
    dom.dotWb.className = 'status-indicator-dot dot-offline';

    appendTerminal('# [LOG] USB Serial Port disconnected.', 'term-dim');
  }

  function handleSerialHardwareDisconnect() {
    appendTerminal('# [WARN] USB Cable disconnected unexpectedly!', 'term-error');
    disconnectSerial();
  }

  function startSerialWatchdog() {
    clearInterval(state.serial.watchdogTimer);
    state.serial.watchdogTimer = setInterval(() => {
      if (!state.serial.isConnected) return;
      const elapsed = Date.now() - state.serial.lastRxTime;
      if (elapsed > 2000) {
        dom.valHubStatus.textContent = 'STALLED / NO DATA';
        dom.dotHub.className = 'status-indicator-dot dot-stale';
      }
    }, 1000);
  }

  /**
   * Custom TransformStream that buffers raw chunks and yields complete newline-delimited lines.
   */
  class LineBreakTransformer {
    constructor() {
      this.container = '';
    }
    transform(chunk, controller) {
      this.container += chunk;
      const lines = this.container.split(/\r?\n/);
      this.container = lines.pop(); // Keep incomplete tail
      for (const line of lines) {
        controller.enqueue(line);
      }
    }
    flush(controller) {
      if (this.container) {
        controller.enqueue(this.container);
      }
    }
  }

  async function readSerialStream(port) {
    const textDecoder = new TextDecoderStream();
    port.readable.pipeTo(textDecoder.writable);
    const lineStream = textDecoder.readable.pipeThrough(new TransformStream(new LineBreakTransformer()));
    const reader = lineStream.getReader();
    state.serial.reader = reader;

    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (value) {
          processIncomingSerialLine(value.trim());
        }
      }
    } catch (err) {
      if (state.serial.isConnected) {
        appendTerminal(`# [ERROR] Serial stream read error: ${err.message}`, 'term-error');
      }
    } finally {
      reader.releaseLock();
    }
  }

  /**
   * Smart Line Router:
   *   - Routes '#' lines directly to Diagnostic Console
   *   - Routes '{' lines directly to NDJSON parser
   */
  function processIncomingSerialLine(line) {
    if (!line) return;
    state.serial.lastRxTime = Date.now();

    // 1. Diagnostic / Log Message
    if (line.startsWith('#')) {
      let styleClass = 'term-log';
      if (line.includes('[WARN]')) styleClass = 'term-warn';
      if (line.includes('[ERROR]')) styleClass = 'term-error';
      appendTerminal(line, styleClass);
      return;
    }

    // 2. Telemetry JSON Line
    if (line.startsWith('{')) {
      try {
        const telemetry = JSON.parse(line);
        handleHubTelemetry(telemetry);
        state.serial.stats.validFrames++;
        updateTelemetryStats();
      } catch (err) {
        state.serial.stats.corruptedLines++;
        appendTerminal(`# [WARN] Malformed JSON received: ${line.substring(0, 50)}...`, 'term-warn');
      }
    }
  }

  function handleHubTelemetry(data) {
    if (data.v !== 1 || !Array.isArray(data.nodes)) return;

    // Hub Status
    dom.valHubStatus.textContent = data.hub_status || 'ONLINE';
    dom.dotHub.className = 'status-indicator-dot dot-online';

    // Wristband Status
    if (data.wb) {
      state.wristband.id = data.wb.id || 1;
      state.wristband.status = data.wb.status || 'ONLINE';
      state.wristband.age_ms = data.wb.age_ms || 0;
      state.wristband.seq = data.wb.seq || 0;

      if (state.wristband.status === 'ONLINE') {
        dom.valWbStatus.textContent = `ONLINE (WRISTBAND #${state.wristband.id})`;
        dom.dotWb.className = 'status-indicator-dot dot-online';
        dom.tagWbAge.textContent = `AGE: ${state.wristband.age_ms} ms`;
      } else {
        dom.valWbStatus.textContent = 'OFFLINE / OUT OF RANGE';
        dom.dotWb.className = 'status-indicator-dot dot-offline';
        dom.tagWbAge.textContent = `LOST: ${state.wristband.age_ms} ms`;
      }
    }

    // Update Node Telemetry (Wristband Perspective)
    data.nodes.forEach(node => {
      const id = node.id;
      if (!state.nodes[id]) return;

      const nData = state.nodes[id].wb;
      nData.dist_m = (node.dist_m !== undefined && node.dist_m !== null) ? node.dist_m : null;
      nData.rssi = node.rssi !== undefined ? node.rssi : null;
      nData.state = node.state || 'OFFLINE';
      nData.refA = node.refA || -59;
      nData.n = node.n || 2.2;
      nData.lastSeen = Date.now();

      renderNodeCard(id);
    });
  }

  function updateTelemetryStats() {
    const stats = state.serial.stats;
    stats.seq++;
    stats.hzCount++;

    const now = Date.now();
    if (now - stats.lastHzTime >= 1000) {
      stats.currentHz = (stats.hzCount * 1000 / (now - stats.lastHzTime)).toFixed(1);
      stats.hzCount = 0;
      stats.lastHzTime = now;
    }

    dom.valTelemetryStats.textContent = `SEQ: ${stats.seq} • ${stats.currentHz} Hz • ERR: ${stats.corruptedLines}`;
  }

  /* -------------------------------------------------------------------------- */
  /* 3. WEB BLUETOOTH ENGINE (INDEPENDENT DIRECT NODE SCAN)                     */
  /* -------------------------------------------------------------------------- */
  function setupBluetoothEvents() {
    if (!('bluetooth' in navigator)) {
      dom.btnScanBle.disabled = true;
      dom.btnScanBle.title = 'Web Bluetooth API unsupported in this browser';
      return;
    }

    dom.btnScanBle.addEventListener('click', toggleBluetoothScan);
  }

  async function toggleBluetoothScan() {
    if (state.bluetooth.isScanning) {
      stopBluetoothScan();
    } else {
      await startBluetoothScan();
    }
  }

  async function startBluetoothScan() {
    try {
      appendTerminal('# [LOG] Requesting Web Bluetooth LE Advertisement Scan...', 'term-log');

      // Check if navigator.bluetooth.requestLEScan is supported
      if ('requestLEScan' in navigator.bluetooth) {
        const scan = await navigator.bluetooth.requestLEScan({
          acceptAllAdvertisements: true,
          keepRepeatedDevices: true
        });

        state.bluetooth.scan = scan;
        state.bluetooth.isScanning = true;

        navigator.bluetooth.addEventListener('advertisementreceived', handleBluetoothAdvertisement);

        dom.btnScanBle.classList.add('scanning');
        dom.btnScanBle.querySelector('.btn-text').textContent = 'Stop BLE Scan';
        dom.valBleStatus.textContent = 'SCANNING (ONLINE)';
        dom.dotBle.className = 'status-indicator-dot dot-online';

        appendTerminal('# [LOG] Web Bluetooth continuous passive scan active.', 'term-log');
      } else {
        // Fallback for browsers with standard requestDevice
        appendTerminal('# [WARN] requestLEScan not supported. Opening standard Bluetooth picker...', 'term-warn');
        const device = await navigator.bluetooth.requestDevice({
          acceptAllDevices: true,
          optionalServices: []
        });

        appendTerminal(`# [LOG] Paired with Bluetooth device: ${device.name || device.id}`, 'term-log');
        dom.valBleStatus.textContent = 'DEVICE PAIRED';
        dom.dotBle.className = 'status-indicator-dot dot-online';
      }
    } catch (err) {
      appendTerminal(`# [ERROR] Web Bluetooth Scan failed: ${err.message}`, 'term-error');
      stopBluetoothScan();
    }
  }

  function stopBluetoothScan() {
    if (state.bluetooth.scan && state.bluetooth.scan.stop) {
      state.bluetooth.scan.stop();
    }
    state.bluetooth.isScanning = false;
    state.bluetooth.scan = null;

    dom.btnScanBle.classList.remove('scanning');
    dom.btnScanBle.querySelector('.btn-text').textContent = 'Scan Nodes (Web BLE)';
    dom.valBleStatus.textContent = 'OFFLINE';
    dom.dotBle.className = 'status-indicator-dot dot-offline';

    appendTerminal('# [LOG] Web Bluetooth Scan stopped.', 'term-dim');
  }

  function handleBluetoothAdvertisement(event) {
    if (!event.manufacturerData) return;

    // Look for SHAPNEST Protocol ID (0x534E)
    if (!event.manufacturerData.has(PROTOCOL_ID)) return;

    const dataView = event.manufacturerData.get(PROTOCOL_ID);
    if (dataView.byteLength < 5) return;

    const frameType = dataView.getUint8(0);
    if (frameType !== FRAME_TYPE_NODE_BEACON) return;

    const nodeId = dataView.getUint8(1);
    const refA = dataView.getInt8(2);
    const rawN = dataView.getUint8(3);
    const nodeN = rawN / 10.0;
    const rssi = event.rssi;

    if (!state.nodes[nodeId]) return;

    state.bluetooth.nodesSeen.add(nodeId);
    dom.tagBleCount.textContent = `${state.bluetooth.nodesSeen.size} NODES SEEN`;

    // Calculate Distance using Log-Distance Model
    const effectiveN = state.nOverrideEnabled ? state.nOverrideValue : nodeN;
    const calculatedDist_m = Math.pow(10, (refA - rssi) / (10 * effectiveN));

    const bleData = state.nodes[nodeId].ble;
    bleData.dist_m = calculatedDist_m;
    bleData.rssi = rssi;
    bleData.refA = refA;
    bleData.n = nodeN;
    bleData.pkts++;
    bleData.lastSeen = Date.now();

    renderNodeCard(nodeId);
  }

  /* -------------------------------------------------------------------------- */
  /* 4. ENVIRONMENTAL PATH-LOSS EXPONENT OVERRIDE (n)                          */
  /* -------------------------------------------------------------------------- */
  function setupTuningEvents() {
    dom.chkOverrideN.addEventListener('change', (e) => {
      state.nOverrideEnabled = e.target.checked;
      dom.sliderOverrideN.disabled = !state.nOverrideEnabled;

      if (state.nOverrideEnabled) {
        state.nOverrideValue = parseFloat(dom.sliderOverrideN.value);
        dom.valNOverride.textContent = `ACTIVE (Override n = ${state.nOverrideValue.toFixed(1)})`;
        dom.valNOverride.style.color = 'var(--color-cyan)';
      } else {
        dom.valNOverride.textContent = 'INACTIVE (Using Node-Broadcast Default)';
        dom.valNOverride.style.color = 'var(--text-muted)';
      }

      // Re-render
      for (let id = 1; id <= 3; id++) renderNodeCard(id);
    });

    dom.sliderOverrideN.addEventListener('input', (e) => {
      state.nOverrideValue = parseFloat(e.target.value);
      dom.sliderNDisplay.textContent = state.nOverrideValue.toFixed(1);
      dom.valNOverride.textContent = `ACTIVE (Override n = ${state.nOverrideValue.toFixed(1)})`;

      for (let id = 1; id <= 3; id++) renderNodeCard(id);
    });
  }

  /* -------------------------------------------------------------------------- */
  /* 5. EXPLICIT OFFLINE VIRTUAL SIMULATOR                                      */
  /* -------------------------------------------------------------------------- */
  function setupSimulationEvents() {
    dom.btnToggleSim.addEventListener('click', () => {
      if (state.isSimulating) {
        exitSimulationMode();
      } else {
        startSimulationMode();
      }
    });

    dom.btnExitSim.addEventListener('click', exitSimulationMode);
  }

  function startSimulationMode() {
    if (state.serial.isConnected) {
      disconnectSerial();
    }
    if (state.bluetooth.isScanning) {
      stopBluetoothScan();
    }

    state.isSimulating = true;
    dom.simBanner.classList.remove('hidden');
    dom.btnToggleSim.classList.add('active-sim');
    dom.btnToggleSim.querySelector('.btn-text').textContent = 'Stop Demo Sim';
    dom.valHubStatus.textContent = 'SIMULATED HUB';
    dom.dotHub.className = 'status-indicator-dot dot-stale';
    dom.valWbStatus.textContent = 'SIMULATED WRISTBAND';
    dom.dotWb.className = 'status-indicator-dot dot-stale';
    dom.valBleStatus.textContent = 'SIMULATED BROWSER BLE';
    dom.dotBle.className = 'status-indicator-dot dot-stale';

    appendTerminal('⚠️ [WARN] DEMO / SIMULATION MODE ACTIVATED — All measurements are synthetic!', 'term-warn');

    // 2D Spatial positions of the 3 nodes in a virtual room
    const nodeCoords = {
      1: { x: 1.0, y: 1.0 }, // Fan
      2: { x: 5.0, y: 1.5 }, // Iron
      3: { x: 3.0, y: 5.0 }  // Door
    };

    state.simTimer = setInterval(() => {
      state.simAngle += 0.08;

      // Virtual child moves in a smooth figure around room
      const childX = 3.0 + 1.8 * Math.cos(state.simAngle);
      const childY = 2.8 + 1.5 * Math.sin(state.simAngle * 1.5);

      const simTelemetry = {
        v: 1,
        hub_status: 'SIMULATED',
        seq: state.serial.stats.seq + 1,
        wb: {
          id: 1,
          status: 'ONLINE',
          age_ms: 50,
          seq: (state.serial.stats.seq + 1) % 256
        },
        nodes: []
      };

      for (let id = 1; id <= 3; id++) {
        const nPos = nodeCoords[id];
        const trueDist = Math.sqrt(Math.pow(childX - nPos.x, 2) + Math.pow(childY - nPos.y, 2));

        // Add realistic Gaussian multipath noise (+-0.2m)
        const noisyDist = Math.max(DISTANCE_MIN_M, trueDist + (Math.random() - 0.5) * 0.25);
        const refA = -59;
        const n = 2.2;
        const noisyRssi = Math.round(refA - 10 * n * Math.log10(noisyDist) + (Math.random() - 0.5) * 3);

        simTelemetry.nodes.push({
          id: id,
          dist_m: parseFloat(noisyDist.toFixed(2)),
          rssi: noisyRssi,
          state: 'ACTIVE',
          refA: refA,
          n: n
        });

        // Also update direct BLE perspective with slight phone offset
        const bleData = state.nodes[id].ble;
        bleData.dist_m = parseFloat((noisyDist + 0.1).toFixed(2));
        bleData.rssi = noisyRssi - 2;
        bleData.pkts++;
        bleData.lastSeen = Date.now();
      }

      handleHubTelemetry(simTelemetry);
      updateTelemetryStats();
    }, 1000);
  }

  function exitSimulationMode() {
    if (!state.isSimulating) return;

    state.isSimulating = false;
    clearInterval(state.simTimer);
    state.simTimer = null;

    dom.simBanner.classList.add('hidden');
    dom.btnToggleSim.classList.remove('active-sim');
    dom.btnToggleSim.querySelector('.btn-text').textContent = 'Run Demo Sim';

    dom.valHubStatus.textContent = 'DISCONNECTED';
    dom.dotHub.className = 'status-indicator-dot dot-offline';
    dom.valWbStatus.textContent = 'WAITING FOR HUB';
    dom.dotWb.className = 'status-indicator-dot dot-offline';
    dom.valBleStatus.textContent = 'OFFLINE';
    dom.dotBle.className = 'status-indicator-dot dot-offline';

    // Clear synthetic data
    for (let id = 1; id <= 3; id++) {
      state.nodes[id].wb.dist_m = null;
      state.nodes[id].wb.rssi = null;
      state.nodes[id].wb.state = 'OFFLINE';
      state.nodes[id].ble.dist_m = null;
      state.nodes[id].ble.rssi = null;
      renderNodeCard(id);
    }

    appendTerminal('# [LOG] Exited Demo Simulation Mode. Ready for physical hardware.', 'term-dim');
  }

  /* -------------------------------------------------------------------------- */
  /* 6. CARD RENDERING & FRESHNESS TIMERS                                       */
  /* -------------------------------------------------------------------------- */
  function renderNodeCard(id) {
    const card = document.getElementById(`card-node-${id}`);
    const pill = document.getElementById(`pill-node-${id}`);
    if (!card || !pill) return;

    const n = state.nodes[id];
    const wb = n.wb;
    const ble = n.ble;

    const formattedWb = formatDistanceValue(wb.dist_m);

    // 1. Update State Pill
    pill.className = 'node-state-pill';
    if (wb.state === 'OFFLINE' || wb.dist_m === null) {
      pill.classList.add('pill-offline');
      pill.textContent = 'OFFLINE';
      card.className = 'node-card card-offline';
    } else if (formattedWb.isOutOfRange || wb.state === 'OUT_OF_RANGE') {
      pill.classList.add('pill-out-of-range');
      pill.textContent = 'OUT OF RANGE';
      card.className = 'node-card card-stale';
    } else if (wb.state === 'STALE') {
      pill.classList.add('pill-stale');
      pill.textContent = 'STALE';
      card.className = 'node-card card-stale';
    } else {
      pill.classList.add('pill-active');
      pill.textContent = 'ACTIVE';
      card.className = 'node-card card-active';
    }

    // 2. Render Wristband Perspective (via Hub)
    const wbHero = document.getElementById(`wb-dist-${id}`);
    const wbUnit = document.getElementById(`wb-unit-${id}`);
    const wbBar = document.getElementById(`wb-bar-${id}`);
    const wbRssi = document.getElementById(`wb-rssi-${id}`);
    const wbRef = document.getElementById(`wb-ref-${id}`);
    const wbN = document.getElementById(`wb-n-${id}`);

    wbHero.textContent = formattedWb.text;
    wbUnit.textContent = formattedWb.unit;
    wbHero.classList.toggle('out-of-range', formattedWb.isOutOfRange);

    if (wb.dist_m !== null && wb.dist_m >= 0) {
      // Invert progress: closer distance = higher bar percentage
      const pct = Math.max(0, Math.min(100, Math.round(((DISTANCE_MAX_M - wb.dist_m) / (DISTANCE_MAX_M - DISTANCE_MIN_M)) * 100)));
      wbBar.style.width = `${pct}%`;

      wbBar.className = 'progress-bar';
      if (wb.dist_m <= 1.0) wbBar.classList.add('bar-close');
      else if (wb.dist_m <= 2.5) wbBar.classList.add('bar-mid');
      else if (wb.dist_m <= DISTANCE_MAX_M) wbBar.classList.add('bar-far');
      else wbBar.classList.add('bar-out');
    } else {
      wbBar.style.width = '0%';
      wbBar.className = 'progress-bar';
    }

    wbRssi.textContent = wb.rssi !== null ? `${wb.rssi} dBm` : '-- dBm';
    wbRef.textContent = wb.refA !== null ? `${wb.refA} dBm` : '-- dBm';
    wbN.textContent = wb.n !== null ? wb.n.toFixed(1) : '--';

    // 3. Render Direct BLE Perspective
    const bleHero = document.getElementById(`ble-dist-${id}`);
    const bleUnit = document.getElementById(`ble-unit-${id}`);
    const bleBar = document.getElementById(`ble-bar-${id}`);
    const bleRssi = document.getElementById(`ble-rssi-${id}`);
    const blePkts = document.getElementById(`ble-pkts-${id}`);

    const formattedBle = formatDistanceValue(ble.dist_m);
    bleHero.textContent = formattedBle.text;
    bleUnit.textContent = formattedBle.unit;
    bleHero.classList.toggle('out-of-range', formattedBle.isOutOfRange);

    if (ble.dist_m !== null && ble.dist_m >= 0) {
      const pctBle = Math.max(0, Math.min(100, Math.round(((DISTANCE_MAX_M - ble.dist_m) / (DISTANCE_MAX_M - DISTANCE_MIN_M)) * 100)));
      bleBar.style.width = `${pctBle}%`;
    } else {
      bleBar.style.width = '0%';
    }

    bleRssi.textContent = ble.rssi !== null ? `${ble.rssi} dBm` : '-- dBm';
    blePkts.textContent = ble.pkts.toString();
  }

  function updateFreshnessUI() {
    const now = Date.now();

    for (let id = 1; id <= 3; id++) {
      const wbFreshness = document.getElementById(`wb-freshness-${id}`);
      const bleFreshness = document.getElementById(`ble-freshness-${id}`);

      const wbLast = state.nodes[id].wb.lastSeen;
      const bleLast = state.nodes[id].ble.lastSeen;

      if (wbFreshness) {
        if (wbLast > 0) {
          const delta = now - wbLast;
          wbFreshness.textContent = delta < 1000 ? `${delta}ms` : `${(delta / 1000).toFixed(1)}s`;
        } else {
          wbFreshness.textContent = '--';
        }
      }

      if (bleFreshness) {
        if (bleLast > 0) {
          const deltaBle = now - bleLast;
          bleFreshness.textContent = deltaBle < 1000 ? `${deltaBle}ms` : `${(deltaBle / 1000).toFixed(1)}s`;
        } else {
          bleFreshness.textContent = '--';
        }
      }
    }
  }

  /* -------------------------------------------------------------------------- */
  /* 7. DIAGNOSTIC TERMINAL LOGGING                                             */
  /* -------------------------------------------------------------------------- */
  function setupTerminalEvents() {
    dom.btnToggleTerminal.addEventListener('click', () => {
      dom.terminalPanel.classList.toggle('hidden');
    });

    dom.btnCloseTerminal.addEventListener('click', () => {
      dom.terminalPanel.classList.add('hidden');
    });

    dom.btnClearTerminal.addEventListener('click', () => {
      dom.terminalOutput.innerHTML = '';
      appendTerminal('# [LOG] Terminal cleared.', 'term-dim');
    });
  }

  function appendTerminal(text, styleClass = 'term-log') {
    const line = document.createElement('div');
    line.className = `term-line ${styleClass}`;
    line.textContent = text;

    dom.terminalOutput.prepend(line); // Prepends so newest is at the top/bottom depending on flex

    // Keep buffer capped at 100 lines
    while (dom.terminalOutput.children.length > 100) {
      dom.terminalOutput.removeChild(dom.terminalOutput.lastChild);
    }
  }

  // Bootstrap when DOM ready
  document.addEventListener('DOMContentLoaded', init);

})();
