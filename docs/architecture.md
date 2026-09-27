# SHAPNEST — System Architecture Specification (Phase 1)

**Component:** System Architecture, Topology & Hardware Integration  
**Scope:** Phase 1 Multi-Node Distance Measurement & Central Hub Prototype  
**Author:** AI Pair Programmer & System Architect  
**Status:** Approved & Implemented  

---

## 1. System Overview & Architectural Purpose

The **SHAPNEST Phase 1 Prototype** is a localized, real-time wireless telemetry system designed to measure and monitor physical distances between a mobile child wristband and five fixed spatial anchor nodes. 

```
                                      +---------------------------------------------+
                                      |          Modern Web Display Application     |
                                      |   (Chrome / Edge / Opera via Web Serial)    |
                                      +---------------------------------------------+
                                                             ^
                                                             | USB Serial (115,200 baud)
                                                             | Streaming NDJSON
                                                             v
+-----------------------+             +---------------------------------------------+
|    ESP32-C3 Nodes     |             |       ESP32-WROOM-32 Central Hub            |
|   (Anchors 1 to 5)    |             |  Core 0: Continuous 100% Passive BLE Scan   |
|  200 ms Adv Interval  |             |  Core 1: NDJSON Formatter & UART Bridge     |
+-----------------------+             +---------------------------------------------+
            \                                                ^
             \ BLE Advertisements (2.4 GHz)                  | BLE Telemetry Uplink (2.4 GHz)
              \ Legacy Non-Connectable                       | Packed 31-byte PDU @ 1 Hz
               v                                             |
       +-------------------------------------------------------------+
       |               ESP32-C3 Child Wristband                      |
       |  900 ms Passive Scan -> 10 ms Math -> 90 ms Uplink Burst    |
       |  5-Sample Rolling Median Filter + EMA Smoothing (alpha=0.25)|
       +-------------------------------------------------------------+
```

### Key Architectural Boundaries
1. **Isolated Prototype Scope:** The Phase 1 prototype is strictly focused on **multi-node distance measurement, signal filtering, and real-time visualization**. Alarms, boundary fences, geofencing, hazard detection, parent notifications, and AI reasoning are explicitly deferred to subsequent phases.
2. **Physical Measurement Separation:** Distance calculations are performed at the edge on the mobile wristband using localized RSSI measurements. The Central Hub serves as an aggregation receiver and serial bridge, passing data to the Web Application without modifying the physical distance estimates.
3. **Dual Distance Perspectives:**
   - **Wristband / Hub Perspective (Primary):** Distances calculated by the child's wristband from node beacons, uplinked via telemetry to the Hub, and displayed in real-time.
   - **Direct BLE Perspective (Bench Validation):** Distances independently calculated by the host browser/PC using Web Bluetooth directly sniffing the node beacons for cross-comparison.

---

## 2. Hardware Topology & Hardware Specifications

| Component | Target Hardware | Core Architecture | RF & Antenna | Primary Role |
| :--- | :--- | :--- | :--- | :--- |
| **Nodes 1–5** | ESP32-C3 SuperMini | 32-bit RISC-V @ 160 MHz, 400 KB SRAM | 2.4 GHz BLE 5.0, Ceramic SMD antenna | Autonomous beacon broadcast (+3 dBm TX, 200 ms interval) |
| **Child Wristband** | ESP32-C3 SuperMini | 32-bit RISC-V @ 160 MHz, 400 KB SRAM | 2.4 GHz BLE 5.0, Ceramic SMD antenna | Multi-node scanner, RSSI filter, distance calculator & uplink |
| **Central Hub** | ESP32-WROOM-32 | Dual-Core 32-bit Xtensa LX6 @ 240 MHz, 520 KB SRAM | 2.4 GHz BLE 4.2/5.0, Inverted-F PCB trace antenna | Dedicated 100% duty-cycle receiver, NDJSON serial bridge |
| **Display Client** | Host PC / Tablet | x86_64 / ARM Browser Engine | Web Serial API (USB-UART CH340/CP2102) | Real-time 5-node radar UI, dynamic units, diagnostic logging |

---

## 3. Radio Scheduling & Cooperative Time-Slicing

