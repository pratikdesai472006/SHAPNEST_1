# SHAPNEST — Hardware Setup & Flashing Documentation
## Phase 1 Multi-Node Distance Measurement Prototype

This document provides complete, unambiguous, step-by-step instructions for configuring, flashing, and verifying the physical ESP32 hardware for the SHAPNEST Phase 1 prototype.

---

## 1. Physical Hardware Target Specifications

| Device Role | Hardware Module | CPU Architecture | Flash / RAM | Typical On-Board USB |
| :--- | :--- | :--- | :--- | :--- |
| **Nodes (5 units)** | ESP32-C3 Mini / SuperMini | 32-bit Single-Core RISC-V @ 160 MHz | 4 MB Flash / 400 KB SRAM | Native USB-JTAG/CDC |
| **Child Wristband (1 unit)** | ESP32-C3 Mini / SuperMini | 32-bit Single-Core RISC-V @ 160 MHz | 4 MB Flash / 400 KB SRAM | Native USB-JTAG/CDC |
| **Central Hub (1 unit)** | ESP32-WROOM-32 / 32D / 32U | 32-bit Dual-Core Xtensa LX6 @ 240 MHz | 4 MB Flash / 520 KB SRAM | CP2102 or CH340 USB-UART |

---

## 2. Arduino IDE Environment Setup

### 2.1 Supported Arduino IDE Versions
* **Arduino IDE 2.x (Recommended):** Version 2.2.1 or newer.
* **Arduino IDE 1.8.x (Legacy):** Version 1.8.19 or newer.

