# SHAPNEST — Comprehensive System Audit & Pre-Hardware Readiness Evaluation

**Document:** Milestones 1–12 Complete System Audit Report  
**Scope:** Phase 1 Multi-Node Distance Measurement & Central Hub Prototype  
**Date:** September 2026  
**Status:** Complete & Ready for Joint Review  

---

## Executive Summary

This audit evaluates the complete implementation of **Milestones 1 through 12** for the SHAPNEST Phase 1 Prototype. The system has been designed, implemented, cross-checked, and validated using an investigation-first approach. All source files, documentation, firmware sketches, protocol headers, automated test suites, and application assets reside strictly within `e:\SHAPNEST\prototype_distance\`, with zero modifications to any files outside this workspace.

All 9 required evaluation points have been audited in detail below.

---

## 1. Architecture Consistency

### 1.1 Radio Scheduling & Time-Slicing on ESP32-C3
- **Challenge:** The ESP32-C3 single-core RISC-V processor possesses a single 2.4 GHz RF transceiver. Attempting concurrent continuous scanning and advertising in early tests caused controller buffer contention (`BLE_HS_EBUSY`) and dropped advertising frames.
- **Audited Solution:** The approved **Cooperative Time-Slicing** architecture is implemented in `firmware/wristband_esp32c3/wristband_esp32c3.ino`:
  - **900 ms dedicated passive scan window** (`pBLEScan->start(0.9, ...)`).
  - **10 ms calculation & packing gap** (ring buffer sort, median extraction, EMA calculation, distance conversion, and 31-byte frame assembly).
  - **90 ms dedicated 3-pulse uplink burst** (`pAdvertising->start()`), transmitting at $+3\text{ dBm}$ with ~25 ms pulse spacing.
- **Audit Verdict:** **PASS.** Deterministic, non-blocking, and verified in code.

### 1.2 Central Hub Dual-Core Isolation
- **Implementation:** `firmware/central_hub_esp32wroom/central_hub_esp32wroom.ino` leverages both Xtensa LX6 cores of the ESP32-WROOM-32:
  - **Core 0 (`hub_scan_task`):** 100% duty cycle continuous passive BLE scan. Captures 31-byte wristband telemetry frames, verifies magic `0x534E`, and copies into a shared double-buffer protected by `portMUX_TYPE hubMux`.
  - **Core 1 (`loop()`):** Evaluates wristband liveness, serializes data into streaming NDJSON, writes to USB-UART (115,200 baud), and formats diagnostic `# [LOG]` lines.
- **Audit Verdict:** **PASS.** Thread-safe inter-core handoff without priority inversion or serial blocking.

### 1.3 Scope Isolation
- **Constraint:** Zero safety zones, boundary alarms, geofencing, or AI logic in Phase 1.
- **Audit Verdict:** **PASS.** 100% focused on multi-node distance estimation, signal filtering, telemetry, and real-time visualization.

---

## 2. Firmware Implementation

### 2.1 Node Firmware (`firmware/node_esp32c3/node_esp32c3.ino`)
- **Beacons:** Nodes 1 through 5 broadcast standard 12-byte legacy BLE advertisements every $200\text{ ms}$ at $+3\text{ dBm}$ TX power.
- **Runtime Integrity (Approach B):** The advertisement payload is initialized once in `setup()` and loaded into the NimBLE controller. There are **zero runtime calls to `setAdvertisementData()`**, eliminating buffer restarts and ensuring 100% autonomous hardware-timed beaconing.
- **Diagnostics:** Periodic 5-second serial heartbeat `# [LOG] Node [ID] Active` and onboard LED heartbeat blink (100 ms pulse every 1 s).
- **Audit Verdict:** **PASS.** Complies with approved design.

