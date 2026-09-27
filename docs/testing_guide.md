# SHAPNEST — Physical Bench Validation Protocol
## Phase 1 Multi-Node Distance Measurement & Accuracy Testing

This document establishes the step-by-step physical test protocol for validating distance accuracy, RF stability, filtering performance, and multi-node tracking on real ESP32 hardware.

In strict adherence to **Section 1.10 and 22** of the project specification:
* Never claim physical validation without an actual hardware test.
* Record true physical tape-measure ground truth versus raw RSSI and estimated distance.
* Follow the progressive test sequence: single node static tests first, then dynamic motion, then multi-node scalability.

---

## 1. Test Equipment & Environment Setup

### 1.1 Required Equipment
1. **5 $\times$ Configured ESP32-C3 Nodes** (labeled `NODE_01` to `NODE_05`).
2. **1 $\times$ ESP32-C3 Child Wristband** (labeled `WRISTBAND_01`).
3. **1 $\times$ ESP32-WROOM Central Hub** connected via USB to PC.
4. **Physical Tape Measure** (at least 5.0 meters length).
5. **Masking Tape or Floor Markers** (to mark exact 0.5 m, 1.0 m, 1.5 m, 2.0 m, 3.0 m, 5.0 m positions).
6. **Host PC** running the SHAPNEST Web Application in Google Chrome or Microsoft Edge.

### 1.2 Physical Environment Guidelines
* **Location:** A clear indoor room (living room, hallway, or lab space) with at least 5 meters of open line-of-sight.
* **Elevation:** Mount or place the nodes on non-metallic surfaces (wooden tables, cardboard boxes, or wall tape) at approximately **1.0 meter above the floor** (typical child torso/wrist height).
* **RF Interference:** Keep at least 2 meters away from high-power 2.4 GHz Wi-Fi routers and microwave ovens during baseline testing.

---

## 2. Progressive Validation Test Matrix

```text
TEST 1: Single Node Static Baseline @ 0.5 m
   │
TEST 2: Single Node Reference Calibration @ 1.0 m
   │
TEST 3: Single Node Static Distance @ 2.0 m
   │
TEST 4: Static Distance Curve Profiling (0.3m, 0.75m, 1.5m, 3.0m, 5.0m)
   │
TEST 5: Dynamic Approaching & Receding Motion (Child walking at 0.8 m/s)
   │
TEST 6: Multi-Node Perimeter Deployment (All 5 Nodes Active Concurrently)
   │
TEST 7: Disappearance & Reappearance Staleness State Machine
   │
TEST 8: Dual-Perspective Comparison (Wristband vs. Direct Phone Web Bluetooth)
```

---

## 3. Detailed Test Protocols

### TEST 1: Single Node Static Baseline @ 0.5 m
* **Objective:** Verify close-proximity distance estimation and stability.
* **Procedure:**
  1. Power ON `NODE_01` only (keep Nodes 2–5 powered OFF).
  2. Measure exactly **0.50 meters** with the physical tape measure.
  3. Place `WRISTBAND_01` at the 0.50 m mark, stationary, oriented with the antenna facing the node.
  4. Connect the Central Hub to the Web App via USB Serial.
  5. Observe the distance display for **30 seconds** (30 updates).
* **Data Recording:**

| Parameter | Target Ground Truth | Measured / Observed |
| :--- | :--- | :--- |
| **Physical Distance** | 0.50 m | 0.50 m |
| **Filtered RSSI** | ~ -52 to -55 dBm | _______ dBm |
| **Estimated Distance**| 0.50 m | _______ m |
| **Absolute Error** | $\le 0.15\text{ m}$ | _______ m |
| **Stability** | No rapid jumping ($< \pm 0.10\text{ m}$) | PASS / FAIL |

---

### TEST 2: Single Node Reference Calibration @ 1.0 m (Crucial Baseline)
* **Objective:** Verify the factory reference RSSI ($A$) at exactly 1.0 meter.
* **Procedure:**
  1. Place `WRISTBAND_01` at exactly **1.00 meter** line-of-sight from `NODE_01`.
  2. Observe the raw and filtered RSSI reported in the Web App and Serial Monitor.
  3. If the filtered RSSI averages, for example, $-61\text{ dBm}$ (while node defaults to $-59\text{ dBm}$), note the $2\text{ dB}$ offset.
  4. If needed, update `#define CALIBRATED_RSSI_1M -61` on Node 1 for fine bench calibration.

---

### TEST 3: Single Node Static Distance @ 2.0 m
* **Objective:** Verify mid-range attenuation and path-loss exponent ($n$).
* **Procedure:**
  1. Move `WRISTBAND_01` to exactly **2.00 meters** from `NODE_01`.
  2. Observe the estimated distance.
  3. If estimated distance reads $2.6\text{ m}$ (over-estimated) or $1.5\text{ m}$ (under-estimated):
     * Use the Web App's **`Override n` slider** to test $n = 2.0$, $2.2$, $2.4$.
     * Find the optimal empirical $n$ that produces exactly $2.00\text{ m}$.