### 2.2 Install the ESP32 Board Package
1. Open Arduino IDE.
2. Navigate to **File $\rightarrow$ Preferences**.
3. Locate the **Additional Boards Manager URLs** field and paste:
   ```text
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
4. Click **OK**.
5. Navigate to **Tools $\rightarrow$ Board $\rightarrow$ Boards Manager...**.
6. Search for `esp32` by **Espressif Systems**.
7. Install version **2.0.14 or newer** (compatible with ESP32 Core v2.x and v3.x).

### 2.3 Install the Required BLE Library
All sketches use **`NimBLE-Arduino`** by h2zero for ultra-lightweight, non-blocking BLE operations.
1. In Arduino IDE, navigate to **Tools $\rightarrow$ Manage Libraries...** (or click the Library icon in the left toolbar).
2. In the search box, type:
   ```text
   NimBLE-Arduino
   ```
3. Locate **NimBLE-Arduino by h2zero**.
4. Click **Install** (Version 1.4.x or 2.x are both supported via preprocessor compatibility guards in our firmware).

---

## 3. Physical Node Configuration & Flashing (ESP32-C3 Mini)

All 5 nodes use the **exact same sketch**:
`prototype_distance/firmware/node_esp32c3/node_esp32c3.ino`

### 3.1 Arduino IDE Board Settings for Nodes
Select the following settings in the **Tools** menu:
* **Board:** `ESP32C3 Dev Module`
* **USB CDC On Boot:** `Enabled`  *(CRITICAL: Required for Serial output over the C3's internal USB port)*
* **CPU Frequency:** `160MHz (WiFi/BT)`
* **Flash Frequency:** `80MHz`
* **Flash Mode:** `QIO` or `DIO`
* **Flash Size:** `4MB (32Mb)`
* **Partition Scheme:** `Default 4MB with spiffs`
* **Upload Speed:** `921600` (or `115200` if upload fails)
* **Port:** Select the COM port corresponding to your connected ESP32-C3 board.

### 3.2 Flashing Nodes 1 through 5
Before clicking Upload for each physical board, adjust the configuration block at the top of [`node_esp32c3.ino`](file:///e:/SHAPNEST/prototype_distance/firmware/node_esp32c3/node_esp32c3.ino):

#### For Physical Node 1:
```cpp
#define NODE_ID                 1     // Node 1
#define CALIBRATED_RSSI_1M    -59     // Bench reference RSSI @ 1m (dBm)
#define PATH_LOSS_EXP_X10      22     // 2.2
#define TX_POWER_DBM            3     // +3 dBm
```
Click **Upload**. Label the physical board: **NODE_01**.

#### For Physical Node 2:
```cpp
#define NODE_ID                 2     // Node 2
#define CALIBRATED_RSSI_1M    -59     // Adjust if bench calibration differs
#define PATH_LOSS_EXP_X10      22     // 2.2
#define TX_POWER_DBM            3     // +3 dBm
```
Click **Upload**. Label the physical board: **NODE_02**.

#### For Physical Node 3:
```cpp
#define NODE_ID                 3     // Node 3
#define CALIBRATED_RSSI_1M    -59     
#define PATH_LOSS_EXP_X10      22     
#define TX_POWER_DBM            3     
```
Click **Upload**. Label the physical board: **NODE_03**.

#### For Physical Node 4:
```cpp
#define NODE_ID                 4     // Node 4
#define CALIBRATED_RSSI_1M    -59     
#define PATH_LOSS_EXP_X10      22     
#define TX_POWER_DBM            3     
```
Click **Upload**. Label the physical board: **NODE_04**.

#### For Physical Node 5:
```cpp
#define NODE_ID                 5     // Node 5
#define CALIBRATED_RSSI_1M    -59     
#define PATH_LOSS_EXP_X10      22     
#define TX_POWER_DBM            3     
```
Click **Upload**. Label the physical board: **NODE_05**.

### 3.3 Expected Node Serial Monitor Output
Open **Tools $\rightarrow$ Serial Monitor** @ **115,200 baud** (with "Both NL & CR"):
```text
==================================================
# [LOG] SHAPNEST PROXIMITY BEACON — NODE_01
# [LOG] Mode: PURE AUTONOMOUS STATIC BEACON (Zero Runtime Updates)
# [LOG] Protocol: v1 | Magic ID: 0x534E ('SN')
# [LOG] Calibrated RSSI @ 1m: -59 dBm
# [LOG] Environmental Exponent (n): 2.2 (raw: 22)
# [LOG] Configured TX Power: +3 dBm
# [LOG] Autonomous Advertising Interval: 200 ms
==================================================
# [LOG] NODE_01 ACTIVE — Autonomous Hardware Link-Layer Broadcasting.
# [LOG] NODE_01 Beacon Active | TX: +3 dBm | Ref@1m: -59 dBm | n: 2.2 | Uptime: 10 s
```
*Visual check:* The on-board LED will flash $N$ times upon boot (e.g. Node 3 flashes 3 times).

---

## 4. Child Wristband Configuration & Flashing (ESP32-C3 Mini)

Open:
`prototype_distance/firmware/wristband_esp32c3/wristband_esp32c3.ino`

### 4.1 Arduino IDE Board Settings for Wristband
* **Board:** `ESP32C3 Dev Module`
* **USB CDC On Boot:** `Enabled`
* **CPU Frequency:** `160MHz (WiFi/BT)`
* **Flash Size:** `4MB (32Mb)`
* **Partition Scheme:** `Default 4MB with spiffs`
* **Upload Speed:** `921600`
* **Port:** Select the COM port corresponding to your connected wristband board.

### 4.2 Flashing
Click **Upload**. Label the physical board: **WRISTBAND_01**.

### 4.3 Expected Wristband Serial Monitor Output
Open Serial Monitor @ **115,200 baud**:
```text
==================================================
# [LOG] SHAPNEST CHILD WRISTBAND — ESP32-C3 MINI
# [LOG] Wristband ID: 1 | Protocol: v1 (0x534E)
# [LOG] Monitored Nodes: 5 (NODE_01 to NODE_05)
# [LOG] Filter Pipeline: 5-Sample Median + EMA (alpha=0.25)
# [LOG] Distance Bounds: 0.15 m to 8.00 m
# [LOG] Cooperative Time-Slice: 900 ms Scan / 90 ms Uplink
==================================================
# [LOG] Wristband Engine ONLINE — Starting Cooperative Loop.
# [LOG] WB#1 Uplink Seq: 5 | Uptime: 5 s
# [LOG]   NODE_01: 0.82 m | RSSI: -58 dBm | ACTIVE
# [LOG]   NODE_02: 1.47 m | RSSI: -67 dBm | ACTIVE
# [LOG]   NODE_03: OFFLINE
# [LOG]   NODE_04: OFFLINE
# [LOG]   NODE_05: OFFLINE
```

---

## 5. Central Hub Configuration & Flashing (ESP32-WROOM)

Open:
`prototype_distance/firmware/central_hub_esp32wroom/central_hub_esp32wroom.ino`

### 5.1 Arduino IDE Board Settings for Central Hub
* **Board:** `ESP32 Dev Module`
* **Upload Speed:** `921600` (or `115200`)
* **CPU Frequency:** `240MHz (WiFi/BT)`
* **Flash Frequency:** `80MHz`
* **Flash Mode:** `QIO`
* **Flash Size:** `4MB (32Mb)`
* **Partition Scheme:** `Default 4MB with spiffs`
* **Port:** Select the COM port corresponding to your connected ESP32-WROOM board.

*Note for ESP32-WROOM DevKit boards:* If the upload hangs on `Connecting........_____.....`, press and hold the **BOOT** button on the ESP32 board until the flashing percentage begins.

### 5.2 Expected Central Hub Serial Monitor Output
Open Serial Monitor @ **115,200 baud**:
```text
==================================================
# [LOG] SHAPNEST CENTRAL HUB GATEWAY — ESP32-WROOM
# [LOG] Protocol: v1 | Magic ID: 0x534E ('SN')
# [LOG] Target Wristband ID: 1
# [LOG] Max Monitored Nodes: 5
# [LOG] Serial Interface: USB UART @ 115200 baud (NDJSON)
# [LOG] Core 0: NimBLE Continuous Scanner | Core 1: Serializer
==================================================
# [LOG] Central Hub ONLINE — Listening for Child Wristband telemetry...
{"v":1,"hub_status":"ONLINE","seq":1,"wb":{"id":1,"status":"OFFLINE","age_ms":999999,"seq":0},"nodes":[{"id":1,"dist_m":null,"rssi":null,"state":"OFFLINE"},{"id":2,"dist_m":null,"rssi":null,"state":"OFFLINE"},{"id":3,"dist_m":null,"rssi":null,"state":"OFFLINE"},{"id":4,"dist_m":null,"rssi":null,"state":"OFFLINE"},{"id":5,"dist_m":null,"rssi":null,"state":"OFFLINE"}]}
```
When Wristband 1 is powered on and within range, the hub logs:
```text
# [LOG] Wristband #1 CONNECTED (Signal: -54 dBm | Age: 45 ms)
{"v":1,"hub_status":"ONLINE","seq":24,"wb":{"id":1,"status":"ONLINE","age_ms":45,"seq":12},"nodes":[{"id":1,"dist_m":0.82,"rssi":-58,"state":"ACTIVE"},{"id":2,"dist_m":1.47,"rssi":-67,"state":"ACTIVE"},{"id":3,"dist_m":null,"rssi":null,"state":"OFFLINE"},{"id":4,"dist_m":null,"rssi":null,"state":"OFFLINE"},{"id":5,"dist_m":null,"rssi":null,"state":"OFFLINE"}]}
```

---

## 6. End-to-End Bring-Up Verification Sequence

1. **Step 1:** Plug in **Central Hub (ESP32-WROOM)** to PC via USB.
2. **Step 2:** Open Web Application at `http://localhost:8000` in Google Chrome or Microsoft Edge.
3. **Step 3:** Click **`[Connect Hub (USB Serial)]`** and select the Central Hub's COM port.
   * *Verify:* Central Hub status card turns green (`CONNECTED (ONLINE)`).
4. **Step 4:** Power on **Node 1**.
   * *Verify:* Node 1 status LED flashes once on boot.
5. **Step 5:** Power on **Child Wristband (ESP32-C3)**.
   * *Verify:* Within 2 seconds, Wristband card on the Web App turns green (`ONLINE (WRISTBAND #1)`), and Node 01 card transitions to **`ACTIVE`** with live distance bars!