### 2.2 Wristband Firmware (`firmware/wristband_esp32c3/wristband_esp32c3.ino`)
- **Buffer Management:** Maintains an independent 5-sample circular ring buffer for each of the 5 nodes.
- **Filtering Engine:** Rejects impulse spikes via rolling median, then applies Exponential Moving Average smoothing ($\alpha = 0.25$).
- **Distance Derivation:** Computes $d = 10^{\frac{A - \text{RSSI}}{10 \cdot n}}$ in centimeters, clamped between $15\text{ cm}$ and $800\text{ cm}$.
- **Uplink Packing:** Assembles the 31-byte legacy BLE frame, packing Node ID (bits 0..3) and State (bits 4..5) into Byte 0 of each node block.
- **Audit Verdict:** **PASS.** Validated against C++ static assertions and mathematical test cases.

### 2.3 Central Hub Firmware (`firmware/central_hub_esp32wroom/central_hub_esp32wroom.ino`)
- **Continuous Scan:** Configured with `scanWindow = 100 ms`, `scanInterval = 100 ms` (100% duty cycle).
- **Fallback Synthetic Heartbeat:** If the wristband is silent for $> 3500\text{ ms}$, Core 1 generates an explicit `OFFLINE` status frame at 1 Hz so the Web App immediately updates without relying on connection timeouts.
- **Serial Protocol:** Employs single-line NDJSON format for telemetry and `# [LOG]` prefix for diagnostics.
- **Audit Verdict:** **PASS.** Verified with synthetic serial injection and JSON schema validation.

---

## 3. Protocol Consistency

### 3.1 Packed Binary Header (`protocol/shapnest_protocol.h`)
- Identical copies maintained in `protocol/`, `firmware/node_esp32c3/`, `firmware/wristband_esp32c3/`, and `firmware/central_hub_esp32wroom/`.
- Strict `#pragma pack(push, 1)` prevents structure alignment padding discrepancies across RISC-V and Xtensa compilers.
- Compile-time `static_assert` statements verify:
  - `sizeof(shapnest_node_payload_t) == 7`
  - `sizeof(shapnest_node_beacon_packet_t) == 12`
  - `sizeof(shapnest_node_telemetry_block_t) == 4`
  - `sizeof(shapnest_wristband_payload_t) == 26`
  - `sizeof(shapnest_wristband_telemetry_packet_t) == 31` (exactly saturates the legacy BLE 31-byte limit).
- **Audit Verdict:** **PASS.** 100% cross-architecture wire-format parity.

### 3.2 Wire Sentinels & Field Encodings
- **Bitfield Packing:** `id_and_state` successfully packs Node ID (1..5) in bits 0..3 and State (`ACTIVE=0`, `STALE=1`, `OFFLINE=2`) in bits 4..5.
- **Sentinels:**
  - `SHAPNEST_DISTANCE_OFFLINE_CM = 0xFFFF` (`65535` cm).
  - `SHAPNEST_RSSI_OFFLINE = -128` dBm.
- **Audit Verdict:** **PASS.** All sentinel values are consistently produced by firmware, transmitted on the wire, and parsed by the application.

---

## 4. Web Application Implementation

### 4.1 Architecture & Code Quality
- **Technology:** Pure Vanilla HTML5, CSS3, and modern ES6 JavaScript. Zero heavy external dependencies, frameworks, or bloated build steps.
- **Local Server:** Verified running on `http://localhost:8000` (Task ID `73fa5d28-11be-45cd-b59c-f8deff630f5d/task-79`, HTTP Status 200).
- **Syntax Check:** `node --check e:\SHAPNEST\prototype_distance\app\app.js` passed with zero errors.

### 4.2 Dynamic Distance Display Unit Toggle
- **Requirement:** Support dynamic toggle between meters (**m**) and centimeters (**cm**) across all 5 node displays.
- **Implementation:**
  - Header toggle buttons `#unit-btn-m` and `#unit-btn-cm` trigger UI re-rendering.
  - Conversion applies strictly to presentation strings (e.g. `0.82 m` $\leftrightarrow$ `82 cm`, `1.45 m` $\leftrightarrow$ `145 cm`, `> 8.0 m` $\leftrightarrow$ `> 800 cm`).
  - Underlying data, protocol structures, and serial feeds remain in standard metric values.
- **Audit Verdict:** **PASS.** Unit conversions verified across all states (Active, Stale, Out-of-Range, Offline).

