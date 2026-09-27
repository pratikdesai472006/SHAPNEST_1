# SHAPNEST — Phase 1: Interactive Multi-Node Distance Measurement & Central Hub Prototype

A real-time, multi-node Bluetooth Low Energy (BLE) proximity and distance estimation prototype for child tracking. The system measures distances between an ESP32-C3 child wristband and five ESP32-C3 spatial anchor nodes, transmits aggregated 31-byte telemetry to an ESP32-WROOM Central Hub, and displays live multi-node distances on a modern web application over USB Serial (115,200 baud).

```
+-----------------------------------------------------------------------------------+
|                            SHAPNEST PHASE 1 ARCHITECTURE                          |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  [Node 1] (0.82m) ---\                                                            |
|  [Node 2] (1.45m) ----\                                                           |
|  [Node 3] (2.10m) -----+--> [Child Wristband]                                     |
|  [Node 4] (3.80m) ----/      (ESP32-C3 Mini)                                      |
|  [Node 5] (8.00m) ---/       - 900 ms Dedicated Scan                              |
|                              - 5-Sample Median + EMA (alpha=0.25)                 |
|                              - 31-byte Telemetry Uplink (1 Hz)                    |
|                                       |                                           |
|                                       v (BLE Broadcast)                           |
|                             [Central Hub]                                         |
|                              (ESP32-WROOM-32)                                     |
|                              - Core 0: 100% Continuous BLE Passive Scan           |
|                              - Core 1: NDJSON Serializer (115,200 baud)           |
|                                       |                                           |
|                                       v (USB Serial)                              |
|                            [Web Display Application]                              |
|                             (Vanilla HTML5/CSS3/ES6)                              |
|                             - Real-time 5-Node Radar Dashboard                    |
|                             - Dynamic Units Toggle (m <-> cm)                     |
|                             - Virtual Simulator [DEMO MODE]                       |
|                             - Diagnostic Console (# [LOG])                        |
+-----------------------------------------------------------------------------------+
```

---

## 1. Directory Structure

```
prototype_distance/
├── app/                                # Web Display Application
│   ├── index.html                      # Semantic HTML5 UI with Glassmorphic Dashboard
│   ├── styles.css                      # Modern CSS design tokens, animations, themes
│   ├── app.js                          # Web Serial / Web Bluetooth engine & UI logic
│   └── start_app.bat                   # Desktop Windows 1-click launcher
├── docs/                               # Technical Specifications & Guides
│   ├── architecture.md                 # System Architecture & Time-Slicing Spec
│   ├── distance_model.md               # RF Propagation Physics & Filter Derivation
│   ├── ble_protocol.md                 # Binary Wire Formats & NDJSON Schema Spec
│   ├── hardware_setup.md               # Pinouts, Flashing & Board Configuration Guide
│   ├── testing_guide.md                # 8-Stage Physical Bench Testing Protocol
│   └── audit_report.md                 # Comprehensive Milestones 1–12 System Audit
├── firmware/                           # Embedded C++ Arduino / ESP-IDF Firmware
│   ├── node_esp32c3/                   # ESP32-C3 Autonomous Beacon Anchor Firmware
│   │   ├── node_esp32c3.ino
│   │   └── shapnest_protocol.h
│   ├── wristband_esp32c3/              # ESP32-C3 Child Wristband Scanner & Uplink
│   │   ├── wristband_esp32c3.ino
│   │   └── shapnest_protocol.h
│   └── central_hub_esp32wroom/         # ESP32-WROOM Dual-Core Central Receiver
│       ├── central_hub_esp32wroom.ino
│       └── shapnest_protocol.h
├── protocol/                           # Shared Master Protocol Definition
│   └── shapnest_protocol.h             # Master Byte-Packed C/C++ Header
├── tests/                              # Automated Validation Test Suites
│   └── test_end_to_end_simulation.py   # Python End-to-End Simulation & Protocol Tests
└── README.md                           # Master Project Documentation
```

---

## 2. Hardware Bill of Materials (BOM)

| Role | Board Model | Processor | Qty | Power Supply | Antenna |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **Nodes 1–5** | ESP32-C3 SuperMini | 32-bit RISC-V @ 160 MHz | 5 | USB 5V / 3.7V LiPo | Onboard Ceramic SMD |
| **Child Wristband** | ESP32-C3 SuperMini | 32-bit RISC-V @ 160 MHz | 1 | 3.7V 300–500mAh LiPo | Onboard Ceramic SMD |
| **Central Hub** | ESP32-WROOM-32 (NodeMCU) | Dual-Core Xtensa LX6 @ 240 MHz | 1 | USB Type-C to Host PC | Inverted-F PCB Trace |

---

## 3. Quickstart: Running the Web Application

### Option A: Windows 1-Click Launcher
Double-click `prototype_distance/app/start_app.bat`.  
This automatically starts a local static server on `http://localhost:8000` and launches your default browser.

### Option B: Manual Command Line
```powershell
cd e:\SHAPNEST\prototype_distance\app
python -m http.server 8000
# Open Google Chrome or Microsoft Edge to: http://localhost:8000
```