### 3.1 Single-Radio Constraint on ESP32-C3
The ESP32-C3 features a single 2.4 GHz radio transceiver shared between Wi-Fi and Bluetooth subsystems. When operating in BLE mode, the radio can either be listening (RX/Scan) or transmitting (TX/Advertise), but cannot execute simultaneous full-duplex operation.

In early testing with uncoordinated multi-role scanning and advertising under high duty cycles, the underlying NimBLE stack frequently encountered controller buffer contention (`BLE_HS_EBUSY` / buffer exhaustion) and missed node advertisements.

### 3.2 The 1-Second Cooperative Time-Slice Schedule
To guarantee deterministic execution, zero buffer crashes, and predictable power consumption, the wristband firmware implements a strict **1000 ms cooperative cycle**:

```
+-------------------------------------------------------------+-------+--------------------+
|                900 ms Scanning Window                       | 10 ms |   90 ms Uplink     |
|                (Dedicated BLE Passive Scan)                 | Math  |  (3-Pulse Burst)   |
+-------------------------------------------------------------+-------+--------------------+
0 ms                                                        900 ms  910 ms               1000 ms
```

1. **Window 1: Continuous Passive Scan (0 ms – 900 ms):**
   - NimBLE passive scan enabled (`SCAN_WINDOW = 900 ms`, `SCAN_INTERVAL = 900 ms`).
   - Receives beacons from Nodes 1–5. Each node broadcasts every 200 ms (with ±10 ms BLE random backoff), yielding ~4 to 5 received packets per node per cycle.
   - Advertisements arriving outside company ID `0x534E` are discarded in the fast callback.
2. **Gap: Calculation & Packing (900 ms – 910 ms):**
   - Scan stopped via `pBLEScan->stop()`.
   - Ring buffers update: 5-sample rolling median is extracted for each node.
   - Exponential Moving Average (EMA, $\alpha = 0.25$) is updated.
   - Log-Distance path-loss formula computes distance in centimeters.
   - Operational clamping applied (0.15 m floor, 8.00 m ceiling).
   - 31-byte telemetry frame is assembled and loaded into the advertiser payload.
3. **Window 2: Dedicated Uplink Burst (910 ms – 1000 ms):**
   - Non-connectable advertising started (`pAdvertising->start()`).
   - Radio transmits a rapid 3-pulse burst (spaced ~25 ms apart) to ensure the Central Hub intercepts the telemetry frame even in noisy multi-path RF environments.
   - Advertising explicitly stopped at $t = 1000\text{ ms}$, freeing the radio for the next 900 ms scan window.

---

## 4. Central Hub Dual-Core Architecture

The ESP32-WROOM-32 Central Hub leverages its dual Xtensa LX6 processor cores to completely isolate high-speed RF capture from blocking serial communications:

```
[Core 0: RF Processing Core]                      [Core 1: System & I/O Core]
+---------------------------------------+         +---------------------------------------+
|  NimBLE Passive Scan Callback         |         |  Arduino main loop()                  |
|  - Continuous scan (100% duty cycle)  |         |  - Evaluates wristband freshness      |
|  - Matches Protocol ID 0x534E         |         |  - Formats streaming NDJSON           |
|  - Validates frame type 0x02 (Uplink) |         |  - Writes to Serial (115,200 baud)    |
|  - Copies 26B payload into buffer     |         |  - Formats diagnostic # [LOG] lines   |
+---------------------------------------+         +---------------------------------------+
                   |                                                 ^
                   |         portMUX_TYPE spinlock buffer            |
                   +-------------------------------------------------+
```

### 4.1 Core 0 Responsibilities
- Executes the NimBLE receiver task at high priority.
- Configured with `scanWindow = 100 ms`, `scanInterval = 100 ms` (100% duty cycle continuous reception).
- Parses the 31-byte raw packet, checks manufacturer AD header `0xFF`, company ID `0x534E`, and frame type `0x02`.
- Acquires `portENTER_CRITICAL(&hubMux)` and copies the fresh payload into a shared buffer, updating the `last_uplink_rx_ms` timestamp.

### 4.2 Core 1 Responsibilities
- Runs the standard Arduino `loop()` at normal priority.
- Checks if a new telemetry frame has been staged; if yes, unpacks the 5 node blocks (Node ID, State, Distance, RSSI).
- Serializes the telemetry into a compact, single-line **Newline-Delimited JSON (NDJSON)** string and flushes it over UART.
- Maintains a 1 Hz fallback heartbeat: if the wristband fails to transmit for > 3500 ms, Core 1 generates a synthetic `OFFLINE` status frame so the Web App immediately updates without waiting for serial timeouts.