---

### TEST 4: Dynamic Motion Testing (Child Approaching & Receding)
* **Objective:** Verify that the 5-sample median filter and EMA ($\alpha = 0.25$) react smoothly to real human movement without lagging or freezing.
* **Procedure:**
  1. Start at a distance of **4.0 meters** from `NODE_01`.
  2. Walk smoothly toward the node at normal walking speed (~$0.8\text{ m/s}$) until reaching $0.5\text{ m}$.
  3. Pause for 5 seconds.
  4. Walk smoothly backwards to $4.0\text{ m}$.
* **Pass Criteria:**
  * Distance display updates continuously at 1 Hz with smooth monotonic transitions.
  * No visual freezing, dropped frames, or sudden backward jumps.
  * Proximity bar shifts dynamically from yellow $\rightarrow$ blue $\rightarrow$ green.

---

### TEST 5: Multi-Node Perimeter Deployment (All 5 Nodes Active)
* **Objective:** Verify concurrent tracking of 5 physical nodes without packet collisions or display crosstalk.
* **Procedure:**
  1. Power ON all 5 physical nodes.
  2. Arrange them in a room perimeter or star configuration:
     * `NODE_01`: Kitchen entrance (~1.2 m)
     * `NODE_02`: Living room table (~2.4 m)
     * `NODE_03`: Front door (~3.8 m)
     * `NODE_04`: Hallway (~0.8 m)
     * `NODE_05`: Study corner (~4.5 m)
  3. Power ON `WRISTBAND_01` at the center of the room.
  4. Verify the Web Application:
     * **All 5 node cards** must display separate, independent distance measurements.
     * All 5 progress bars must reflect their individual relative proximities simultaneously.
     * Sequence counter on the status bar must advance continuously at ~1.0 Hz with zero serial parse errors.

---

### TEST 6: Disappearance & Reappearance Staleness State Machine
* **Objective:** Verify `ACTIVE` $\rightarrow$ `STALE` $\rightarrow$ `OFFLINE` $\rightarrow$ `ACTIVE` transitions.
* **Procedure:**
  1. With all 5 nodes actively displaying distances, abruptly remove power from **`NODE_03`** (unplug USB).
  2. Observe `NODE_03` card on the Web App:
     * **At $t = 0\text{ s}$:** State is `ACTIVE`.
     * **At $t = 1.2\text{ s}$:** State badge transitions to amber **`STALE`** (distance is held).
     * **At $t = 3.5\text{ s}$:** State badge transitions to gray **`OFFLINE`** (distance becomes `---`).
     * *Crucial check:* Verify that Nodes 1, 2, 4, and 5 continue updating normally without any delay or interruption!
  3. Restore power to `NODE_03`.
  4. *Verify:* Within 2 seconds, `NODE_03` re-engages and transitions directly back to bright green **`ACTIVE`** with fresh measurements!

---

### TEST 7: Dual-Perspective Validation (Wristband vs. Direct Phone BLE)
* **Objective:** Compare the child wristband's distance estimation against the phone/browser's independent direct BLE observation.
* **Procedure:**
  1. Hold the host smartphone or laptop running the Web App directly adjacent to `WRISTBAND_01` (within 10 cm of the wristband).
  2. In the Web App header, click **`[Scan Nodes (Web BLE)]`**.
  3. Observe the side-by-side columns on the cards:
     * Left Column: **🧒 WRISTBAND (VIA HUB)**
     * Right Column: **📱 DIRECT BROWSER BLE**
  4. Compare the readings:
     * Because the phone is physically located next to the wristband, both columns should measure within $\pm 0.3\text{ m}$ of each other.
     * If they differ significantly, check whether the phone's Bluetooth antenna has a different sensitivity than the ESP32-C3 Mini.

---

## 4. Master Physical Validation Results Table Template

| Test ID | Condition | Ground Truth (m) | Raw RSSI (dBm) | Filtered RSSI (dBm) | Measured Dist (m) | Abs Error (m) | % Error | Status |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **T1.1** | Node 1 Line-of-Sight | 0.50 m | | | | | | |
| **T1.2** | Node 1 Line-of-Sight | 1.00 m | | | | | | |
| **T1.3** | Node 1 Line-of-Sight | 2.00 m | | | | | | |
| **T1.4** | Node 1 Line-of-Sight | 3.00 m | | | | | | |
| **T1.5** | Node 1 Line-of-Sight | 5.00 m | | | | | | |
| **T2.1** | Node 2 Line-of-Sight | 1.00 m | | | | | | |
| **T3.1** | Node 3 Line-of-Sight | 1.00 m | | | | | | |
| **T4.1** | Node 4 Line-of-Sight | 1.00 m | | | | | | |
| **T5.1** | Node 5 Line-of-Sight | 1.00 m | | | | | | |
| **T6.1** | Body Shadowing (Child Torso between Node & Wristband) | 1.00 m | | | | | | |
| **T7.1** | Out-of-Range ($> 8.0\text{ m}$) | > 8.00 m | | | `> 8.0 m` | N/A | N/A | |