### Application Features
- **USB Serial Connection:** Click **"CONNECT SERIAL (HUB)"** and select the ESP32-WROOM COM port to receive real hardware telemetry.
- **Direct Web Bluetooth (Bench Validation):** Click **"SCAN DIRECT BLE (DEBUG)"** to directly scan nearby nodes from the browser.
- **Dynamic Distance Unit Toggle:** Click the **`m`** or **`cm`** button in the header. All 5 distance readouts and ranges instantly switch format (e.g. `0.82 m` $\leftrightarrow$ `82 cm`) without affecting internal calculations.
- **Virtual Simulation Mode:** Click **"DEMO SIMULATION"** to run a synthetic 5-node walking simulation with a clear `[DEMO / SIMULATION MODE — SYNTHETIC DATA]` indicator banner.
- **Diagnostic Console:** Click **"DIAGNOSTIC LOGS"** at the bottom to view real-time `# [LOG]` output and raw NDJSON lines.

---

## 4. Firmware Flashing Guide

Detailed flashing guides, Arduino IDE board package settings, and silkscreen pinouts are in [`docs/hardware_setup.md`](docs/hardware_setup.md).

### 4.1 Flashing Nodes 1–5 (ESP32-C3)
1. Open `firmware/node_esp32c3/node_esp32c3.ino`.
2. Configure `NODE_ID` (1 to 5) for each individual board:
   ```cpp
   #define NODE_ID 1 // Change to 2, 3, 4, 5 for respective nodes
   ```
3. Board: **ESP32C3 Dev Module**
   - Flash Mode: `QIO`, Flash Size: `4MB`
   - USB CDC On Boot: `Enabled` (for serial diagnostics)
4. Upload to each of the 5 node boards.

### 4.2 Flashing Child Wristband (ESP32-C3)
1. Open `firmware/wristband_esp32c3/wristband_esp32c3.ino`.
2. Board: **ESP32C3 Dev Module**
   - USB CDC On Boot: `Enabled`
3. Upload to the wristband board. The wristband immediately begins its 1000 ms cooperative cycle (900 ms scan $\rightarrow$ 10 ms math $\rightarrow$ 90 ms uplink burst).

### 4.3 Flashing Central Hub (ESP32-WROOM-32)
1. Open `firmware/central_hub_esp32wroom/central_hub_esp32wroom.ino`.
2. Board: **ESP32 Dev Module**
   - Upload Speed: `921600`
   - CPU Frequency: `240MHz (WiFi/BT)`
3. Upload to the Central Hub board. Connect the Hub to the host PC via USB.

---

## 5. Automated Verification & Testing

To run the automated integration test suite:
```powershell
python e:\SHAPNEST\prototype_distance\tests\test_end_to_end_simulation.py
```

### Verified Test Cases (100% Pass)
1. `test_node_beacon_packet_layout`: Validates exact 12-byte packed Node structure.
2. `test_wristband_telemetry_packet_layout`: Validates exact 31-byte legacy BLE PDU saturation.
3. `test_id_and_state_bitfield_packing`: Validates bitfield macros for ID (bits 0..3) and State (bits 4..5).
4. `test_median_filter_impulse_rejection`: Validates impulse noise rejection of 5-sample ring buffer.
5. `test_ema_smoothing_convergence`: Validates exponential moving average smoothing ($\alpha=0.25$).
6. `test_log_distance_calculation`: Validates inverted Log-Distance path-loss formula.
7. `test_operational_bounds_clamping`: Validates 0.15 m floor, 8.00 m ceiling, and OFFLINE sentinels.
8. `test_end_to_end_packet_to_ndjson`: Validates complete Hub RX $\rightarrow$ Unpack $\rightarrow$ NDJSON serialization.
9. `test_dynamic_unit_conversion_display_logic`: Validates dynamic presentation toggle (`m` $\leftrightarrow$ `cm`).

---

## 6. Milestones 1–12 Status Matrix

| Milestone | Description | Deliverables | Status |
| :---: | :--- | :--- | :---: |
| **M1** | Master Protocol Specification & Packed Header | `protocol/shapnest_protocol.h` | **COMPLETED & VERIFIED** |
| **M2** | Configurable ESP32-C3 Node Firmware | `firmware/node_esp32c3/` | **COMPLETED & VERIFIED** |
| **M3** | Standalone Web Display Application | `app/index.html`, `styles.css`, `app.js` | **COMPLETED & VERIFIED** |
| **M4** | ESP32-WROOM Central Hub Firmware | `firmware/central_hub_esp32wroom/` | **COMPLETED & VERIFIED** |
| **M5** | Child Wristband Firmware | `firmware/wristband_esp32c3/` | **COMPLETED & VERIFIED** |
| **M6** | Hardware Setup & Flashing Documentation | `docs/hardware_setup.md` | **COMPLETED & VERIFIED** |
| **M7** | Physical Bench Validation Protocol | `docs/testing_guide.md` | **COMPLETED & VERIFIED** |
| **M8** | System Architecture & Distance Modeling Spec | `docs/architecture.md`, `docs/distance_model.md`| **COMPLETED & VERIFIED** |
| **M9** | BLE Protocol & Data Flow Specification | `docs/ble_protocol.md` | **COMPLETED & VERIFIED** |
| **M10**| Automated Integration & Simulation Testing | `tests/test_end_to_end_simulation.py` | **COMPLETED & VERIFIED** |
| **M11**| Deployment Package & Desktop Launcher | `app/start_app.bat`, `README.md` | **COMPLETED & VERIFIED** |
| **M12**| Comprehensive System Audit & Pre-Hardware Readiness | `docs/audit_report.md` | **IN PROGRESS (FINAL)** |