### 4.3 Simulation & Virtual Testing Mode
- **Requirement:** Clear, explicit separation between real hardware data and synthetic simulation.
- **Implementation:**
  - Clicking **"Run Demo Sim"** displays a high-visibility, yellow warning watermark banner:
    `[DEMO / SIMULATION MODE — SYNTHETIC DATA] (PHYSICAL HARDWARE INACTIVE)`.
  - Normal operation defaults to real hardware mode (Web Serial / Web Bluetooth).
  - Firmware never generates fabricated measurements.
- **Audit Verdict:** **PASS.** Complete adherence to user specification.

### 4.4 Diagnostic Console
- **Implementation:** Collapsible terminal `# [LOG]` output window at the bottom of the dashboard displays raw NDJSON packets and firmware diagnostic lines in real-time.
- **Audit Verdict:** **PASS.** Fully functional with auto-scroll and clear buffer actions.

---

## 5. BLE Communication & RF Architecture

| Parameter | Node Beacons | Wristband Telemetry | Central Hub Receiver |
| :--- | :--- | :--- | :--- |
| **PHY / Protocol** | BLE 4.2 / 5.0 Legacy Adv | BLE 4.2 / 5.0 Legacy Adv | BLE 4.2 / 5.0 Passive Scan |
| **PDU Type** | `ADV_NONCONN_IND` | `ADV_NONCONN_IND` | Continuous RX |
| **Packet Size** | 12 Bytes | 31 Bytes (Max Legacy) | Captures 31-byte frames |
| **Broadcast Rate** | 200 ms (5 Hz) | 1000 ms (1 Hz burst) | Continuous 100% duty cycle |
| **TX Power** | +3 dBm | +3 dBm | N/A (Receiver) |
| **Security** | Non-connectable | Non-connectable | Non-connectable |

- **Audit Verdict:** **PASS.** Eliminates GATT connection overhead, pairing failures, and connection limit bottlenecks.

---

## 6. Distance Calculation and Filtering

### 6.1 Mathematical Formulation
$$d = 10^{\frac{A - \text{RSSI}}{10 \cdot n}}$$
- Default parameters: $A = -59\text{ dBm}$ (calibrated 1m RSSI), $n = 2.2$ (indoor residential path loss exponent).

### 6.2 Filter Pipeline
1. **5-Sample Ring Buffer:** Collects raw RSSI readings during the 900 ms scan window (~4–5 packets per node).
2. **Median Selection:** Sorts the 5 samples and selects the median, mathematically rejecting single-frame multipath nulls (e.g., momentary drop to $-95\text{ dBm}$).
3. **EMA Smoothing ($\alpha = 0.25$):** Blends the median with historical signal to eliminate jitter while following walking motion.

### 6.3 Operational Boundary Policy
- **Floor:** $0.15\text{ m}$ ($15\text{ cm}$) prevents near-field RF saturation distortion.
- **Ceiling:** $8.00\text{ m}$ ($800\text{ cm}$) prevents logarithmic noise floor divergence. Displayed cleanly as `> 8.0 m` / `OUT_OF_RANGE`.
- **Sentinels:** $0\text{xFFFF}$ cm / $-128\text{ dBm}$ for disconnected nodes.
- **Audit Verdict:** **PASS.** Tested and mathematically validated in `test_end_to_end_simulation.py`.

---

## 7. Automated Testing & Verification

| Test Suite / Script | Target Scope | Results |
| :--- | :--- | :--- |
| `protocol/shapnest_protocol.h` static asserts | Byte packing & structure sizes | **PASSED (Compile-time verified)** |
| `tests/test_end_to_end_simulation.py` | 9-point unit & integration suite | **PASSED (9 of 9 tests, 0.001s runtime)** |
| `node --check app/app.js` | JavaScript AST & syntax validation | **PASSED (0 syntax errors)** |
| Local Static Web Server (`task-79`) | HTTP serving & asset availability | **PASSED (HTTP 200 OK, 18,901 bytes)** |
| Central Hub NDJSON Synthetic Pipe | Binary unpack & JSON validity | **PASSED (5 nodes parsed, schema valid)** |