---

## 5. Data Freshness State Machine

To prevent stale or dropped packets from showing lingering readings, every node in the system transitions through three discrete liveness states based on millisecond elapsed time since last packet reception:

```
               Fresh packet (< 1200 ms)
       +---------------------------------------+
       |                                       |
       v                                       |
+--------------+   t >= 1200 ms   +--------------+   t >= 3500 ms   +---------------+
|    ACTIVE    | ---------------> |    STALE     | ---------------> |    OFFLINE    |
| (Green Pill) |                  | (Amber Pill) |                  |  (Gray Pill)  |
+--------------+ <--------------- +--------------+                  +---------------+
       ^               Fresh packet (< 3500 ms)                             |
       |                                                                    |
       +--------------------------------------------------------------------+
                          Fresh packet received after silence
```

### State Definitions
1. **ACTIVE (Code `0b00` = 0):**
   - Packet received within the last $1200\text{ ms}$ (representing at least 1 packet received in the previous cooperative cycle).
   - Distance and RSSI readings are actively updated and displayed with high visual confidence.
2. **STALE (Code `0b01` = 1):**
   - No packet received for $1200\text{ ms} \le t < 3500\text{ ms}$ (missed 1–2 consecutive scan cycles).
   - The system preserves the last known distance and RSSI for continuity, but the UI displays an amber warning pill indicating signal degradation or body shadowing.
3. **OFFLINE (Code `0b10` = 2):**
   - No packet received for $t \ge 3500\text{ ms}$ (missed 3+ consecutive scan cycles).
   - Node is declared lost or out of range. Distance is set to sentinel `0xFFFF` (`65535` cm), RSSI is set to `-128 dBm`, and the UI displays an inactive gray card.

---

## 6. Dynamic Distance Display Unit Presentation Architecture

The system supports seamless switching between **meters (m)** and **centimeters (cm)** to accommodate different physical evaluation scenarios.

### 6.1 Architectural Decoupling Rule
- **Firmware & Protocol Invariance:** The binary BLE protocol, packed structs, telemetry buffers, and internal distance calculations are **strictly immutable** and always stored and transmitted as **integer centimeters (`uint16_t`)**.
- **Serial Transmission Invariance:** Central Hub serial NDJSON output transmits distances in standard **floating-point meters** (`"distance": 1.45`), with centimeters explicitly provided or trivially derived.
- **Presentation-Only Conversion:** The UI Unit Selector (`m` vs `cm`) acts solely as a presentation filter in `app.js`. Toggling the switch instantly updates all card readouts, progress labels, and diagnostic gauges across all 5 nodes without triggering recalculations or network traffic.

```
+----------------------------------------------------+
|  Wristband Firmware: Distance = 145 cm (uint16_t)  |
+----------------------------------------------------+
                          |
                          v (BLE 31-byte packed packet)
+----------------------------------------------------+
|  Central Hub Serial NDJSON: "distance": 1.45       |
+----------------------------------------------------+
                          |
                          v (USB Serial Web API)
+----------------------------------------------------+
|  Web Application Presentation Layer                |
|  - Mode "m":  "1.45 m"                             |
|  - Mode "cm": "145 cm"                             |
+----------------------------------------------------+
```

---

## 7. Security, RF Immunity & Boundary Architecture

1. **Non-Connectable Broadcasts (`ADV_NONCONN_IND`):**
   - Node beacons and wristband uplink packets are strictly non-connectable.
   - Devices do not accept pairing, bonding, or GATT connection requests, eliminating BLE stack connection saturation attacks and unauthorized profile inspections.
2. **Proprietary Protocol Filtering:**
   - Packets are identified by the custom 16-bit Company Identifier `0x534E` ('S', 'N') and validated against `SHAPNEST_PROTOCOL_VERSION 0x01`.
   - Stray commercial beacons (e.g., iBeacon, Eddystone, Tile, AirTags) are discarded in the earliest packet classification branch with near-zero CPU overhead.
3. **CRC & BLE Physical Integrity:**
   - Standard BLE physical layer 24-bit CRC checks ensure corrupted packets are dropped by hardware before reaching the application buffer.