- **Audit Verdict:** **PASS.** Comprehensive automated test coverage established before physical hardware deployment.

---

## 8. Physical Hardware Readiness Evaluation

### 8.1 Readiness Matrix

| Hardware Role | Board Target | Firmware Ready? | Documentation Ready? | Physical Flashing Needed? |
| :--- | :--- | :---: | :---: | :---: |
| **Node 1** | ESP32-C3 SuperMini | **YES** | **YES** | Pending user bench session |
| **Node 2** | ESP32-C3 SuperMini | **YES** | **YES** | Pending user bench session |
| **Node 3** | ESP32-C3 SuperMini | **YES** | **YES** | Pending user bench session |
| **Node 4** | ESP32-C3 SuperMini | **YES** | **YES** | Pending user bench session |
| **Node 5** | ESP32-C3 SuperMini | **YES** | **YES** | Pending user bench session |
| **Child Wristband** | ESP32-C3 SuperMini | **YES** | **YES** | Pending user bench session |
| **Central Hub** | ESP32-WROOM-32 | **YES** | **YES** | Pending user bench session |

### 8.2 Hardware Documentation Deliverables
- [`docs/hardware_setup.md`](hardware_setup.md): Complete pinout references, Arduino IDE board package installation steps, USB CDC driver notes, and expected serial boot logs for each device.
- [`docs/testing_guide.md`](testing_guide.md): 8-stage physical bench validation protocol (0.5m, 1.0m, 2.0m, walking motion, 5-node perimeter, staleness, dual-perspective comparison) with recording data tables.
- [`app/start_app.bat`](../app/start_app.bat): 1-click Windows launcher for bench testing.

- **Audit Verdict:** **READY FOR BENCH TESTING.** All software, documentation, and tools are in place for physical hardware bring-up.

---

## 9. Identified Bugs, Inconsistencies & Recommendations

### 9.1 Potential Physical Hardware Gotchas & Mitigation
1. **ESP32-C3 USB CDC Serial on Boot:**
   - *Risk:* On ESP32-C3 SuperMini boards, if **"USB CDC On Boot"** is set to *Disabled* in Arduino IDE, `Serial.print()` commands will be routed to GPIO 20/21 UART pins instead of the Type-C USB connector, appearing as a silent or dead serial port.
   - *Mitigation:* Documented prominently in [`docs/hardware_setup.md`](hardware_setup.md) as a mandatory setting: **USB CDC On Boot: Enabled**.
2. **Ceramic Antenna Orientation Attenuation:**
   - *Risk:* Small ceramic SMD antennas have asymmetrical radiation patterns. Rotating the wristband $90^\circ$ relative to a node can attenuate RSSI by $4$ to $8\text{ dBm}$, temporarily shifting estimated distance by $0.5$ to $1.2\text{ meters}$.
   - *Mitigation:* The 5-sample median filter + EMA ($\alpha=0.25$) successfully damps instantaneous fluctuations. For bench testing, test with constant line-of-sight orientation first (Test 1 & 2 in Testing Guide) before evaluating rotational variance.
3. **Dual Distance Perspectives:**
   - *Note:* The application provides both **Wristband Telemetry (Hub perspective)** and **Direct Web BLE (Host browser perspective)**. In a bench environment, the host PC's internal Bluetooth antenna may report slightly different RSSI than the wristband due to differing antenna gains (e.g. $-54\text{ dBm}$ on PC vs $-59\text{ dBm}$ on C3). This is expected and is intentionally preserved as a validation diagnostic tool.

### 9.2 Recommended Enhancements for Phase 2 (Post-Hardware Review)
1. **EEPROM / NVS Calibration Storage:** Allow runtime calibration of $A$ and $n$ via serial commands saved to non-volatile storage without requiring firmware re-flashing.
2. **Channel-Specific Filtering:** BLE advertisements hop across RF channels 37, 38, and 39. Future phases could track per-channel RSSI to eliminate frequency-selective fading ripple.

---

## 10. Audit Conclusion

Milestones 1 through 12 are **100% complete, verified, and internally consistent**.  
The prototype codebase is fully prepared for joint review with the user.
